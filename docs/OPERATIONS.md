# Operating ai-factory

The one page that answers "what do I run, and when". Written for someone
who has never seen this system. This is the *keep it healthy* half of the
documentation pair; the *use it well* half — daily work inside a stamped
repo — is [WORKING.md](WORKING.md).

## The mental model: four channels

Everything ai-factory ships travels on exactly one of four channels. When
something changes, ask "which channel does it ride?" — that determines
what, if anything, you do.

| What changed in ai-factory | Channel | Reaches CI agents | Reaches local sessions | You do |
|---|---|---|---|---|
| **Plugin content** — skills, agents, hooks (`plugins/factory/{skills,agents,hooks}/`) | Plugin marketplace | Automatically, next @claude run (workflows fetch the plugin fresh every run) | After `claude plugin update factory@<marketplace>` (or the periodic cache refresh) | Nothing per repo; update the local plugin per machine |
| A **template** (`plugins/factory/templates/`) | `/factory-update`, per repo | After the update PR merges | Same | Merge the auto-filed update PR (or run `/factory-update` manually) |
| A **seeded memory** (`templates/*.md` fact files) | `/factory-init`, new repos only | On repos initialized after the change | Same | Nothing — existing repos own their memory files |
| Repo content (`## Project`, `docs/memory/`, code) | None — repo-owned | — | — | Factory never touches it |

