# Operating ai-factory

The one page that answers "what do I run, and when". Written for someone
who has never seen this system.

## The mental model: four channels

Everything ai-factory ships travels on exactly one of four channels. When
something changes, ask "which channel does it ride?" — that determines
what, if anything, you do.

| What changed in ai-factory | Channel | Reaches CI agents | Reaches local sessions | You do |
|---|---|---|---|---|
| A **skill** (`plugins/factory/skills/`) | Plugin marketplace | Automatically, next @claude run (workflows fetch the plugin fresh every run) | After `claude plugin update factory@<marketplace>` (or the periodic cache refresh) | Nothing per repo; update the local plugin per machine |
| A **template** (`plugins/factory/templates/`) | `/factory-update`, per repo | After the update PR merges | Same | Merge the auto-filed update PR (or run `/factory-update` manually) |
| A **seeded memory** (`templates/*.md` fact files) | `/factory-init`, new repos only | On repos initialized after the change | Same | Nothing — existing repos own their memory files |
| Repo content (`## Project`, `docs/memory/`, code) | None — repo-owned | — | — | Factory never touches it |

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
`CLAUDE_CODE_OAUTH_TOKEN` secret. Consumer repos carry **zero**
propagation-specific config.

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

## CI agent health

Never judge an @claude run by the green check — see the
`factory:ci-agent-ops` skill for health signals, the silent-failure
diagnosis order, and the smoke-test procedure. Seeded per repo as
`docs/memory/ci-claude-silent-failures.md`.
