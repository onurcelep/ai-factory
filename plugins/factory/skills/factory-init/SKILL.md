---
name: factory-init
description: Stamp the current repository with the standard AI-dev setup - @claude workflows, .claude/settings.json plugin wiring, marker-fenced CLAUDE.md, AGENTS.md. Use when initializing a new repo or onboarding an existing repo onto the ai-factory standard.
---

# factory-init

Stamp this repository with the ai-factory standard. Templates live in
`${CLAUDE_PLUGIN_ROOT}/templates/`. Follow the steps in order; never
overwrite existing content without showing a diff and getting confirmation.

## 1. Preflight (abort with a clear message if any fails)

- `git rev-parse --is-inside-work-tree` succeeds; otherwise say "not a git
  repo, run git init first" and stop.
- `gh auth status` succeeds (needed for the manual-steps checklist; if it
  fails, continue stamping but flag it).
- Note the repo slug from `gh repo view --json nameWithOwner -q .nameWithOwner`
  (no remote is fine; the App/secret steps just move to the checklist).

## 2. Stamp the fixed files

Copy each template to its target. If the target exists and differs, show a
unified diff and ask the user per file (keep existing / take template).
If identical, report "already current" and skip.

| Template | Target |
|---|---|
| `templates/claude.yml` | `.github/workflows/claude.yml` |
| `templates/claude-code-review.yml` | `.github/workflows/claude-code-review.yml` |
| `templates/settings.json` | `.claude/settings.json` |
| `templates/MEMORY.md.tmpl` | `docs/memory/MEMORY.md` |

For `.claude/settings.json`, if the target exists, MERGE instead of replace:
add the `onur` marketplace to `extraKnownMarketplaces` and the two entries to
`enabledPlugins`, preserving everything else in the file.

For `docs/memory/MEMORY.md`, create only if missing. If it already exists,
leave it completely untouched — after stamping, its content (and every
fact file beside it) is repo-owned, like `## Project`. Conventions:
`factory:repo-memory` skill.

## 3. Stamp AGENTS.md

Render `templates/AGENTS.md.tmpl`: fill `{{PROJECT_NAME}}` with the repo
directory name, and `{{BUILD_COMMAND}}` / `{{TEST_COMMAND}}` by inspecting
the repo (Cargo.toml -> cargo build / cargo test; package.json -> its
scripts; a plain static site -> "none (static site)" / "manual browser
check"). If unsure, ask the user. If AGENTS.md exists and is identical,
report "already current" and skip; otherwise diff-and-confirm.

## 4. Stamp CLAUDE.md (three cases)

Markers, verbatim:
begin: `<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->`
end: `<!-- factory:standard:end -->`

- **No CLAUDE.md:** render `templates/CLAUDE.md.tmpl`. Fill
  `{{PROJECT_NAME}}`; replace `{{PROJECT_CONTENT}}` with a starter skeleton:
  a `## Commands` heading (build/test/lint found in step 3) and a
  `## Hard rules` heading with a `<!-- add project rules here -->` comment.
- **CLAUDE.md exists, no markers:** render the template, then move the ENTIRE
  existing file content under `## Project` (replacing `{{PROJECT_CONTENT}}`).
  Do not delete or rewrite any of it; if the old content duplicates a
  standard rule, point the duplication out to the user and let them decide.
  To keep the heading outline valid (the old content becomes a subsection of
  `## Project`, not a sibling of it): drop the old file's H1 title line (its
  information is already captured in the new file's H1) and demote every
  remaining heading in the moved content by one level (`##` becomes `###`,
  `###` becomes `####`, and so on). Heading text and all body content stay
  byte-identical — only the leading `#` markers and the dropped H1 line
  change.
- **Markers already present:** say "already initialized; run /factory-update
  to refresh" and touch nothing.

## 5. Manual-steps checklist (print at the end)

1. Install the Claude GitHub App on this repo: https://github.com/apps/claude
2. Set the auth secret: `gh secret set CLAUDE_CODE_OAUTH_TOKEN`
   (generate via `claude setup-token` if needed).
3. Review the stamped files, then commit them per this repo's rules (the
   skill does not commit for you).

## 6. Report

List every file written/skipped/merged and the checklist above. Idempotent:
re-running on a stamped repo must produce only "already current" and the
"already initialized" message.
