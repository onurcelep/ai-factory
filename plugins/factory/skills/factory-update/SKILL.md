---
name: factory-update
description: Refresh the ai-factory standard parts of an already-initialized repo - the @claude workflows, plugin wiring in .claude/settings.json, and the marker-fenced standard block in CLAUDE.md. Use after the ai-factory templates change. Never touches project-specific content.
---

# factory-update

Refresh only the standard, stamped parts.

## 0. Resolve the template source — remote main by default

`${CLAUDE_PLUGIN_ROOT}/templates/` is a cache fetched at session start and
may be stale (a session opened before a template change keeps the old
version for its whole lifetime). Never stamp from it by default. Instead:

1. Derive the marketplace repo slug from the target repo's
   `.claude/settings.json` → `extraKnownMarketplaces.<name>.source.repo`.
2. Fetch the canonical templates into a temp dir:
   `git clone --depth 1 https://github.com/<slug> <tmpdir>`.
3. Use `<tmpdir>/plugins/factory/templates/` as the template source. Read
   the version from `<tmpdir>/plugins/factory/.claude-plugin/plugin.json`
   and the head sha, and state both in the report and in any commit or PR
   message ("factory-update to <version> @ <sha>").

Arguments: an optional git ref (tag, branch, or commit) pins the fetch —
`git clone --depth 1 --branch <ref>` for tags/branches, or a full clone +
checkout for a sha. The literal argument `local` uses
`${CLAUDE_PLUGIN_ROOT}/templates/` (offline fallback) — the report must
then flag that the source may be stale.

## 0b. Base on the remote default branch, not the local checkout

Run `git fetch origin` in the target repo and apply the update on a new
branch cut from `origin/<default-branch>` — the local checkout may be
behind or mid-work, and stamping from it re-applies changes main already
has (producing a conflicted, redundant PR). If the working tree is dirty
or on a feature branch, do the work in a temporary worktree
(`git worktree add <tmp> -b <branch> origin/<default>`) so nothing in
progress is touched, and remove it afterwards.

## 1. Preflight

CLAUDE.md must contain BOTH markers:
begin: `<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->`
end: `<!-- factory:standard:end -->`
If either is missing, stop and say "not initialized; run /factory-init".

This tool will never modify content outside the marker boundaries.

## 2. Refresh workflows and settings

Templates below refer to the source resolved in step 0.

Same diff-and-confirm copy as factory-init, same targets:
`.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`.
For `.claude/settings.json`, merge (preserve any repo-added keys); only
ensure the template's `extraKnownMarketplaces` entry and its
`enabledPlugins` entries are present and current (the template is the
source of truth for the marketplace and plugin names).

## 3. Ensure the memory index exists

If `docs/memory/MEMORY.md` is missing, create it from
`templates/MEMORY.md.tmpl`. If it exists, leave it completely untouched —
its content and the fact files beside it are repo-owned, like `## Project`.

## 4. Refresh the CLAUDE.md standard block

Extract the text between (and including) the two markers from
`templates/CLAUDE.md.tmpl` (the {{PROJECT_NAME}} placeholder is not inside
the block, so no placeholder resolution is needed) and replace the text
between (and including) the markers in the repo's CLAUDE.md with it. Show
the diff before writing.
NEVER modify anything outside the markers: the `## Project` section and
everything else in the file belong to the repo.

## 5. Report

List changed/current files and the template source stamped from
(version + sha, or "local cache — possibly stale"). If nothing changed,
say so explicitly.
