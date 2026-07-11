---
name: ci-agent-ops
description: Operating and diagnosing the @claude CI pipeline. Use when a @claude run or auto PR review misbehaves (no PR, no review note, instant finish), when verifying CI-agent health, or before changing claude*.yml workflows or the CLAUDE_CODE_OAUTH_TOKEN secret.
---

# CI agent ops

How to read, verify, and debug the @claude GitHub Action pipeline. Written
from a real multi-cause outage; every rule below was paid for.

## Health signals (never trust the check color)

The action can report a green check on a run that did nothing. Judge health
by artifacts and by the result JSON in the run log:

- **Healthy:** `"is_error": false`, double-digit `num_turns`, nonzero
  `total_cost_usd`, and the expected artifact exists (a pushed `claude/`
  branch + "Create PR ➔" link on the issue, or a posted review note).
- **Dead on arrival:** `is_error: true`, `num_turns: 1`, `total_cost_usd: 0`,
  ~2s duration. The tracking comment sticks at "I'll analyze this and get
  back to you", or a review check is green with no review comment. The run
  did no work, whatever the check says.
- **Honest failures** (`error_max_turns`, push 403) report as failures;
  read the last comment for what blocked it.
- **Anti-tamper skip (looks dead, is not):** on any PR that modifies a
  `claude*.yml` workflow file, the action refuses to run — the workflow
  file must be identical to the default branch's version — and produces
  an instant no-artifact run (red where the assertion step exists, green
  and silent where it does not). This is NOT a token failure: do not
  rotate anything. Expected on factory-update PRs that touch workflows;
  the run behaves normally again after merge. Discriminate by reading
  the run log for "Workflow validation failed".

## Diagnosis order for dead-on-arrival runs

The real error is hidden by default. Do these in order; do not ship a fix
before one of them has named the cause:

0. **Retry once first.** Transient API errors produce the exact same
   instant-`is_error`/$0 signature as a dead token (observed live: two
   repos' runs blipped simultaneously and both succeeded on retry, via a
   "@claude please retry" comment). Only a failure that *reproduces* on
   retry warrants the investigation below.
1. **Surface the error:** add `show_full_output: true` to the workflow and
   merge it (the action refuses branch-modified workflows even via
   workflow_dispatch, so this must land on the default branch). Read the
   SDK stream in the next run's log.
2. **Suspect the OAuth token first:** `CLAUDE_CODE_OAUTH_TOKEN` going bad
   produces exactly this signature. Rotate with `claude setup-token`, then
   `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <repo>`.
   **Trap:** you cannot verify a token locally with
   `CLAUDE_CODE_OAUTH_TOKEN=... claude -p ...` — the CLI silently prefers
   keychain credentials and succeeds with any garbage value. Verify only
   in CI (smoke test below).
3. **Discriminate with a cross-repo A/B:** trigger @claude in a sibling
   repo sharing the same secret value. Same failure → token/account.
   Works there → this repo's config. One run answers what hours of log
   archaeology cannot.
4. **Only then consider version regressions.** A correlation across a gap
   with no runs in it ("last good used build A, first bad used build B")
   is not evidence — every variable that changed in that window is equally
   suspect. Do not pin action SHAs on correlation alone.

## Smoke test (the only real verification)

After any change to tokens, workflows, permissions, or the App
installation, run one full loop before declaring health:

1. Open an issue: "@claude this is a CI health check. Reply with a one-line
   comment saying 'pong' and do nothing else." → verifies token + model.
2. For full verification, give it a real one-file micro-task instead →
   verifies push (`claude/` branch appears with a "Create PR ➔" link),
   then open the PR from that link → verifies the auto review posts.
3. Delete or close the smoke issue afterwards.

Known plumbing facts (why the loop is shaped this way):

- Branch pushes and PR creation use the **workflow token**, so the
  workflow needs `contents/pull-requests/issues: write` (the App token
  only covers comment posting; with read-only permissions every implement
  task dies at `git push` 403 while comments still work).
- Even with write permissions, pushes that modify `.github/workflows/`
  files are rejected ("without workflows permission"). Don't retry:
  apply everything else, revert the workflow-file part, and report the
  remaining diff for a human to apply.
- The action never opens the PR itself: it pushes and posts a prefilled
  "Create PR ➔" link. This is by design — a PR created by the workflow's
  own token would not trigger `pull_request` workflows (GitHub
  anti-recursion), silently skipping the auto review. A human (or a local
  session under the owner's token) opens the PR.
- `main` must be guarded by a ruleset (require PR) where the plan allows,
  never by under-granting workflow permissions: a safety property that
  falls out of a misconfiguration disappears when the misconfiguration is
  fixed.
- `--max-turns` must fit implement-and-PR tasks (~15–25 turns; the
  template pins 30 as a circuit breaker).

## Incident hygiene

- Keep diagnosis-in-progress out of permanent public artifacts. PR bodies
  and issue comments get short, final, neutral text; the running theory
  lives in the session or in `docs/memory/` once verified. Never autolink
  an external upstream issue (`owner/repo#N` or URL) from a public PR or
  comment — it creates an un-deletable "mentioned" event on the upstream
  tracker.
- After the incident, record the verified diagnosis in `docs/memory/`
  (per `factory:repo-memory`) in the same PR as the fix, and delete noisy
  retry/error comments from the affected issues.
