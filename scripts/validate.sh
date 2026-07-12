#!/usr/bin/env bash
# Validation suite for ai-factory. Each block is a check; first failure exits 1.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok: $1"; }

json_valid() { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; }

# --- Task 1: manifests ---
# The marketplace name and repo slug are derived, not hardcoded, so the
# suite validates any fork (see scripts/rebrand.sh) by checking cross-file
# consistency instead of owner-specific literals.
[ -f .claude-plugin/marketplace.json ] || fail "marketplace.json missing"
json_valid .claude-plugin/marketplace.json || fail "marketplace.json is not valid JSON"
MKT=$(python3 -c "import json; print(json.load(open('.claude-plugin/marketplace.json'))['name'])") \
  || fail "marketplace.json must have a name"
[ -n "$MKT" ] || fail "marketplace name must be non-empty"
[ "$MKT" != "factory" ] || fail "marketplace name must differ from the plugin name 'factory'"
grep -q '"name": "factory"' .claude-plugin/marketplace.json || fail "marketplace must list plugin 'factory'"
[ -f plugins/factory/.claude-plugin/plugin.json ] || fail "plugin.json missing"
json_valid plugins/factory/.claude-plugin/plugin.json || fail "plugin.json is not valid JSON"
ok "manifests (marketplace '$MKT')"

# --- Task 2: shared skills ---
for s in model-routing release-flow repo-memory ci-agent-ops factory-init factory-update factory-status; do
  f="plugins/factory/skills/$s/SKILL.md"
  [ -f "$f" ] || fail "$f missing"
  head -1 "$f" | grep -q '^---$' || fail "$f missing frontmatter"
  grep -q '^name: ' "$f" || fail "$f missing name field"
  grep -q '^description: ' "$f" || fail "$f missing description field"
done
ok "shared skills"

# --- Task 3: templates ---
T=plugins/factory/templates
for f in claude.yml claude-code-review.yml claude-smoke-test.yml settings.json CLAUDE.md.tmpl AGENTS.md.tmpl MEMORY.md.tmpl ci-claude-silent-failures.md; do
  [ -f "$T/$f" ] || fail "$T/$f missing"
done
json_valid "$T/settings.json" || fail "settings.json template is not valid JSON"
SLUG=$(python3 -c "import json; print(json.load(open('$T/settings.json'))['extraKnownMarketplaces']['$MKT']['source']['repo'])" 2>/dev/null) \
  || fail "settings.json must wire marketplace '$MKT' to a github repo"
[ -n "$SLUG" ] || fail "settings.json marketplace '$MKT' must name a repo slug"
grep -q "\"factory@$MKT\": true" "$T/settings.json" || fail "settings.json must enable factory@$MKT"
# factory@$MKT is the only structurally required plugin. Additional enabled
# plugins (the shipped template also enables superpowers as the author's
# default process layer) are allowed but intentionally not required by name,
# so a fork can drop or swap the process layer without patching this suite.
grep -qF '<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing begin marker"
grep -qF '<!-- factory:standard:end -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing end marker"
# Either credential is valid: CLAUDE_CODE_OAUTH_TOKEN (subscription, the
# shipped default) or ANTHROPIC_API_KEY (API-billing forks) — see
# docs/FORKING.md "Billing: subscription or API key".
grep -qE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' "$T/claude.yml" || fail "claude.yml must wire an auth secret (CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY)"
# Models are a fork-class choice (docs/FORKING.md "Choosing your models"):
# the suite
# enforces the incident-earned invariants — every workflow pins a model
# explicitly and probe/responder runs are turn-capped — never the author's
# specific model names, so a fork can reroute models without patching this.
grep -qE -- '--model [^ '"'"']+' "$T/claude.yml" || fail "claude.yml must pin a model explicitly (--model ...)"
grep -qE -- '--max-turns [0-9]+' "$T/claude.yml" || fail "claude.yml must carry a turn cap (--max-turns N)"
grep -qE -- '--model [^ '"'"']+' "$T/claude-code-review.yml" || fail "review workflow must pin a model explicitly (--model ...)"
grep -q 'cancel-in-progress: true' "$T/claude-code-review.yml" || fail "review workflow must cancel superseded runs"
grep -q 'docs/memory' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl standard block must point at docs/memory"
grep -q 'factory:version {{FACTORY_VERSION}}' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl must carry the version stamp placeholder"
grep -q 'factory:repo-memory' "$T/MEMORY.md.tmpl" || fail "MEMORY.md.tmpl must reference the repo-memory skill"
grep -q 'ci-claude-silent-failures.md' "$T/MEMORY.md.tmpl" || fail "MEMORY.md.tmpl must index the seeded CI fact file"
grep -q 'factory:ci-agent-ops' "$T/ci-claude-silent-failures.md" || fail "seeded CI fact must point at the ci-agent-ops skill"
# Silent-failure detection (issue #17): a scheduled smoke test + post-run
# assertions on the dead-on-arrival signature. Both the scheduled probe and
# the assertion steps parse the action's documented `execution_file` output.
grep -qE -- '--model [^ '"'"']+' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must pin a model explicitly (--model ...)"
grep -qE -- '--max-turns [0-9]+' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must carry a turn cap (--max-turns N)"
grep -q 'cron:' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must run on a schedule (off-minute cron)"
grep -q 'cancel-in-progress: true' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must use a concurrency group"
grep -q 'execution_file' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must assert on the action's execution_file output"
grep -q 'is_error' "$T/claude-smoke-test.yml" || fail "smoke-test workflow must check the dead-on-arrival is_error signature"
grep -q 'execution_file' "$T/claude.yml" || fail "claude.yml must assert on the action's execution_file output"
grep -q 'execution_file' "$T/claude-code-review.yml" || fail "review workflow must assert on the action's execution_file output"
ok "templates"

