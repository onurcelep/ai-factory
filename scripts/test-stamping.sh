#!/usr/bin/env bash
# Golden-file behavioural tests for the mechanical stamping semantics of
# /factory-init and /factory-update. Runs fixture inputs through the reference
# implementation (scripts/lib/factory_stamp.py) and diffs the output against
# checked-in golden files, then asserts each transform is idempotent.
#
# The skills are LLM-run prose; this harness is not testing the LLM. It encodes
# the mechanical transforms (marker-block splice, H1-drop + heading demotion,
# settings.json merge) as executable truth so a prose edit that changes what the
# skills stamp gets caught here instead of shipping to every consuming repo.
#
# Usage:
#   scripts/test-stamping.sh            run the checks (used by validate.sh)
#   scripts/test-stamping.sh --regen    rewrite the golden files from current
#                                       templates + reference impl (do this
#                                       deliberately after an intended change to
#                                       a template's standard block, then review
#                                       the golden diff)
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok: $1"; }

REGEN=0
[ "${1:-}" = "--regen" ] && REGEN=1

STAMP=(python3 scripts/lib/factory_stamp.py)
CT=plugins/factory/templates/CLAUDE.md.tmpl
ST=plugins/factory/templates/settings.json
FX=tests/fixtures
VER=0.0.0-test          # pinned so a plugin.json version bump never churns goldens
NAME=sample-project

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# check_or_regen <label> <golden-path> <actual-path>
check_or_regen() {
  local label=$1 golden=$2 actual=$3
  if [ "$REGEN" = 1 ]; then
    cp "$actual" "$golden"
    ok "regenerated $label"
    return
  fi
  [ -f "$golden" ] || fail "$label: golden $golden missing (run: scripts/test-stamping.sh --regen)"
  if ! diff -u "$golden" "$actual" >"$TMP/diff.txt"; then
    echo "----- $label: actual output differs from golden $golden -----" >&2
    cat "$TMP/diff.txt" >&2
    fail "$label: stamping output drifted from golden"
  fi
  ok "$label matches golden"
}

# --- Case 1: fresh CLAUDE.md (no existing file) ---
"${STAMP[@]}" init-claude --template "$CT" --project-name "$NAME" --version "$VER" \
  --project-content "$FX/claude-md/fresh/project-content.md" >"$TMP/fresh.md"
check_or_regen "init/fresh" "$FX/claude-md/fresh/expected.md" "$TMP/fresh.md"
# Idempotency: re-running init on the stamped output is a no-op (markers present).
"${STAMP[@]}" init-claude --template "$CT" --project-name "$NAME" --version "$VER" \
  --existing "$TMP/fresh.md" --project-content "$FX/claude-md/fresh/project-content.md" >"$TMP/fresh2.md"
cmp -s "$TMP/fresh.md" "$TMP/fresh2.md" || fail "init/fresh not idempotent on re-run"
ok "init/fresh idempotent"

# --- Case 2: existing CLAUDE.md, no markers (H1 drop + heading demotion) ---
"${STAMP[@]}" init-claude --template "$CT" --project-name "$NAME" --version "$VER" \
  --existing "$FX/claude-md/existing-no-markers/input.md" >"$TMP/exist.md"
check_or_regen "init/existing-no-markers" "$FX/claude-md/existing-no-markers/expected.md" "$TMP/exist.md"
# Body must survive byte-for-byte: intro paragraph and the in-fence '# ' comment
# must appear verbatim; the old H1 line must be gone.
grep -qF 'Intro paragraph that must survive byte-for-byte.' "$TMP/exist.md" || fail "init/existing lost body text"
grep -qF '# this hash is a shell comment' "$TMP/exist.md" || fail "init/existing demoted an in-fence '#'"
grep -qxF '# Acme Widgets' "$TMP/exist.md" && fail "init/existing kept the old H1 title line"
grep -qxF '### Setup' "$TMP/exist.md" || fail "init/existing did not demote '## Setup' -> '### Setup'"
ok "init/existing-no-markers demotion invariants hold"
# Idempotency: re-running init on the stamped output is a no-op.
"${STAMP[@]}" init-claude --template "$CT" --project-name "$NAME" --version "$VER" \
  --existing "$TMP/exist.md" >"$TMP/exist2.md"
cmp -s "$TMP/exist.md" "$TMP/exist2.md" || fail "init/existing-no-markers not idempotent"
ok "init/existing-no-markers idempotent"

# --- Case 3: markers already present (init is a strict no-op) ---
"${STAMP[@]}" init-claude --template "$CT" --project-name "$NAME" --version "$VER" \
  --existing "$FX/claude-md/markers-present/input.md" >"$TMP/present.md"
