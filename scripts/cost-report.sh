#!/usr/bin/env bash
# Fleet cost observability for factory-stamped repos.
#
# Enumerates the owner's factory-stamped repos (same CLAUDE.md stamp
# detection the propagation workflow uses), lists recent Claude workflow
# runs in a given month, and extracts each run's `total_cost_usd` from its
# run log (the value the claude-code-action prints in its result JSON).
# Prints a per-repo, per-workflow table plus a grand total.
#
# Dependencies: gh (authenticated) + python3 only. No external services.
#
# Degrades gracefully: GitHub retains Actions logs for a limited window
# (default 90 days), so older runs' costs are unrecoverable. Runs whose log
# is gone, is still in progress, or never emitted a cost are counted and
# reported as "unseen" rather than silently dropped — the report tells you
# what it could NOT measure instead of pretending completeness.
#
# Usage:
#   scripts/cost-report.sh [--month YYYY-MM] [--owner OWNER] [--limit N]
#
#   --month   month to report, UTC (default: current month)
#   --owner   GitHub owner to scan (default: the authenticated gh user)
#   --limit   max runs to inspect per repo per workflow (default: 100)
#
# Suggested cadence: run on the 1st of each month for the month just ended
#   (e.g. `scripts/cost-report.sh --month "$(date -u -v-1m +%Y-%m 2>/dev/null || date -u -d 'last month' +%Y-%m)"`)
#   before logs for that month start aging out. See docs/OPERATIONS.md.
set -euo pipefail

MONTH="$(date -u +%Y-%m)"
OWNER=""
LIMIT=100

while [ $# -gt 0 ]; do
  case "$1" in
    --month) MONTH="$2"; shift 2;;
    --owner) OWNER="$2"; shift 2;;
    --limit) LIMIT="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

case "$MONTH" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]) : ;;
  *) echo "--month must be YYYY-MM (got: $MONTH)" >&2; exit 2;;
esac

if [ -z "$OWNER" ]; then
  OWNER=$(gh api user --jq .login 2>/dev/null) || { echo "cannot determine owner; pass --owner" >&2; exit 1; }
fi

echo "Fleet cost report — owner ${OWNER}, month ${MONTH} (UTC)" >&2
echo "Scanning stamped repos… (log downloads make this slow for busy months)" >&2

# Collect one TSV record per run: repo <TAB> workflow <TAB> run_id <TAB> cost_or_empty <TAB> reason
# reason is empty when cost was captured, else a short why-not-measured token.
records="$(mktemp)"
trap 'rm -f "$records"' EXIT

stamped_count=0

# Only these workflows run a model and therefore incur cost. Matched by the
# workflow's display name (case-insensitive substring) so it survives repos
# that renamed the file. Propagation runs no model and is intentionally out.
is_costed_workflow() {
  printf '%s' "$1" | grep -qiE 'claude|frontier'
}

