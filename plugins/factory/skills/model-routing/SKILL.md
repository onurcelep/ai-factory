---
name: model-routing
description: Model routing policy for token efficiency. Use when spawning subagents, choosing a model for an agent/workflow, or editing model pins in @claude GitHub workflow files.
---

# Model routing (token efficiency)

Route agent work to the cheapest capable model. Always set the model
explicitly: an omitted model silently inherits an expensive default.

- **Haiku**: implementers executing fully-specified plan tasks (the plan
  contains the complete code; the job is transcription plus running tests).
- **Sonnet**: fix subagents, task reviewers, GitHub routines, and the
  interactive @claude Actions responder (`--model claude-sonnet-5
  --max-turns 40`; the propagated factory-update task alone needs ~46
  recorded turns, so lower caps kill legitimate runs). Judgment work needs at least mid-tier: turn count beats
  token price. An under-modeled agent that takes 3x the turns costs more
  than a capable one.
- **Opus**: research sweeps, architecture/design work, and the auto PR-review
  workflow (runs once per PR; review depth matters).
- **Most capable model**: session controller and the final whole-branch
  review only.

Escalate one level when a task is BLOCKED or produces repeated review
findings; never escalate by default.

## Shipped agents carry these pins

Prefer spawning the plugin's shared agents over restating the routing per
task — they encode this policy structurally and update fleet-wide with the
plugin: **factory-implementer** (Haiku, fully-specified tasks, returns
BLOCKED instead of guessing), **factory-reviewer** (Sonnet, scoped
review/fix), **factory-researcher** (Opus, decision-ready research). Live
in `plugins/factory/agents/`.

Workflow pins live in `.github/workflows/claude.yml` (Sonnet, turn-capped)
and `.github/workflows/claude-code-review.yml` (Opus). Keep pins and this
policy in sync when either changes.

## Single source of truth for pinned values

The workflow files are the ONLY place a pinned literal (model name, turn
cap, tool allowlist) may appear. Everywhere else (README, CLAUDE.md,
docs/) point at the pin location instead of restating the value: restated
copies drift silently the moment a pin changes, because nobody updates
prose when they bump a cap. The same rule applies to any config literal a
doc is tempted to quote — link the file that owns it.