The skills row is the one with no version gate: an edit on `main` reaches
the whole fleet at each environment's next turnover, with no release step.
That is deliberate (freshness over ceremony), but it needs a rollback
story and a stability escape hatch — see
[Rolling back a bad skill](#rolling-back-a-bad-skill-and-pinning-against-one).

## Lifecycle

### Onboard a brand-new repo

```
/factory-init          # stamps workflows, settings, CLAUDE.md, memory index
```

Then follow its checklist: install the Claude GitHub App, set
`CLAUDE_CODE_OAUTH_TOKEN`, commit via PR, and **run the smoke test it
prints** — a pipeline that has never completed one loop (issue → @claude →
branch → PR → review) is not set up. The init also protects `main` with a
require-PR ruleset where the plan allows.

Only the repo owner can trigger a run by default — adding a collaborator
with write access does **not** let them spend your `CLAUDE_CODE_OAUTH_TOKEN`
until you explicitly extend `CLAUDE_TRUSTED_ACTORS` (see
[SECURITY-MODEL.md § The `CLAUDE_TRUSTED_ACTORS` gate](SECURITY-MODEL.md#the-claude_trusted_actors-gate-write-access--token-spend)).

### Onboard an existing repo (created before ai-factory)

Same command. `/factory-init` is designed for this case:

- An existing `CLAUDE.md` is preserved whole — it moves under `## Project`
  (headings demoted one level), and the standard block is added around it.
  Nothing is deleted or rewritten.
- An existing `.claude/settings.json` is merged, not replaced.
- Existing workflows with the same names get a diff-and-confirm, never a
  silent overwrite.
- `docs/memory/` content is never touched if present.

After onboarding, the repo is maintained exactly like a new one.

### Maintain a stamped repo

**Target: nothing.** With the propagation workflow enabled (below), a
template change on ai-factory's main automatically files an update issue
in every stale repo; @claude runs the update and pushes a branch; you
click its "Create PR" link and merge. Your only recurring job is the
merge button.

Manual fallbacks, any time:

- `/factory-status` — fleet check: every stamped repo, its stamped
  version vs latest, plus your local plugin version.
- `/factory-update` — refresh one repo by hand (also accepts a git ref to
  pin, or `local` for offline).

## Enable automatic propagation (one-time, ~2 minutes)

1. Create a fine-grained PAT for your account with **Contents: read** and
   **Issues: write** on your repositories.
2. `gh secret set FACTORY_PROPAGATE_TOKEN -R <owner>/<this-repo>`

Done. On every merge to main that touches `plugins/factory/templates/**`
(or the plugin version), `.github/workflows/factory-propagate.yml` scans
your repos for the factory stamp, compares versions, and files one
`factory-update to <version>` issue per stale repo (idempotent: it skips
repos that are current or already have the issue open). Without the
secret, the workflow skips with a notice — propagation is opt-in.

Requirements in consumer repos (all standard): the stamped `claude.yml`
(so @claude answers issues), the Claude GitHub App, and the
`CLAUDE_CODE_OAUTH_TOKEN` secret (`ANTHROPIC_API_KEY` on API-billing
forks — see [FORKING.md](FORKING.md#billing-subscription-or-api-key)).
Consumer repos carry **zero** propagation-specific config.

**Known limitation:** GitHub blocks App-token pushes that modify
`.github/workflows/` files, so a propagated update can deliver
everything *except* changes to the workflow files themselves — the
agent applies the rest and reports the workflow diff for a human to
apply (a one-line `git` push under your own account, which has the
`workflow` scope). Template changes to workflows are rare; when one
ships, expect that one manual step per repo.

## When to bump the plugin version

The version is the propagation trigger and comparison key, so it tracks
**template state only**: bump it when anything under
`plugins/factory/templates/` changes, and don't bump it for skill- or
doc-only changes — skills reach every CI agent on their next run without
a release, and a version bump would file stamp-only update PRs in every
repo for no delivered change.

This rule is enforced, not just documented. The **Version Guard**
workflow (`.github/workflows/version-guard.yml`) fails any PR whose diff
touches `plugins/factory/templates/**` without a version change in
`plugin.json` relative to the merge base; skill-only and doc-only PRs
pass untouched. The same check runs locally — `./scripts/validate.sh`
invokes `scripts/check-version-bump.sh`, which compares against
`origin/main` and skips gracefully when no merge base is derivable. To
run it standalone: `scripts/check-version-bump.sh [base-ref]`.

## How staleness is detected

`/factory-init` and `/factory-update` write a machine-readable stamp into
the CLAUDE.md standard block:

```
<!-- factory:version 0.5.0 -->
```

`factory-status` and the propagation workflow grep for that line and
compare against `plugins/factory/.claude-plugin/plugin.json` on the
marketplace's main. The comparison is **version-aware** (`sort -V`, not
string equality): stamped `<` latest is stale; stamped `==` latest is
current; stamped `>` latest is reported "ahead" and gets no update issue
(so a repo stamped from a newer testing branch is never downgraded).
Repos stamped before v0.5.0 have markers but no version line — they are
reported as "stamped, version unknown"; one `/factory-update` adds the
stamp.

## Fleet cost observability

The model-routing policy manages spend per task, but nothing aggregated it
across the fleet. `scripts/cost-report.sh` answers "what did the agents
cost this month?" using `gh` + `python3` only — no external service.

```bash
scripts/cost-report.sh                 # current month, authenticated gh owner
scripts/cost-report.sh --month 2026-06 # a specific month (UTC)
scripts/cost-report.sh --owner other-org --limit 200
```

It enumerates the owner's factory-stamped repos (the same `CLAUDE.md`
stamp detection the propagation workflow uses), lists that month's Claude
workflow runs, and pulls each run's `total_cost_usd` out of its run log
(the value the claude-code-action prints in its result JSON). Output is a
per-repo, per-workflow table with a grand total.

**It reports what it could not measure.** GitHub retains Actions logs for a
limited window (default ~90 days), so a run whose log has expired, is still
in progress, or never emitted a cost is counted as *unseen* and listed by
reason — never silently dropped or counted as zero. A month with all logs
expired prints an empty table with that explanation, which is expected.

**Suggested cadence:** run it on the **1st of each month for the month just
ended**, before that month's logs start aging out — the only way to capture
costs you would otherwise lose to the retention window. It is read-only and
safe to run ad hoc any time. There is no budget *alarm* yet; this is the
measurement layer an alarm would sit on.

## CI agent health

Never judge an @claude run by the green check — see the
`factory:ci-agent-ops` skill for health signals, the silent-failure
diagnosis order, and the smoke-test procedure. Seeded per repo as
`docs/memory/ci-claude-silent-failures.md`.

## Model transitions

When the model behind your agents changes — a new family ships, your plan's
top tier changes, or a workflow's pinned model is deprecated — skill behavior
can regress silently: the files didn't change, so nothing looks different
until an agent quietly stops following its process. Run this checklist the
day a transition happens:

1. **Tier 2 first** (free): `python3 scripts/run-evals.py`. Routing is
   model-independent, so this confirms the catalog itself is still coherent
   before you spend tokens.
2. **Targeted Tier 3** (tokens): `python3 scripts/run-evals.py --behavioral
   <skill>` for the skills whose failure is expensive — the CI-facing ones
   first (`release-flow`, `ci-agent-ops`). A new-model regression here means
   the skill's wording leaned on the old model's judgment: tighten the
   instructions until it passes, don't wait for a fleet incident.
3. **Re-check model pins.** Workflow templates pin models by name
   (`claude.yml`, `claude-code-review.yml`); agent definitions pin tiers.
   Deprecated names fail loudly, but a *renamed cheaper tier* can leave
   judgment work under-modeled — review pins against the `model-routing`
   skill's policy, bump the plugin version, and let propagation carry the
   fix to the fleet.
4. **Smoke the CI agent** per `factory:ci-agent-ops` — a model swap in the
   Action is exactly the kind of change its silent-failure modes love.

## Rolling back a bad skill, and pinning against one

Skills auto-propagate from `main` with no version gate (the skills row of
the four-channel table above). That trades a release step for a rollback
story. Here is the whole story, and the one opt-in that buys a repo
stability if it wants it.

### A skill edit on main breaks CI agents — what do you run?

1. **Revert on `main`.** `main` is PR-guarded, so `git revert <sha>`, open
   a PR, and merge it (or push a one-file PR restoring the last-good skill).
   There is no tag to move and no release to cut — for this system the
   marketplace *is* `main`.
2. That is the entire action. Each environment re-converges on its own
   schedule (next table); you never touch consumer repos to fix a bad skill.

**Why revert-on-`main` is the only lever for CI agents.** The `@claude`
GitHub Action installs the plugin with
`plugin_marketplaces: https://github.com/onurcelep/ai-factory.git` and runs
`claude plugin marketplace add <url>` against that URL's **default branch**.
The Action's input validator rejects any URL that does not end in `.git`
(`claude-code-action`'s `base-action/src/install-plugins.ts`,
`MARKETPLACE_URL_REGEX = /^https:\/\/…\.git$/`), so no `#ref` / `?ref=` /
sha suffix is accepted and a CI run cannot be pointed at a pinned ref. The
marketplace a CI agent sees is always `main`. Ref-pinning the CI channel is
**not supported upstream**; reverting `main` is the mechanism.

### Convergence time per environment

| Environment | How it fetches skills | Time to pick up the revert | In-flight work |
|---|---|---|---|
| `@claude` GitHub Action (CI agents) | fresh `marketplace add` + `plugin install` at the start of **every** run — no cache, no pin | **Next `@claude` run** after the revert merges | A run already executing keeps the bad skill until it ends |
| Claude Code **cloud** session | plugin fetched at session start | **Next new session** | An open session keeps the bad skill for its whole lifetime |
| Claude Code **local** session | cached plugin, refreshed on `claude plugin update` or the periodic cache refresh | After `claude plugin update factory@<marketplace>` (or the next periodic refresh), **per machine** | An open session keeps the bad skill for its whole lifetime |

The fleet is healthy once the revert PR is merged **and** every environment
has turned over per the middle column. CI has no cache, so it is the
fastest to heal (next run); a machine with a long-lived local session is
the slowest. The floor is "merge the revert" — there is no faster lever for
CI, and nothing slower you must wait on beyond a machine's `plugin update`.

### Pin a consumer repo to a known-good skills version (opt-in)

A repo that values stability over freshness can pin the marketplace source
to a **tag or commit SHA** in its committed `.claude/settings.json`. This
is a documented `extraKnownMarketplaces` capability
(`https://docs.claude.com/en/docs/claude-code/plugin-marketplaces`):

```json
{
  "extraKnownMarketplaces": {
    "onur": {
      "source": {
        "source": "github",
        "repo": "onurcelep/ai-factory",
        "ref": "v0.5.0",
        "sha": "<full-commit-sha>"
      }
    }
  }
}
```

When both are set the `sha` is the effective pin: Claude Code checks out
that commit directly, and the install still succeeds even if the branch or
tag named by `ref` is later deleted upstream, as long as the commit stays
reachable. Rolling forward is a one-line edit to a newer `ref`/`sha`;
rolling back is editing it to an older one. The pin **survives
`/factory-update`**: the settings merge treats `ref`/`sha` as repo-owned
and never removes them (`scripts/lib/factory_stamp.py merge-settings`,
golden-tested).

**This escape hatch covers local and cloud sessions only.** The `@claude`
Action cannot honor it — its `plugin_marketplaces` input takes a bare
`.git` URL (above), so a pinned consumer still gets `main`-tracking skills
in CI. There is therefore no per-repo way to freeze CI today; keeping
ai-factory's `main` known-good (the revert runbook above) is the
fleet-wide control, and per-repo pinning is a local/cloud comfort layer on
top of it.

**Why there is no `stable`-tag release channel.** The tempting design —
have workflows fetch the marketplace at a moving `stable` tag and promote
`main → stable` deliberately — cannot work for CI, because the Action's
`plugin_marketplaces` input rejects a pinned ref (above). A `stable` tag
would gate only the local/cloud half of the fleet while CI kept tracking
`main`, so it would add a promotion ritual without actually protecting the
channel that matters most. Rejected in favor of the revert runbook, which
is one lever that covers the whole fleet.

**Also considered, not chosen: a stable-mirror promotion repo.** A second
repo whose default branch is only ever fast-forwarded from this one by a
deliberate promotion act would give CI a real release gate (the Action
reads the default branch of whatever URL it is given). Rejected for now:
it adds a second repo, a promotion ritual, and a fleet-wide workflow-URL
change — permanent upkeep to hedge a risk the revert runbook already
covers in one merge. Revisit if the fleet grows beyond one operator or
upstream adds ref support to the Action's `plugin_marketplaces` input.

Two stamped guards automate what the skill describes, so a bad
`CLAUDE_CODE_OAUTH_TOKEN` no longer waits for a human to notice a
missing artifact:

- **`claude-smoke-test.yml`** — a weekly (off-minute cron) plus
  on-demand (`workflow_dispatch`) liveness probe. It runs a one-turn
  Haiku "pong" and fails red if the action's `execution_file` result
  message matches the dead-on-arrival signature (`is_error:true` /
  `num_turns:1` / `total_cost_usd:0`). Run it manually from the Actions
  tab right after any token / secret / App change.
- **Post-run assertions** in `claude.yml` and `claude-code-review.yml`
  — after the action step, an assertion parses the same `execution_file`
  and fails on that exact three-way conjunction, so a dead token turns
  the very first affected run red instead of green. Honest failures
  (max-turns, push 403) already report red, so the conjunction is scoped
  to fire only on the silent case.
