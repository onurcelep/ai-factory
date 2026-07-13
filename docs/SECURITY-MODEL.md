# Security model: trust boundaries for the write-capable agents

Two of ai-factory's four workflows run an agent with `contents: write` and
push rights, and one of those additionally combines `WebSearch`/`WebFetch`
(a prompt-injection vector) with those rights. This is safe today — but
only because a specific set of mitigations each hold a specific risk. None
of those assumptions were written down where they live, so a fork that
weakened one (dropped the `main` ruleset, allowlisted more bots, widened
`--allowedTools`) had no way to know what it was holding up.

This page is that record: per workflow, **who can trigger it, what token
and permissions it runs with, what the injection surfaces are, and the
named mitigation holding each risk.**

**Single source of truth.** Following the repo convention (see the
`factory:model-routing` skill and `scripts/validate.sh`), this doc never
restates pinned literals — permission scopes, model ids, tool lists all
live at their pin and drift if copied. Each row points at the pin; read
the value there.

## The two invariants everything rests on

1. **No agent can touch `main` directly.** Branch pushes land on
   `claude/*` / audit branches; a require-PR ruleset on `main` (stamped by
   `/factory-init` step 5, documented in the `factory:release-flow` skill
   and the README decisions table) forces every change through a pull
   request. The write permission on the workflow token is what lets the
   agent *push a branch*; the **ruleset**, not an under-granted token, is
   what protects `main`. A safety property that only exists because a token
   is mis-scoped evaporates the moment the mis-scoping is fixed — so it is
   deliberately not relied upon.
2. **A human merges every PR.** The action never opens or merges the PR: it
   pushes a branch and posts a prefilled "Create PR ➔" link (a PR opened by
   the workflow's own token would not trigger `pull_request` workflows —
   GitHub anti-recursion — silently skipping the auto review). Merge is the
   one irreversible step, and it is always a human's.

## Per-workflow trust boundaries

### 1. Responder — `templates/claude.yml` (interactive `@claude`)

