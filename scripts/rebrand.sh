#!/usr/bin/env bash
# Point this ai-factory fork at your own GitHub repo and marketplace name.
#
# Usage: scripts/rebrand.sh <github-owner>/<repo> [marketplace-name]
#
# The marketplace name defaults to the GitHub owner. Rewrites every
# functional reference (manifests, templates, README) and re-runs the
# validation suite. Idempotent: running it again with the same values
# changes nothing. Owner/author display names in the two manifests are
# attribution, not wiring; update them by hand if you want.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 1 ] || { echo "usage: $0 <github-owner>/<repo> [marketplace-name]" >&2; exit 1; }
NEW_SLUG=$1
NEW_MKT=${2:-${NEW_SLUG%%/*}}
case "$NEW_SLUG" in
  */*) ;;
  *) echo "error: first argument must be <github-owner>/<repo>" >&2; exit 1 ;;
esac
[ "$NEW_MKT" != "factory" ] || { echo "error: marketplace name 'factory' collides with the plugin name" >&2; exit 1; }

OLD_MKT=$(python3 -c "import json; print(json.load(open('.claude-plugin/marketplace.json'))['name'])")
OLD_SLUG=$(python3 -c "import json; print(json.load(open('plugins/factory/templates/settings.json'))['extraKnownMarketplaces']['$OLD_MKT']['source']['repo'])")

echo "repo:        $OLD_SLUG -> $NEW_SLUG"
echo "marketplace: $OLD_MKT -> $NEW_MKT"

for f in .claude-plugin/marketplace.json \
         plugins/factory/templates/settings.json \
         plugins/factory/templates/claude.yml \
         plugins/factory/templates/claude-code-review.yml \
         README.md; do
  sed -i.bak \
    -e "s|$OLD_SLUG|$NEW_SLUG|g" \
    -e "s|factory@$OLD_MKT|factory@$NEW_MKT|g" \
    -e "s|\"$OLD_MKT\"|\"$NEW_MKT\"|g" \
    -e "s|\`$OLD_MKT\`|\`$NEW_MKT\`|g" \
    "$f"
  rm -f "$f.bak"
done

./scripts/validate.sh
echo "Rebranded. Review the diff, then commit and push."