cmp -s "$FX/claude-md/markers-present/input.md" "$TMP/present.md" \
  || fail "init/markers-present must return the file byte-identical"
ok "init/markers-present is a no-op"

# --- Case 4: factory-update marker-block splice ---
"${STAMP[@]}" update-splice --template "$CT" --version "$VER" \
  --target "$FX/update/input.md" >"$TMP/update.md"
check_or_regen "update/splice" "$FX/update/expected.md" "$TMP/update.md"
# Nothing outside the markers may change: the repo-owned '## Project' content and
# the H1 must be preserved verbatim; the stale version marker must be gone.
grep -qF 'Repo-owned content that update-splice must preserve exactly, em dash — and all.' "$TMP/update.md" \
  || fail "update/splice altered content outside the markers"
grep -qF '# CLAUDE.md — consuming-repo' "$TMP/update.md" || fail "update/splice altered the H1"
grep -qF 'factory:version 0.0.0-OLD' "$TMP/update.md" && fail "update/splice left the stale version stamp"
grep -qF "factory:version $VER" "$TMP/update.md" || fail "update/splice did not stamp the current version"
ok "update/splice boundary invariants hold"
# Idempotency: splicing the already-current file again changes nothing.
"${STAMP[@]}" update-splice --template "$CT" --version "$VER" --target "$TMP/update.md" >"$TMP/update2.md"
cmp -s "$TMP/update.md" "$TMP/update2.md" || fail "update/splice not idempotent"
ok "update/splice idempotent"

# Preflight: update-splice must refuse a file with no marker block.
if "${STAMP[@]}" update-splice --template "$CT" --version "$VER" \
     --target "$FX/claude-md/existing-no-markers/input.md" >/dev/null 2>&1; then
  fail "update/splice must fail on a file with no marker block"
fi
ok "update/splice rejects an unstamped file"

# --- Case 5: settings.json merge ---
"${STAMP[@]}" merge-settings --template "$ST" --target "$FX/settings/input.json" >"$TMP/settings.json"
check_or_regen "settings/merge" "$FX/settings/expected.json" "$TMP/settings.json"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/settings.json" \
  || fail "settings/merge produced invalid JSON"
# Repo keys preserved; template wiring added.
python3 - "$TMP/settings.json" "$ST" <<'PY' || fail "settings/merge lost a repo key or template wiring"
import json, sys
merged = json.load(open(sys.argv[1]))
tmpl = json.load(open(sys.argv[2]))
assert merged.get("permissions", {}).get("allow") == ["Bash(npm test)"], "repo permissions dropped"
assert merged["enabledPlugins"].get("some-other-plugin@some-market") is True, "repo plugin dropped"
for k, v in tmpl["enabledPlugins"].items():
    assert merged["enabledPlugins"].get(k) == v, f"template plugin {k} missing"
for k, v in tmpl["extraKnownMarketplaces"].items():
    assert merged["extraKnownMarketplaces"].get(k) == v, f"template marketplace {k} missing"
PY
ok "settings/merge preserves repo keys and adds template wiring"
# Idempotency: merging the already-merged file again changes nothing.
"${STAMP[@]}" merge-settings --template "$ST" --target "$TMP/settings.json" >"$TMP/settings2.json"
cmp -s "$TMP/settings.json" "$TMP/settings2.json" || fail "settings/merge not idempotent"
ok "settings/merge idempotent"

# --- Case 6: settings.json merge preserves a consumer's ref/sha pin ---
"${STAMP[@]}" merge-settings --template "$ST" --target "$FX/settings/pinned-input.json" >"$TMP/pinned.json"
check_or_regen "settings/pinned-merge" "$FX/settings/pinned-expected.json" "$TMP/pinned.json"
python3 - "$TMP/pinned.json" <<'PYEOF' || fail "settings/pinned-merge lost the repo's ref/sha pin"
import json, sys
src = list(json.load(open(sys.argv[1]))["extraKnownMarketplaces"].values())[0]["source"]
assert src.get("ref") == "v0.5.0", "ref pin dropped"
assert src.get("sha", "").startswith("0123456789"), "sha pin dropped"
PYEOF
ok "settings/pinned-merge preserves the stability pin"
# Idempotency
"${STAMP[@]}" merge-settings --template "$ST" --target "$TMP/pinned.json" >"$TMP/pinned2.json"
cmp -s "$TMP/pinned.json" "$TMP/pinned2.json" || fail "settings/pinned-merge not idempotent"
ok "settings/pinned-merge idempotent"

echo "STAMPING TESTS PASSED"
