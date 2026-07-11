---
name: factory-status
description: Fleet check - list every repo of the current GitHub user that is factory-stamped and report whether each is current or stale against the marketplace's latest version. Use when asking "which of my repos need a factory-update", after templates change, or to verify propagation worked.
---

# factory-status

Answer "which of my repos are factory-stamped, and are they current?" in
one pass. Read-only; changes nothing.

## 1. Resolve the latest version

Fetch the canonical version from the marketplace repo's main branch (do
not trust the session's plugin cache):

Derive the marketplace repo slug the same way `factory-update` step 0
does: from the current repo's `.claude/settings.json` →
`extraKnownMarketplaces.<name>.source.repo`; if there is no settings file
here, take it from the installed plugin's marketplace config. Then:

```bash
LATEST=$(gh api "repos/$SLUG/contents/plugins/factory/.claude-plugin/plugin.json" \
  --jq .content | base64 -d | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
```

## 2. Scan the fleet

Enumerate the user's repos and read each one's stamp (the
`<!-- factory:version X.Y.Z -->` line inside the CLAUDE.md standard
block):

```bash
OWNER=$(gh api user --jq .login)
for r in $(gh repo list "$OWNER" --limit 100 --json name --jq '.[].name'); do
  v=$(gh api "repos/$OWNER/$r/contents/CLAUDE.md" --jq .content 2>/dev/null \
      | base64 -d | grep -o 'factory:version [0-9.]*' | awk '{print $2}')
  [ -n "$v" ] && echo "$r $v"
done
```

Repos with markers but no version line were stamped before v0.5.0 —
report them as "stamped, version unknown (pre-0.5.0): run /factory-update
to add the stamp".

## 3. Compare (version-aware, not string equality)

Do **not** compare `stamped == latest` as strings — a repo stamped from a
newer testing branch would read as stale and get a pointless downgrade.
Compare semantically with `sort -V` (dependency-free); the verdict is:

- stamped **==** latest → **current**
- stamped **>** latest → **ahead** (stamped from a newer/testing build; not stale, no update)
- stamped **<** latest → **STALE — run /factory-update**
- marker but no version line → **stamped-unversioned (pre-0.5.0)**

```bash
# verdict for one repo, given $stamped and $LATEST
if [ "$stamped" = "$LATEST" ]; then verdict=current
elif [ "$(printf '%s\n%s\n' "$stamped" "$LATEST" | sort -V | tail -1)" = "$stamped" ]; then verdict=ahead
else verdict="STALE — run /factory-update"; fi
```

## 4. Report

A table: repo · stamped version · latest version · verdict
(**current** / **ahead** / **STALE — run /factory-update** / stamped-unversioned).
Also report the locally installed plugin version (`claude plugin list` or
the plugin cache's plugin.json) against `LATEST`, with the fix
(`claude plugin update factory@<marketplace>`); local sessions load skills
from that cache, so a stale local plugin means stale skills locally even
when every repo is current.

If the propagation workflow is set up (see `docs/OPERATIONS.md`), stale
repos should already have an open update issue — link any found
(`gh issue list -R <owner>/<repo> --search "factory-update in:title"`)
instead of just saying "run it manually".
