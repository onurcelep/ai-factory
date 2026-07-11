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
| **Mitigation holding each risk** | **Who can actually run it: claude-code-action actor checks** — the action only proceeds for a triggering user with **write access** to the repo, and **rejects bots by default** unless allowlisted (see [Mitigations](#mitigations-what-each-one-is)). So an anonymous public commenter's `@claude` never starts a privileged run. **What a run can do to `main`: the require-PR ruleset** (invariant 1). **Irreversible action: human-only merge** (invariant 2). **Self-modification: GitHub's workflow-file push refusal** (invariant 3 below). |

### 2. Review — `templates/claude-code-review.yml` (automatic Opus review)

| Facet | Detail |
|---|---|
| **Trigger surface** | Every `pull_request` event (`opened`/`synchronize`/`ready_for_review`/`reopened`) — see the `on:` block. |
| **Token + effective permissions** | Read-only: the `permissions:` block in `templates/claude-code-review.yml` grants no write scope (only `id-token: write` for auth). This job cannot push or comment-mutate beyond posting its review via `--comment`. Read the block for the exact scopes. |
| **Injection surfaces** | The PR diff and PR/issue metadata it reviews — untrusted, since a machine-authored PR is exactly the case this reviews. |
| **Mitigation holding each risk** | **Bot-authored PRs still get reviewed: the `allowed_bots: 'claude'` allowlist** — the action rejects non-human actors by default, so the responder's own `claude`-authored proposals are explicitly allowlisted so they are *not* skipped. The blast radius is bounded structurally: **the read-only permission block** means even a fully injected review agent has nothing to write. |

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