| Facet | Detail |
|---|---|
| **Trigger surface** | Issue/comment/review text containing `@claude` (see the `on:` + `if:` block). On a **public** repo, anyone can *open* an issue — so the text is attacker-controllable. |
| **Token + effective permissions** | Runs the workflow's `GITHUB_TOKEN`; scopes pinned in the `permissions:` block of `templates/claude.yml` (includes `contents: write`). Model authenticates with the `CLAUDE_CODE_OAUTH_TOKEN` secret. Do not restate the scopes here — read the block. |
| **Injection surfaces** | The triggering issue/comment/PR body (untrusted on public repos); repository file contents the agent reads. |
| **Mitigation holding each risk** | **Who can actually run it: claude-code-action actor checks** — the action only proceeds for a triggering user with **write access** to the repo, and **rejects bots by default** unless allowlisted (see [Mitigations](#mitigations-what-each-one-is)). So an anonymous public commenter's `@claude` never starts a privileged run. **Who can spend *your* token: the `CLAUDE_TRUSTED_ACTORS` gate** (below) — write access and token-spend are different trust decisions; this workflow's `if:` additionally requires the actor be the repo owner or on that allowlist. **What a run can do to `main`: the require-PR ruleset** (invariant 1). **Irreversible action: human-only merge** (invariant 2). **Self-modification: GitHub's workflow-file push refusal** (invariant 3 below). |

### 2. Review — `templates/claude-code-review.yml` (automatic Opus review)

| Facet | Detail |
|---|---|
| **Trigger surface** | Every `pull_request` event (`opened`/`synchronize`/`ready_for_review`/`reopened`) — see the `on:` block. Unlike the responder, there is no `@claude` text gate at all upstream of the actor check below: any PR fires it. |
| **Token + effective permissions** | Near-read-only: the `permissions:` block in `templates/claude-code-review.yml` grants no `contents` write — this job cannot push. `pull-requests: write` exists solely for the assertion step's self-report comment (PR comments require this scope, not `issues: write` — verified via a live 403); it adds no capability class the job lacks (the app token already posts the review comment). Read the block for the exact scopes. |
| **Injection surfaces** | The PR diff and PR/issue metadata it reviews — untrusted, since a machine-authored PR is exactly the case this reviews. |
| **Mitigation holding each risk** | **Who can spend *your* token: the job-level `CLAUDE_TRUSTED_ACTORS` gate** (below) — since this workflow has no actor check upstream (it isn't the `claude-code-action` responder gate, it's a plain `pull_request` trigger), the `if:` on the job itself requires the PR author be the repo owner, on the allowlist, or `claude[bot]`. **Bot-authored PRs still get reviewed: the `allowed_bots: 'claude'` action input** — the action separately rejects non-human actors by default, so the responder's own `claude`-authored proposals are explicitly allowlisted so they are *not* skipped by the action itself (the job-level gate above allowlists the same login so the two don't fight). The blast radius is bounded structurally: **no contents write** means even a fully injected review agent cannot push; the only write surface is comment posting, which the app token already had. |

### 3. Propagate — `.github/workflows/factory-propagate.yml` (fleet fan-out)

| Facet | Detail |
|---|---|
| **Trigger surface** | `push` to `main` touching `plugins/factory/templates/**` or the plugin manifest, plus manual `workflow_dispatch`. Only someone who can land a commit on `main` (i.e. through a merged PR) can trigger it — not arbitrary issue text. |
| **Token + effective permissions** | Runs plain shell (`gh`), **no claude-code-action, no model**. Workflow `permissions:` are read-only (see its `permissions:` block); the cross-repo writes use the separate `FACTORY_PROPAGATE_TOKEN` secret — a fine-grained PAT scoped to **Contents: read + Issues: write** on the owner's repos (see the header comment + `docs/OPERATIONS.md`). The default `GITHUB_TOKEN` is deliberately *not* usable cross-repo (scoped to this repo only). |
| **Injection surfaces** | None from model reasoning — there is no model. The only external input is other repos' `CLAUDE.md` content, which is `grep`-matched for a stamp, never executed. |
| **Mitigation holding each risk** | **Scope containment: the PAT is Issues-write only** — the worst a compromised propagate run can do fleet-wide is file issues (which then flow through the responder's own actor checks + ruleset + human merge). Absent the secret the job **skips with a notice** (safe default for forks). |

### 4. Frontier audit — `.github/workflows/frontier-audit.yml` (weekly self-audit)

| Facet | Detail |
|---|---|
| **Trigger surface** | Scheduled (cron) + manual `workflow_dispatch`. **Not** triggerable by issue/comment text — only the repo's own schedule or a maintainer dispatch. |
| **Token + effective permissions** | Workflow `GITHUB_TOKEN` with the scopes in its `permissions:` block (includes `contents: write` to push the audit branch); model via `CLAUDE_CODE_OAUTH_TOKEN`. Read the block for the scopes. |
| **Injection surfaces** | **The highest-risk combination in the fleet: `WebSearch` + `WebFetch` (fetching arbitrary external pages — a classic prompt-injection channel) together with push rights.** It also reads the full repo history (`fetch-depth: 0`). |
| **Mitigation holding each risk** | **Bounded capability: the scoped `--allowedTools` pin** in the `claude_args` block — `Bash` is restricted to `git`, `gh`, the repo's own validator, and harmless utilities (no arbitrary shell), so a page that tries to inject "run this command" has no general `Bash` to reach. **`main` is still protected by the ruleset** and **merge is still human-only** (invariants 1 & 2), so even a fully injected audit run can at most push a branch that a human then declines to merge. **No untrusted-text trigger:** unlike the responder, nothing an outside party writes can *start* this run. |

## The `CLAUDE_TRUSTED_ACTORS` gate: write access ≠ token spend

GitHub write access and "may run agents on the repo owner's
`CLAUDE_CODE_OAUTH_TOKEN`" are two different trust decisions. A solo
maintainer never notices the gap — they're the only write-access actor
there is — but the moment a repo gains an outside collaborator with write
access, `claude-code-action`'s own actor check (write-access required) is
no longer narrow enough: that collaborator's `@claude` comment, or their
plain PR against the review workflow, would run against *your*
subscription token, not theirs.

Both `templates/claude.yml` and `templates/claude-code-review.yml` add a
job-level `if:` on top of the action's own check:

```
github.actor == github.event.repository.owner.login ||
contains(format(',{0},', vars.CLAUDE_TRUSTED_ACTORS), format(',{0},', github.actor))
```

(the review workflow checks `github.event.pull_request.user.login`
instead of `github.actor`, since the actor triggering a `pull_request`
event is GitHub itself, not the PR's author — and separately allowlists
`claude[bot]` so machine-authored PRs are not the case that widening
`CLAUDE_TRUSTED_ACTORS` is meant to guard against).

- **The repo owner is always trusted, with zero config** — `github.event.repository.owner.login`
  is read from the event, never hardcoded, so this holds unchanged across
  forks and rebranding.
- **Extending trust to a contributor is an explicit, auditable step**, not
  a side effect of granting them write access:
  ```bash
  gh variable set CLAUDE_TRUSTED_ACTORS --body "alice,bob"
  ```
  Unset (the default), no one but the owner can trigger a token-spending
  run — a contributor can still push branches and open PRs, the PR just
  doesn't get an automatic review, and their `@claude` mentions are
  silently ignored (no model call, no cost — the gate is evaluated in the
  `if:` before the action even starts).
- **Comma-delimited membership, not substring match** — the
  `format(',{0},', …)` wrapping means `bob` in the list never
  accidentally matches actor `bobby`.

## Role contracts: instructions × permissions

Instructions and permissions are delivered by two different systems.
Instructions broadcast widely — the repo `CLAUDE.md` and the plugin's
skills load into *every* agent that works here. Permissions are
role-specific — each workflow's `permissions:` block and `--allowedTools`
pin (the tables above). A mismatch between the two is invisible until it
becomes an incident: the agent obeys an instruction its allowlist cannot
honor, gets denied, and burns turns flailing or fails its actual job.

This is not hypothetical. On 2026-07-12 the PR reviewer obeyed a
root-CLAUDE.md gate written for change-making agents ("run the validation
suite before pushing"), was permission-denied 56 times, and posted **no
review at all under a green check** — caught only by the artifact
assertion added the same day (see the review workflow's assert step and
issue #42).

The contract rules, in force:

1. **Instructions that command actions must name the roles they bind.**
   The root `CLAUDE.md` scopes its gates to change-making agents and
   tells read-only roles to assess instead of attempt. Any future
   instruction file that names a gate follows the same pattern
   (enforced by `validate.sh`).
2. **A role's allowlist is part of its trust boundary, not a
   convenience setting.** Widening one to satisfy an instruction is a
   security decision — argue it against the tables above, not against a
   denial count. (The reviewer currently runs on the action's default
   tool policy; an explicit pin is deliberately deferred until issue #42
   yields evidence of what a review legitimately needs.)
3. **Denials are the mismatch signal.** The review workflow warns when
   the denial count exceeds 20 and preserves the execution trace as a
   run artifact on failure or high denials, so "what did the agent try
   vs. what was it allowed" is a download, not archaeology.
4. **The contract is tested from the agent's side too:** a cross-role
   behavioral eval (`evals/cases/release-flow.json`, `role: readonly`)
   runs an agent with an assess-only allowlist against a change-shaped
   task and requires it to report its limitation instead of flailing.

## Invariant 3: GitHub refuses workflow-file self-modification

Independent of the tokens above, GitHub rejects any push that modifies
`.github/workflows/**` unless the pushing token carries the `workflow`
scope — which neither the workflow `GITHUB_TOKEN` nor the Claude App token
has. So no agent in the fleet can rewrite its own triggers or permissions;
workflow changes are always applied by a human under an account that has
the scope. (This is also why propagated template updates deliver
everything *except* workflow-file changes — see `docs/OPERATIONS.md`.)

## Mitigations: what each one is

- **claude-code-action actor checks** — the anthropics/claude-code-action's
  own gate. Per the official security doc
  (<https://github.com/anthropics/claude-code-action/blob/main/docs/security.md>,
  "Access Control"): *"The action can only be triggered by users with write
  access to the repository"*, and *"By default, GitHub Apps and bots cannot
  trigger this action for security reasons. Use the `allowed_bots`
  parameter to enable specific bots or all bots."* The same doc flags the
  two bypasses to **never** widen casually: `allowed_bots: '*'` (any App can
  invoke with a prompt it controls, especially on public repos) and
  `allowed_non_write_users` (*"a significant security risk … bypasses the
  primary security mechanism"*). The review workflow's `allowed_bots:
  'claude'` is the *narrow* form — one named, trusted bot.
- **Require-PR ruleset on `main`** — stamped by `/factory-init`;
  see the `factory:release-flow` skill and the README decisions table.
- **Human-only merge** — structural (invariant 2); the action posts a
  "Create PR ➔" link and never merges.
- **GitHub workflow-file push refusal** — platform behavior (invariant 3);
  see also the `factory:ci-agent-ops` skill.
- **Scoped `--allowedTools`** — the frontier-audit `claude_args` pin bounds
  the audit agent's `Bash` surface.
- **`CLAUDE_TRUSTED_ACTORS` gate** — the job-level `if:` on the responder
  and review workflows (see above) that narrows "may trigger a run" to
  the repo owner plus an explicit allowlist, independent of GitHub write
  access.

## If you fork and weaken a mitigation

Each of these *silently* removes a load-bearing property. If you must, know
what you are giving up:

| If you change… | You lose… |
|---|---|
| Drop the `main` require-PR ruleset | Invariant 1 — agents can now push to `main` (their tokens already carry write). |
| Widen `allowed_bots` to `'*'` or set `allowed_non_write_users` | The actor check — untrusted parties can drive a write-capable run. |
| Widen frontier-audit `--allowedTools` (e.g. bare `Bash`) | The bound on the highest-injection-risk job — a fetched page can now propose arbitrary commands. |
| Give the workflow/App token `workflow` scope | Invariant 3 — agents can rewrite their own triggers and permissions. |
| Merge PRs by bot/automation instead of a human | Invariant 2 — the one human checkpoint on irreversible change. |
| Set `CLAUDE_TRUSTED_ACTORS` to `*`, or drop the job-level `if:` gate | Every write-access collaborator can spend the repo owner's `CLAUDE_CODE_OAUTH_TOKEN` — the gap this mitigation exists to close. |
