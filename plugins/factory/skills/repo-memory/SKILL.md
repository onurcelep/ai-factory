---
name: repo-memory
description: Repo-committed agent memory (docs/memory/) shared by local sessions, Claude Code cloud, and the @claude GitHub Action. Use when reading or recording durable project learnings, promoting local auto-memory into the repo, or deciding where a learned fact belongs.
---

# Repo memory (docs/memory/)

Remote agents (@claude Action runs, cloud sessions, routines) never see
`~/.claude`, so machine-local auto-memory cannot reach them. The repo is
the only substrate every environment shares. Durable project learnings
therefore live in the repo, under `docs/memory/`.

## Layout

```
docs/memory/MEMORY.md    # index: one line per fact — the only always-read file
docs/memory/<fact>.md    # one fact per file, kebab-case name
```

## Read path

Before nontrivial work, read `docs/memory/MEMORY.md` (it is deliberately
tiny). Open only the fact files whose index line matches the task at
hand. Never bulk-load the whole directory.

## Write path

When a task teaches you something that is (a) non-obvious, (b) reusable,
and (c) not derivable from the code or git history, record it **in the
same PR/commit as the work**:

1. Add or update ONE fact file. Update beats duplicate — scan the index
   first. Delete entries you have proven wrong.
2. Add or adjust its one-line entry in `MEMORY.md`.

Fact file format:

```markdown
# <short title>

Learned: YYYY-MM-DD (re-verify before acting if the area has changed)

<The distilled fact. Why it matters. How to apply it.>
```

Distill — a rule, not a transcript. If it takes more than ~15 lines it is
probably two facts, or not yet understood.

## What belongs here (and what does not)

- YES: environment quirks, hard-won gotchas, decisions with their
  rationale, cross-component contracts, "X looks right but breaks Y".
- NO: anything derivable from the code, git history, or CLAUDE.md; task
  state (that is the plan file / issues); personal or user-level
  preferences (those stay in machine-local auto-memory); secrets or
  personal data — NEVER, the repo may be public.

## Gardening

Memory changes ship inside normal PRs, so review is the quality gate:
treat a memory diff with the same scrutiny as code. Entries carry their
date; stale entries are deleted or re-verified, not accumulated. If the
index outgrows ~40 lines, consolidate related facts before adding more.

## Promotion (local <-> repo)

If machine-local auto-memory holds a project-type fact about this repo,
it belongs here: move it into `docs/memory/` in your next PR and keep at
most a pointer locally. The reverse also holds: never record repo facts
only in local memory — the other environments (and other machines) will
not see them.

## Relation to CLAUDE.md

CLAUDE.md `## Project` holds the always-loaded rules every session must
see. `docs/memory/` holds the long tail, read on demand. When a memory
entry graduates to "every session must know this", promote it into
`## Project` and delete the fact file — one home per fact.
