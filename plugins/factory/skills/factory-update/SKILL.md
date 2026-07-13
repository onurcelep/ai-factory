---
name: factory-update
description: Refresh the ai-factory standard parts of an already-initialized repo - the @claude workflows, plugin wiring in .claude/settings.json, and the marker-fenced standard block in CLAUDE.md. Use after the ai-factory templates change. Never touches project-specific content.
---

# factory-update

Refresh only the standard, stamped parts.

## 0. Resolve the template source

**In a GitHub Action session (the @claude responder), use
`${CLAUDE_PLUGIN_ROOT}/templates/` directly.** The Action installs the
plugin fresh from the marketplace at every run start, so the cache is
current by construction — and the sandbox blocks network access anyway.
Do not attempt `git clone`, `curl`, or WebFetch there; they fail and waste
turns. Read the version from
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and state it in the
report and commit message ("factory-update to <version>").

**In a local or cloud session**, `${CLAUDE_PLUGIN_ROOT}/templates/` is a
cache fetched at session start and may be stale (a session opened before a
template change keeps the old version for its whole lifetime). Never stamp
from it by default. Instead:

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

**Action-session limitation — read this before touching any
`.github/workflows/**` path.** The @claude App token cannot write there
at all (GitHub rejects the push, and the action's own tool policy
matches that boundary), so treat every file under `.github/workflows/`
as **read-only in this session, full stop**: never call `Edit` or
`Write` on one, and do not "try it and see" — a denied write attempt is
turns spent for nothing, and a run that keeps retrying instead of
backing off can burn its whole turn budget and error out
(`error_max_turns`) without ever reaching the CLAUDE.md version-stamp
update, which is the one change that actually clears a propagation
issue. Instead: `Read` the current file and the template, diff them
yourself (textually, in your head or a scratch comparison — no write
tool involved), and if they differ, put the exact diff in your report
for a human (or a local session, which has no such restriction) to
apply by hand. This applies even if the diff is just a comment or
whitespace change — do not special-case "small" diffs into an attempt.
Do the CLAUDE.md and settings.json work below regardless of whether a
workflow diff exists; they are independent and unblocked.

Templates below refer to the source resolved in step 0.

Same diff-and-confirm copy as factory-init, same targets: **every
workflow row of factory-init's step-2 stamp table** (each
`templates/*.yml` whose target is `.github/workflows/<name>`) — do not
restate the list here; a template workflow added later must ride updates
without this skill changing. A workflow template with no counterpart in
the repo is NEW: stamp it (it is part of the standard, not a repo
extra). Repo-specific additions inside an existing workflow (say, an
extra `--allowedTools` flag or an extra input) are repo-owned — preserve
them when applying the template diff and call them out in the report.
For `.claude/settings.json`, merge (preserve any repo-added keys); only
ensure the template's `extraKnownMarketplaces` entry and its
`enabledPlugins` entries are present and current (the template is the
source of truth for the marketplace and plugin names). Exception: a
`ref`/`sha` pin on a marketplace source is repo-owned (the stability
opt-in in `docs/OPERATIONS.md`) — never remove it; reference semantics:
`scripts/lib/factory_stamp.py merge-settings` (golden-tested).

## 3. Ensure the memory index exists

If `docs/memory/MEMORY.md` is missing, create it from
`templates/MEMORY.md.tmpl`. If it exists, leave it completely untouched —
its content and the fact files beside it are repo-owned, like `## Project`.

## 4. Refresh the CLAUDE.md standard block

The marker-block splice below is encoded as executable truth in `scripts/lib/factory_stamp.py` (`update-splice`) in the ai-factory repo, golden-tested by `scripts/test-stamping.sh` — match its behaviour exactly.

Extract the text between (and including) the two markers from
`templates/CLAUDE.md.tmpl`, replace `{{FACTORY_VERSION}}` in it with the
version resolved in step 0 (the `<!-- factory:version ... -->` line is the
machine-readable stamp that `factory:factory-status` and the propagation
workflow read — never drop it), and replace the text between (and
including) the markers in the repo's CLAUDE.md with the result. Show the
diff before writing. The {{PROJECT_NAME}} placeholder is not inside the
block, so no other resolution is needed.
NEVER modify anything outside the markers: the `## Project` section and
everything else in the file belong to the repo.

## 5. Report

List changed/current files and the template source stamped from
(version + sha, or "local cache — possibly stale"). If nothing changed,
say so explicitly.
