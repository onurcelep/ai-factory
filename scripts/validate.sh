#!/usr/bin/env bash
# Validation suite for ai-factory. Each block is a check; first failure exits 1.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok: $1"; }

json_valid() { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; }

# --- Task 1: manifests ---
[ -f .claude-plugin/marketplace.json ] || fail "marketplace.json missing"
json_valid .claude-plugin/marketplace.json || fail "marketplace.json is not valid JSON"
grep -q '"name": "onur"' .claude-plugin/marketplace.json || fail "marketplace name must be 'onur'"
grep -q '"name": "factory"' .claude-plugin/marketplace.json || fail "marketplace must list plugin 'factory'"
[ -f plugins/factory/.claude-plugin/plugin.json ] || fail "plugin.json missing"
json_valid plugins/factory/.claude-plugin/plugin.json || fail "plugin.json is not valid JSON"
ok "manifests"

# --- Task 2: shared skills ---
for s in model-routing release-flow repo-memory factory-init factory-update; do
  f="plugins/factory/skills/$s/SKILL.md"
  [ -f "$f" ] || fail "$f missing"
  head -1 "$f" | grep -q '^---$' || fail "$f missing frontmatter"
  grep -q '^name: ' "$f" || fail "$f missing name field"
  grep -q '^description: ' "$f" || fail "$f missing description field"
done
ok "shared skills"

# --- Task 3: templates ---
T=plugins/factory/templates
for f in claude.yml claude-code-review.yml settings.json CLAUDE.md.tmpl AGENTS.md.tmpl MEMORY.md.tmpl; do
  [ -f "$T/$f" ] || fail "$T/$f missing"
done
json_valid "$T/settings.json" || fail "settings.json template is not valid JSON"
grep -q 'onurcelep/ai-factory' "$T/settings.json" || fail "settings.json must reference onurcelep/ai-factory"
grep -q 'factory@onur' "$T/settings.json" || fail "settings.json must enable factory@onur"
grep -q 'superpowers@claude-plugins-official' "$T/settings.json" || fail "settings.json must enable superpowers"
grep -qF '<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing begin marker"
grep -qF '<!-- factory:standard:end -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing end marker"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$T/claude.yml" || fail "claude.yml must use CLAUDE_CODE_OAUTH_TOKEN"
grep -q 'claude-sonnet-5 --max-turns 10' "$T/claude.yml" || fail "claude.yml must pin sonnet turn-capped"
grep -q 'model opus' "$T/claude-code-review.yml" || fail "review workflow must pin opus"
grep -q 'cancel-in-progress: true' "$T/claude-code-review.yml" || fail "review workflow must cancel superseded runs"
grep -q 'docs/memory' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl standard block must point at docs/memory"
grep -q 'factory:repo-memory' "$T/MEMORY.md.tmpl" || fail "MEMORY.md.tmpl must reference the repo-memory skill"
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

# --- Fix: workflows must self-load the factory plugin (Action ignores repo settings.json) ---
grep -q "factory@onur" plugins/factory/templates/claude.yml || fail "claude.yml template must load factory@onur via plugins input"
grep -q "factory@onur" plugins/factory/templates/claude-code-review.yml || fail "review template must load factory@onur via plugins input"
grep -q 'onurcelep/ai-factory' plugins/factory/templates/claude.yml || fail "claude.yml template must reference the onur marketplace URL"
grep -q 'onurcelep/ai-factory' plugins/factory/templates/claude-code-review.yml || fail "review template must reference the onur marketplace URL"
ok "workflow plugin self-loading"

echo "ALL CHECKS PASSED"
