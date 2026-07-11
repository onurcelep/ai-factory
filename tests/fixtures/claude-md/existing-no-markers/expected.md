# CLAUDE.md — sample-project

<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->
<!-- factory:version 0.0.0-test -->
Read by Claude Code locally and by the @claude GitHub Action, so both
inherit the same rules. Standard setup is stamped by ai-factory
(`/factory-update` refreshes this block only; everything under `## Project`
belongs to this repo).

## Standard rules

- **Every change ships via a short-lived branch and a PR; a human merges.
  Nobody pushes `main` directly** (@claude pushes only `claude/` work
  branches and opens PRs). Full discipline: `factory:release-flow` skill.
- **Review before merge:** the auto PR review runs, and `/code-review` for
  anything nontrivial. What a merge to `main` triggers (deploy, a separate
  release train, or nothing) is per-repo, under `## Project`.
- **Model routing: consult the `factory:model-routing` skill** before
  spawning subagents or editing the model pins in
  `.github/workflows/claude*.yml`.
- **Durable learnings live in `docs/memory/`** — read its `MEMORY.md`
  index before nontrivial work; record new non-obvious, reusable project
  facts there in the same PR. Rules: `factory:repo-memory` skill. Never
  personal data or secrets (the repo may be public).
- Scale tooling to the task: prefer the lightest mechanism that works
  (inline edit < subagent < worktree < workflow).
<!-- factory:standard:end -->

## Project

<!-- Everything below is owned by this repo. /factory-update never touches it. -->


Intro paragraph that must survive byte-for-byte.

### Setup

Run the build:

```sh
# this hash is a shell comment, not a heading — it must NOT be demoted
make build
```

#### Environment

- `WIDGET_API` must be set

### House rules

Don't break the trunk.

