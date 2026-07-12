# Working with a stamped repo

The *use it well* half of the documentation pair. Its sibling,
[OPERATIONS.md](OPERATIONS.md), is the *keep it healthy* half — stamping,
propagation, versioning, rollback. This page is about the day after all
that works: you have a stamped repo, three agent surfaces, and a task in
front of you. What do you actually do?

## Pick the right surface

Every stamped repo gives you three ways to run an agent, and they follow
the same committed rules (`CLAUDE.md`) and read the same committed memory
(`docs/memory/`). The choice is about *your* attention, not the agent's
ability:

| The task in front of you | Use | Why |
|---|---|---|
| Well-specified and delegable — you could write the acceptance criteria in a couple of sentences | **GitHub issue, tag `@claude`** | You get a reviewed PR without holding a session open; the turn-capped responder is built for scoped tasks |
| Exploratory, interactive, or fuzzy — design work, debugging, anything where the next step depends on the last answer | **Local Claude Code session** | You are the feedback loop; this is also where your process layer (brainstorming, planning, TDD skills) does its best work |
| Long-running and hands-off — a refactor or migration you want to review in the morning, not watch | **Cloud session** | Fire and forget; same rules and memory load there too |
| Reviewing a PR | **Nothing — it's automatic** | Every PR gets a once-per-PR review from the strongest model; add a local `/code-review` pass yourself for anything gnarly |

Two failure modes to avoid: driving a vague, twenty-questions design
conversation through GitHub issues (each round trip is a full CI run —
that conversation belongs in a local session), and babysitting a
well-specified task interactively (that attention belongs to the work
only you can do).

## The habits that compound

Each of these exists because skipping it once cost real time. The
enforcement lives in the skills and workflows the stamp installed; your
job is mostly to not work around them.

**1. Pin down *what* you want before any agent builds it.** The most
expensive failure mode in agent work isn't bad code — it's good code for
the wrong requirement, discovered after the PR. When the idea is fuzzy,
make the agent interrogate you first (the shipped process layer's
brainstorming skill, or whatever requirements-grilling skill you prefer)
and only then let it plan. If you keep changing your mind mid-build,
that's the tell that this step was skipped.

**2. Judge runs by artifacts, never by check colors.** A green check
means the workflow exited zero, nothing more. The honest signals are:
did the branch/PR/review *actually appear*, and what do the run's turn
count and cost say? A one-turn, zero-dollar run did nothing, whatever
the dashboard claims. The stamped workflows self-report the known silent
failures, and the `ci-agent-ops` skill carries the diagnosis playbook —
but the habit of asking "where's the artifact?" is yours.

**3. Bank what you learn.** When a session uncovers something durable —
"the staging deploy needs a manual cache flush", "this API lies about
timeouts" — have the agent record it in `docs/memory/` (the
`repo-memory` skill knows the format and updates the index). This is the
difference between a setup that compounds and one that re-learns the
same facts every session, on every machine, for every agent type.

**4. Spend model capability where judgment lives.** The plugin ships
three routed subagents — a cheap implementer for fully-specified tasks,
a mid-tier reviewer/fixer, an expensive researcher — and the
`model-routing` skill carries the policy. The habit: don't under-model
judgment work to save tokens (a wrong design costs more than any model
tier), and don't burn the expensive model on transcription.

**5. Let the release discipline hold, especially when it's inconvenient.**
Branch, PR, human merges — always. Agents never merge into `main`, not
even by local `git merge` when there's no remote to push to; the
`release-flow` skill spells this out and a hook blocks direct pushes.
This rule earned its precision the hard way: an eval caught an agent
completing "get it into main" via local merge *while the rule was in its
context*, because an earlier wording only forbade pushes.

**6. On day one, run one full loop.** File a trivial issue, tag
`@claude`, watch it become a branch, a PR, and a review — before you
trust the pipeline with real work. A capability that has never been
exercised end to end is a hypothesis, not a capability. (The stamp also
installs a scheduled smoke test that keeps verifying this weekly.)

## When something feels off

- An `@claude` run "succeeded" but produced nothing → `ci-agent-ops`
  skill, or the seeded `docs/memory/ci-claude-silent-failures.md` in
  your repo.
- A skill seems to have stopped triggering or being followed →
  [evals/README.md](../evals/README.md); run the tier-2 check, then a
  targeted behavioral eval.
- The repo's standard block looks stale → `/factory-status`, then
  [OPERATIONS.md](OPERATIONS.md).
- You changed the model your agents run on →
  [OPERATIONS.md § Model transitions](OPERATIONS.md#model-transitions).