for repo in $(gh repo list "$OWNER" --limit 200 --json name --jq '.[].name' 2>/dev/null); do
  # Same stamp detection as .github/workflows/factory-propagate.yml.
  claude_md=$(gh api "repos/$OWNER/$repo/contents/CLAUDE.md" --jq .content 2>/dev/null | base64 -d 2>/dev/null) || continue
  printf '%s' "$claude_md" | grep -q 'factory:standard:begin' || continue
  stamped_count=$((stamped_count + 1))
  echo "  $OWNER/$repo: stamped — listing runs" >&2

  # Runs for this repo, newest first; filter to the month + costed workflows in python-free jq.
  run_json=$(gh run list -R "$OWNER/$repo" --limit "$LIMIT" \
      --json databaseId,workflowName,createdAt,conclusion,status 2>/dev/null) || { echo "    (could not list runs)" >&2; continue; }

  # Emit "id<TAB>workflow" for runs created in MONTH; filtering by prefix.
  while IFS=$'\t' read -r run_id wf; do
    [ -n "$run_id" ] || continue
    is_costed_workflow "$wf" || continue
    log=$(gh run view "$run_id" -R "$OWNER/$repo" --log 2>/dev/null) || {
      printf '%s\t%s\t%s\t\tlog-unavailable\n' "$repo" "$wf" "$run_id" >>"$records"; continue; }
    # The action prints `"total_cost_usd": <n>` in its result JSON (note the
    # space after the colon). grep -o exits 1 on no match; with pipefail+set
    # -e that would abort the whole report, so tolerate it (cost-unknown).
    cost=$(printf '%s' "$log" | grep -oE '"total_cost_usd":[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+' | tail -1 || true)
    if [ -n "$cost" ]; then
      printf '%s\t%s\t%s\t%s\t\n' "$repo" "$wf" "$run_id" "$cost" >>"$records"
    else
      printf '%s\t%s\t%s\t\tno-cost-in-log\n' "$repo" "$wf" "$run_id" >>"$records"
    fi
  done < <(printf '%s' "$run_json" | python3 -c '
import json, sys
month = sys.argv[1]
try:
    runs = json.load(sys.stdin)
except Exception:
    runs = []
for r in runs:
    if str(r.get("createdAt","")).startswith(month):
        print("%s\t%s" % (r.get("databaseId",""), r.get("workflowName","")))
' "$MONTH")
done

# Render the table + totals + a plain accounting of what could not be measured.
python3 -c '
import sys, collections
records_path, owner, month, stamped = sys.argv[1:5]
rows = []
with open(records_path) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 5:
            continue
        repo, wf, run_id, cost, reason = parts
        rows.append((repo, wf, run_id, cost, reason))

agg = collections.OrderedDict()  # (repo, wf) -> [runs, measured, sum_cost, unseen]
grand_cost = 0.0
grand_runs = grand_measured = grand_unseen = 0
unseen_reasons = collections.Counter()
for repo, wf, run_id, cost, reason in rows:
    key = (repo, wf)
    a = agg.setdefault(key, [0, 0, 0.0, 0])
    a[0] += 1; grand_runs += 1
    if cost:
        c = float(cost)
        a[1] += 1; a[2] += c; grand_measured += 1; grand_cost += c
    else:
        a[3] += 1; grand_unseen += 1; unseen_reasons[reason or "unknown"] += 1

print()
print("=" * 78)
print("Fleet cost report  |  owner %s  |  month %s (UTC)" % (owner, month))
print("stamped repos scanned: %s" % stamped)
print("=" * 78)
if not rows:
    print("No Claude workflow runs found in this month across stamped repos.")
    print("(This is fine: nothing ran, or all logs for the month have expired.)")
    sys.exit(0)

hdr = "%-28s %-22s %5s %5s %12s" % ("repo", "workflow", "runs", "cost?", "cost USD")
print(hdr)
print("-" * len(hdr))
last_repo = None
for (repo, wf), (runs, measured, cost_sum, unseen) in agg.items():
    shown_repo = repo if repo != last_repo else ""
    last_repo = repo
    print("%-28s %-22s %5d %5d %12.4f" % (shown_repo[:28], wf[:22], runs, measured, cost_sum))
print("-" * len(hdr))
print("%-28s %-22s %5d %5d %12.4f" % ("TOTAL", "", grand_runs, grand_measured, grand_cost))
print()
print("Measured %d of %d runs. %d run(s) had no recoverable cost:" % (grand_measured, grand_runs, grand_unseen))
for reason, n in unseen_reasons.most_common():
    label = {
        "log-unavailable": "log expired or run still in progress",
        "no-cost-in-log":  "log present but no total_cost_usd emitted",
    }.get(reason, reason)
    print("  - %d: %s" % (n, label))
print()
print("Costs shown are only what the run logs still contain. Unmeasured runs")
print("are NOT zero-cost — GitHub retains Actions logs ~90 days, so older")
print("runs are simply unrecoverable. Run monthly to capture costs before they age out.")
' "$records" "$OWNER" "$MONTH" "$stamped_count"
