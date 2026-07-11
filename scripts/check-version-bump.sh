#!/usr/bin/env bash
# Version-bump guard. If the diff against the merge base touches any template
# under plugins/factory/templates/**, the plugin version in
# plugins/factory/.claude-plugin/plugin.json MUST change (and not go backwards).
# Skill-only and doc-only changes are deliberately exempt — see
# docs/OPERATIONS.md "When to bump the plugin version".
#
# Usage: check-version-bump.sh [base-ref]   (default base-ref: origin/main)
# Exit:  0 = pass or gracefully skipped (no derivable merge base / baseline)
#        1 = templates changed without a forward version bump
#
# Dependency-free: git, python3, and sort -V are all present on the runners
# and in local dev. Shared by .github/workflows/version-guard.yml and
# scripts/validate.sh so there is one source of truth for the rule.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${1:-origin/main}"
TEMPLATES="plugins/factory/templates"
PLUGIN_JSON="plugins/factory/.claude-plugin/plugin.json"

read_version() { python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"; }

# Derive the merge base. Skip gracefully when it can't be resolved (shallow
# clone with no shared history, detached checkout, missing base ref) — the
# guard is advisory locally and authoritative only in CI where full history
# is fetched.
if ! MB=$(git merge-base HEAD "$BASE" 2>/dev/null); then
  echo "version-bump-guard: no merge base against '$BASE' — skipping (nothing to compare)."
  exit 0
fi

# Did any template change between the merge base and the working tree?
if git diff --quiet "$MB" -- "$TEMPLATES" 2>/dev/null; then
  echo "version-bump-guard: no template changes vs ${MB:0:12} — no bump required."
  exit 0
fi

old_ver=$(git show "$MB:$PLUGIN_JSON" 2>/dev/null | read_version 2>/dev/null || echo "")
new_ver=$(read_version < "$PLUGIN_JSON")

if [ -z "$old_ver" ]; then
  echo "version-bump-guard: could not read baseline version at ${MB:0:12} — skipping."
  exit 0
fi

changed_files() { git diff --name-only "$MB" -- "$TEMPLATES" | sed 's/^/        /'; }

if [ "$old_ver" = "$new_ver" ]; then
  {
    echo "FAIL: templates changed but $PLUGIN_JSON version is unchanged ($new_ver)."
    echo "      The version is the propagation trigger and comparison key: an unbumped"
    echo "      template change silently never reaches consumers. Bump it."
    echo "      See docs/OPERATIONS.md 'When to bump the plugin version'."
    echo "      Changed template files:"
    changed_files
  } >&2
  exit 1
fi

highest=$(printf '%s\n%s\n' "$old_ver" "$new_ver" | sort -V | tail -1)
if [ "$highest" != "$new_ver" ]; then
  {
    echo "FAIL: $PLUGIN_JSON version went backwards ($old_ver -> $new_ver) while templates changed."
    echo "      Bump to a version greater than $old_ver."
  } >&2
  exit 1
fi

echo "version-bump-guard: templates changed and version bumped $old_ver -> $new_ver."
exit 0