# --- Task 4: factory-init skill ---
FI=plugins/factory/skills/factory-init/SKILL.md
[ -f "$FI" ] || fail "$FI missing"
grep -q 'CLAUDE_PLUGIN_ROOT' "$FI" || fail "factory-init must reference CLAUDE_PLUGIN_ROOT templates"
grep -qE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' "$FI" || fail "factory-init must mention the auth secret"
grep -qF 'factory:standard:begin' "$FI" || fail "factory-init must document the markers"
ok "factory-init skill"

# --- Task 5: factory-update skill ---
FU=plugins/factory/skills/factory-update/SKILL.md
[ -f "$FU" ] || fail "$FU missing"
grep -qF 'factory:standard:begin' "$FU" || fail "factory-update must document the markers"
grep -q 'never' "$FU" || fail "factory-update must state it never touches project content"
ok "factory-update skill"

# --- Dogfood: stamped workflow copies must match their templates ---
# ai-factory consumes its own review workflow. Any workflow that shares a
# basename with a template must stay byte-identical to it, so templates/
# remains the single source of truth. Re-sync with:
#   cp plugins/factory/templates/<name> .github/workflows/<name>
for w in .github/workflows/*.yml; do
  t="$T/$(basename "$w")"
  [ -f "$t" ] || continue
  cmp -s "$t" "$w" || fail "$(basename "$w") drifted from its template — re-copy from $T"
done
ok "dogfooded workflows match templates"

# --- Fix: workflows must self-load the factory plugin (Action ignores repo settings.json) ---
grep -q "factory@$MKT" plugins/factory/templates/claude.yml || fail "claude.yml template must load factory@$MKT via plugins input"
grep -q "factory@$MKT" plugins/factory/templates/claude-code-review.yml || fail "review template must load factory@$MKT via plugins input"
grep -q "github.com/$SLUG" plugins/factory/templates/claude.yml || fail "claude.yml template must reference the $SLUG marketplace URL"
grep -q "github.com/$SLUG" plugins/factory/templates/claude-code-review.yml || fail "review template must reference the $SLUG marketplace URL"
ok "workflow plugin self-loading (repo $SLUG)"

# --- Propagation + operations doc ---
PW=.github/workflows/factory-propagate.yml
[ -f "$PW" ] || fail "factory-propagate.yml missing"
grep -q 'FACTORY_PROPAGATE_TOKEN' "$PW" || fail "propagate workflow must gate on FACTORY_PROPAGATE_TOKEN"
grep -q 'factory:standard:begin' "$PW" || fail "propagate workflow must detect the stamp marker"
grep -q 'factory:version' "$PW" || fail "propagate workflow must read the version stamp"
[ -f docs/OPERATIONS.md ] || fail "docs/OPERATIONS.md missing"
grep -q 'factory-propagate' docs/OPERATIONS.md || fail "OPERATIONS.md must document propagation setup"
grep -q 'FACTORY_PROPAGATE_TOKEN' docs/OPERATIONS.md || fail "OPERATIONS.md must document the propagation token"
ok "propagation + operations doc"

# --- Stamping semantics: golden-file behavioural tests ---
# validate.sh above checks file presence and string content; this asserts the
# init/update transforms still behave. The reference implementation encodes the
# mechanical stamping semantics; a skill-prose edit that changes them fails here.
[ -f scripts/test-stamping.sh ] || fail "scripts/test-stamping.sh missing"
bash scripts/test-stamping.sh || fail "stamping golden-file tests failed (see output above)"
ok "stamping semantics (golden-file tests)"

# --- Version-bump guard: template changes require a plugin.json version bump ---
# CI enforces this on PRs via .github/workflows/version-guard.yml; the same
# script runs here so a local ./scripts/validate.sh catches it before push.
# It skips gracefully when no merge base is derivable (e.g. fresh clone).
[ -x scripts/check-version-bump.sh ] || fail "scripts/check-version-bump.sh missing or not executable"
[ -f .github/workflows/version-guard.yml ] || fail "version-guard.yml missing"
grep -q 'check-version-bump.sh' .github/workflows/version-guard.yml || fail "version-guard.yml must invoke check-version-bump.sh"
scripts/check-version-bump.sh || fail "template change without a version bump (see message above)"
ok "version-bump guard"

# --- Skills channel pin/rollback story (issue #16) ---
# The skills channel auto-propagates from main with no version gate, so the
# rollback runbook + per-environment convergence table + the opt-in consumer
# pin are the whole safety story — they must not silently disappear.
grep -q 'Rolling back a bad skill' docs/OPERATIONS.md || fail "OPERATIONS.md must carry the skill-rollback runbook"
grep -q 'Convergence time per environment' docs/OPERATIONS.md || fail "OPERATIONS.md must document per-environment convergence for a skill rollback"
grep -q 'extraKnownMarketplaces' docs/OPERATIONS.md || fail "OPERATIONS.md must document the opt-in consumer pin (extraKnownMarketplaces ref/sha)"
ok "skills channel pin/rollback story"

# --- Security model doc + cost report ---
[ -f docs/SECURITY-MODEL.md ] || fail "docs/SECURITY-MODEL.md missing"
grep -q 'SECURITY-MODEL.md' docs/DECISIONS.md || fail "decisions table must link SECURITY-MODEL.md"
[ -f scripts/cost-report.sh ] || fail "scripts/cost-report.sh missing"
bash -n scripts/cost-report.sh || fail "scripts/cost-report.sh has a syntax error"
grep -q 'total_cost_usd' scripts/cost-report.sh || fail "cost-report.sh must extract total_cost_usd"
ok "security model doc + cost report"

# --- Plugin agents: routed agent definitions carry the model-routing pins ---
for a in factory-implementer factory-reviewer factory-researcher; do
  f="plugins/factory/agents/$a.md"
  [ -f "$f" ] || fail "$f missing"
  head -1 "$f" | grep -q '^---$' || fail "$f missing frontmatter"
  grep -q '^name: ' "$f" || fail "$f missing name field"
  grep -q '^description: ' "$f" || fail "$f missing description field"
  grep -q '^model: ' "$f" || fail "$f missing model pin (the whole point)"
done
# Which tier each agent pins is a fork-class choice (docs/FORKING.md
# "Choosing your models"); the loop above already enforces that every agent
# pins one.
grep -q 'factory-implementer' plugins/factory/skills/model-routing/SKILL.md || fail "model-routing skill must reference the shipped agents"
ok "plugin agents (routing pins)"

# --- Plugin hooks: protect-main guard ---
json_valid plugins/factory/hooks/hooks.json || fail "hooks.json is not valid JSON"
grep -q 'protect-main.sh' plugins/factory/hooks/hooks.json || fail "hooks.json must wire protect-main.sh"
[ -x plugins/factory/hooks/protect-main.sh ] || fail "protect-main.sh missing or not executable"
bash -n plugins/factory/hooks/protect-main.sh || fail "protect-main.sh has bash syntax errors"
grep -q 'FACTORY_ALLOW_MAIN_PUSH' plugins/factory/hooks/protect-main.sh || fail "protect-main.sh must carry the escape hatch"
grep -q 'factory:standard:begin' plugins/factory/hooks/protect-main.sh || fail "protect-main.sh must scope itself to stamped repos"
ok "plugin hooks (protect-main)"

# --- Round-2 wiring: sticky review comment, init canary, decisions rows ---
grep -q 'use_sticky_comment: true' plugins/factory/templates/claude-code-review.yml || fail "review template must use a sticky comment"
grep -q 'Init canary' .github/prompts/frontier-audit.md || fail "frontier-audit prompt must carry the init canary"
grep -q 'claude-smoke-test' docs/DECISIONS.md || fail "decisions table must cover the smoke test"
grep -q 'factory_stamp.py' docs/DECISIONS.md || fail "decisions table must cover the golden tests"
grep -q 'version-guard' docs/DECISIONS.md || fail "decisions table must cover the version guard"
ok "round-2 wiring (sticky review, canary, decisions rows)"

# --- CI self-reporting: failing runs explain themselves ---
for f in claude.yml claude-code-review.yml claude-smoke-test.yml; do
  grep -q 'factory:ci-self-report' "$T/$f" || fail "$f must carry the self-report mechanism"
done
grep -q 'pull-requests: write' "$T/claude-code-review.yml" || fail "review template needs pull-requests:write for the self-report comment (PR comments use this scope, not issues:write)"
grep -q 'issues: write' "$T/claude-smoke-test.yml" || fail "smoke template needs issues:write for the health issue"
grep -q 'anti-tamper' "$T/claude-code-review.yml" || fail "review assertion must discriminate the anti-tamper skip"
grep -q 'Self-reports' plugins/factory/skills/ci-agent-ops/SKILL.md || fail "ci-agent-ops must document the self-reports"
ok "CI self-reporting"

# --- Role contracts: instructions × permissions must reconcile ---
# Incident 2026-07-12: a change-agent gate in CLAUDE.md sent the read-only
# reviewer into 56 permission denials and it posted no review under a green
# check. Instructions that command actions must scope themselves by role,
# and load-bearing allowlists must stay scoped (docs/SECURITY-MODEL.md
# "Role contracts").
grep -q 'Scope by role' CLAUDE.md || fail "CLAUDE.md must scope its gates by agent role (read-only agents cannot run them)"
grep -q 'Role contracts' docs/SECURITY-MODEL.md || fail "SECURITY-MODEL.md must document the role contracts"
FA=.github/workflows/frontier-audit.yml
grep -q -- '--allowedTools' "$FA" || fail "frontier-audit must pin a scoped --allowedTools (load-bearing: SECURITY-MODEL.md)"
if grep -o -- '--allowedTools [^ ]*' "$FA" | tr ' ,' '\n\n' | grep -qx 'Bash'; then
  fail "frontier-audit must not allow bare Bash (WebFetch + push rights job)"
fi
grep -q '"role": "readonly"' evals/cases/release-flow.json || fail "cross-role behavioral eval missing (release-flow role: readonly)"
ok "role contracts"

# --- Docs map: the navigation layer must stay wired ---
# Each audience has one entry door; these checks keep the doors linked so
# a new doc or a rename can't silently orphan part of the map.
[ -f docs/WORKING.md ] || fail "docs/WORKING.md missing"
[ -f CONTRIBUTING.md ] || fail "CONTRIBUTING.md missing"
# No orphan docs: every top-level doc must be reachable from the hub's
# "Where to go" table — a new or renamed doc that isn't wired in fails here.
for d in docs/*.md; do
  grep -qF "$d" README.md || fail "README 'Where to go' must link $d (no orphan docs)"
done
grep -q 'CONTRIBUTING.md' README.md || fail "README must link CONTRIBUTING.md (Where to go)"
# Agent entry point: the repo's own CLAUDE.md orients agents working here.
[ -f CLAUDE.md ] || fail "CLAUDE.md (agent entry point) missing"
grep -q 'validate.sh' CLAUDE.md || fail "CLAUDE.md must point agents at validate.sh"
grep -q 'CONTRIBUTING.md' CLAUDE.md || fail "CLAUDE.md must point agents at CONTRIBUTING.md"
grep -q 'WORKING.md' docs/OPERATIONS.md || fail "OPERATIONS.md must cross-link its WORKING.md pair"
grep -q 'OPERATIONS.md' docs/WORKING.md || fail "WORKING.md must cross-link its OPERATIONS.md pair"
grep -q 'evals/cases' CONTRIBUTING.md || fail "CONTRIBUTING must state the eval-case-per-skill rule"
grep -q 'validate.sh' CONTRIBUTING.md || fail "CONTRIBUTING must require validate.sh before pushing"
ok "docs map"

# --- Skill evals: unit tests + Tier 2 trigger/routing (deterministic, no tokens) ---
python3 -m unittest discover -s tests -q || fail "eval runner unit tests failed"
python3 scripts/run-evals.py || fail "skill evals (tier 2) failed"
ok "skill evals (tier 2)"

echo "ALL CHECKS PASSED"
