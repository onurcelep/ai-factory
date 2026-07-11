---
name: factory-init
description: Stamp the current repository with the standard AI-dev setup - @claude workflows, .claude/settings.json plugin wiring, marker-fenced CLAUDE.md, AGENTS.md. Use when initializing a new repo or onboarding an existing repo onto the ai-factory standard.
---

# factory-init

Stamp this repository with the ai-factory standard. Templates live in
`${CLAUDE_PLUGIN_ROOT}/templates/`. Follow the steps in order; never
overwrite existing content without showing a diff and getting confirmation.

## 1. Preflight — check the prerequisites

Run every check below, then show the results as a pass/fail list that
includes the fix command for each failure (users skip READMEs; this
report is where they find out what is missing). Only the first check
aborts; everything else continues with a flag.

| Check | How | On failure |
|---|---|---|
| Git repo | `git rev-parse --is-inside-work-tree` | ABORT: "not a git repo, run git init first" |
| `gh` CLI installed and authenticated | `gh auth status` | flag: install the gh CLI, then `gh auth login`; the secret and App checks below move to the checklist |
| Repo hosted on GitHub | `gh repo view --json nameWithOwner -q .nameWithOwner` | flag: the stamped workflows only run once the repo is pushed to GitHub; App/secret steps stay on the checklist |
| Auth secret set | `gh secret list` contains `CLAUDE_CODE_OAUTH_TOKEN` | flag: generate with `claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN` |
| Claude GitHub App installed | best effort: `gh api /user/installations` lists an entry with `"app_slug": "claude"` covering this repo. gh's standard OAuth token gets HTTP 403 from this endpoint — in that case report "could not verify; check https://github.com/settings/installations yourself" | flag: install https://github.com/apps/claude on the repo or org |

A repo that is not on GitHub yet still gets stamped — the flagged items
simply stay on the manual checklist at the end.

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
| `templates/ci-claude-silent-failures.md` | `docs/memory/ci-claude-silent-failures.md` |

For `.claude/settings.json`, if the target exists, MERGE instead of replace:
add the template's `extraKnownMarketplaces` entry and its `enabledPlugins`
entries (the template is the source of truth for the marketplace and plugin
names), preserving everything else in the file.

For `docs/memory/MEMORY.md` and the seeded fact file, create only if
missing. If either already exists, leave it completely untouched — after
stamping, its content (and every fact file beside it) is repo-owned, like
`## Project`. Conventions: `factory:repo-memory` skill.

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

## 5. Protect main (where the plan allows)

The stamped workflows give @claude write permissions, so "nobody pushes
`main` directly" must be enforced, not assumed. On public repos (or any
plan with rulesets), create/update a `protect_main` ruleset on the default
branch with rules `deletion`, `non_fast_forward`, and `pull_request`
(`required_approving_review_count: 0` so solo merges stay unblocked), with
an always-bypass for the repo admin role. On private repos without
rulesets, note in the checklist that the guarantee is convention-only.

## 6. Manual-steps checklist (print at the end)

Include only the items the preflight flagged, plus the review and smoke
steps:

1. Install the Claude GitHub App on this repo: https://github.com/apps/claude
2. Set the auth secret: `gh secret set CLAUDE_CODE_OAUTH_TOKEN`
   (generate via `claude setup-token` if needed).
3. Review the stamped files, then commit them per this repo's rules (the
   skill does not commit for you).
4. **Smoke-test the full loop before relying on it** (see
   `factory:ci-agent-ops`): file a trivial one-file task tagging @claude,
   confirm it pushes a `claude/` branch and posts a "Create PR ➔" link,
   open the PR from the link, confirm the auto review posts, then merge or
   close. A pipeline that has never completed one loop is not set up.

## 7. Report

List every file written/skipped/merged and the checklist above. Idempotent:
re-running on a stamped repo must produce only "already current" and the
"already initialized" message.
