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
for f in claude.yml claude-code-review.yml settings.json CLAUDE.md.tmpl AGENTS.md.tmpl MEMORY.md.tmpl ci-claude-silent-failures.md; do
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
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$T/claude.yml" || fail "claude.yml must use CLAUDE_CODE_OAUTH_TOKEN"
grep -q 'claude-sonnet-5 --max-turns 40' "$T/claude.yml" || fail "claude.yml must pin sonnet turn-capped"
grep -q 'model opus' "$T/claude-code-review.yml" || fail "review workflow must pin opus"
grep -q 'cancel-in-progress: true' "$T/claude-code-review.yml" || fail "review workflow must cancel superseded runs"
grep -q 'docs/memory' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl standard block must point at docs/memory"
grep -q 'factory:version {{FACTORY_VERSION}}' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl must carry the version stamp placeholder"
grep -q 'factory:repo-memory' "$T/MEMORY.md.tmpl" || fail "MEMORY.md.tmpl must reference the repo-memory skill"
grep -q 'ci-claude-silent-failures.md' "$T/MEMORY.md.tmpl" || fail "MEMORY.md.tmpl must index the seeded CI fact file"
grep -q 'factory:ci-agent-ops' "$T/ci-claude-silent-failures.md" || fail "seeded CI fact must point at the ci-agent-ops skill"
ok "templates"

# --- Task 4: factory-init skill ---
FI=plugins/factory/skills/factory-init/SKILL.md
[ -f "$FI" ] || fail "$FI missing"
grep -q 'CLAUDE_PLUGIN_ROOT' "$FI" || fail "factory-init must reference CLAUDE_PLUGIN_ROOT templates"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$FI" || fail "factory-init must mention the auth secret"
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

echo "ALL CHECKS PASSED"
