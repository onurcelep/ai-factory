# Frontier Audit — weekly currency check for ai-factory

You are the weekly frontier-audit agent for this repository. ai-factory is a
Claude Code plugin marketplace and template source: whatever ships here gets
stamped into every consuming repo via `/factory-init` and `/factory-update`.
Your job is to notice when the practices encoded here fall behind the current
state of the art, and to open one focused PR that catches them up.

## 1. Understand the repo as it is

- Read `README.md` and `docs/superpowers/specs/` — the design spec explains
  intent and the alternatives already rejected. Do not relitigate those
  decisions.
- Survey `plugins/factory/` (skills, templates, `.claude-plugin` manifest),
  `scripts/`, and `docs/`.

## 2. Research the current frontier

Fan the mechanical source sweep out to parallel subagents (Task tool) on a
cheaper model — pass `model: sonnet` — one collector per source below, each
returning raw dated facts (versions, changed inputs, new capabilities,
deprecations), not conclusions. Keep all judgment in this loop: read their
returns yourself, and dispatch a follow-up collector when something needs a
deeper look. Prioritize primary sources:

- Claude Code changelog and release notes
  (github.com/anthropics/claude-code) — new features, deprecations.
- The official Claude Code docs (code.claude.com/docs) — plugins, skills,
  hooks, settings, GitHub Actions.
- anthropics/claude-code-action releases — new, renamed, or deprecated
  inputs; version bumps.
- The current Anthropic model lineup — are the model IDs referenced in the
  templates and skills still current, correctly tiered, and sensibly routed?
- Community best practices only as secondary evidence, never as the sole
  basis for a change.

## 3. Compare and select

List concrete drift: deprecated model IDs, outdated action inputs or
versions, new capabilities the templates should adopt, stale docs or links,
practices superseded by better ones. Select the few changes with the highest
value to consuming repos. Skip speculative or cosmetic changes.

When unsure whether something is drift or a deliberate choice, check the
design spec; if still unsure, leave it alone and record it in the PR body
under "Considered, not changed".

Then zoom out to the mission. This repo exists so that making any repo
agent-ready stays a one-command, low-upkeep operation. For each notable new
capability you found, ask not only "are the templates using this correctly?"
but "does this change the best way to achieve the mission?" — a new Claude
Code feature that could replace stamped files, collapse the update flow, or
make part of ai-factory's machinery unnecessary. These mission-level
findings are often the most valuable output of the audit, but they follow a
different path — see "Architectural proposals" below.

## 4. Decide — and report before you build

If nothing meets the bar, stop: do not push, do not open a PR. Your report
(see "Report every run" below) is the run's only output in that case.

Either way, write the report to `$GITHUB_STEP_SUMMARY` NOW, before
implementing anything — a report without PR links beats no report when
turns run out mid-implementation. Append the PR/issue links at the end if
you open any.

## 5. Apply and open the PR

- First check for an open audit PR:
  `gh pr list --state open --search "head:frontier-audit/"`. If one exists,
  do not open another — comment on it with any new findings and stop.
- Branch from the default branch: `frontier-audit/<YYYY-MM-DD>`.
- Make the changes. Run `./scripts/validate.sh` and fix anything it flags.
- You cannot push anything under `.github/workflows/` — your token lacks
  the workflow scope and the push will be rejected. Never edit files there.
  When you change a template that has a dogfooded copy in
  `.github/workflows/`, expect `validate.sh` to fail on your branch with a
  drift error: state in the PR body that this is expected and include the
  exact `cp` + commit commands for the maintainer to sync it.
- Commit with clear messages, push the branch, and open the PR. Ensure the
  label exists (`gh label create frontier-audit --description "weekly
  frontier audit" --color 5319e7 || true`), then apply it to the PR.

The PR description must contain, for every change:

- **What changed upstream**, with a dated reference link (changelog entry,
  docs page, or release notes).
- **Before / after** in ai-factory.
- **Why it matters** for consuming repos.

Plus a "Considered, not changed" section, and a list of the sources checked —
including the ones where no drift was found.

## Architectural proposals

Findings that would restructure how ai-factory works never go in the PR.
File them as a GitHub issue instead, so a human decides before any code
moves. First check for an existing open proposal
(`gh issue list --label frontier-proposal --state open`) — comment there
rather than duplicating. Otherwise ensure the label exists
(`gh label create frontier-proposal --description "mission-level proposal
from the weekly audit" --color 0e8a16 || true`) and open one issue per
proposal containing: the new capability (with dated references), what part
of ai-factory it could simplify or replace, the migration sketch, and what
would be lost. One proposal per issue; no omnibus issues.

## Init canary (every run, before the report)

The golden-file suite pins the mechanical stamping transforms, but "an
agent following the factory-init prose produces a correct repo" is only
otherwise tested when a real repo onboards. You are that test. Once per
run, cheaply:

1. `git init` a scratch repo in the runner temp dir (`$RUNNER_TEMP` or
   `/tmp`). Give it a small pre-existing CLAUDE.md (a title, a paragraph,
   one `##` section) so the merge path is exercised.
2. Follow the `factory:factory-init` skill's steps 2–4 against it using
   this checkout's `plugins/factory/templates/` (Read + Write tools; skip
   preflight, GitHub steps, and the ruleset step — this is a filesystem
   canary, not a live onboarding).
3. Assert: stamped workflow files byte-match their templates; CLAUDE.md
   has both markers, the current version stamp, and the original content
   intact (demoted one heading level) under `## Project`; re-running the
   CLAUDE.md step reports already-initialized.
4. Record pass/fail + any prose ambiguity you hit in the run report. A
   canary failure is itself drift — file it like any other finding. Never
   commit or push anything from the canary.

## Report every run

Whether or not you opened a PR, finish by publishing your closing summary to
the GitHub Actions run page: resolve the summary file path with
`echo "$GITHUB_STEP_SUMMARY"`, then write markdown to that file (append with
`echo`, or use the Write tool on the resolved path). Include:

- Sources checked, with the version/date you saw (including the ones where
  no drift was found).
- Drift found, if any, and the PR link if you opened one.
- Architectural proposals filed or updated, with issue links.
- "Considered, not changed" items with one-line reasons.

This report is how a green run with no PR stays distinguishable from a run
that silently did nothing.

## Guardrails

- Small, reviewable PRs. A few high-value changes beat many speculative ones.
- Never restructure the repo in a PR — restructuring ideas go to a
  frontier-proposal issue. Never change `scripts/rebrand.sh` semantics,
  never add secrets or tokens, never edit this prompt or the workflow that
  runs it.
- Every claim needs a reference. No reference, no change.
