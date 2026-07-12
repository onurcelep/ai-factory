# Contributing

These rules apply equally to PRs against this repo and to changes you
make in your own fork — they're what keeps the standard trustworthy
enough to stamp into a fleet.

## The one command

```bash
bash scripts/validate.sh    # must print: ALL CHECKS PASSED
```

Run it before pushing anything. CI runs the same suite on every PR
(`validate` workflow), so a red run locally is a red PR. The suite checks
cross-file *consistency*, never owner-specific literals, so it passes
unchanged on any rebranded fork.

## The rules the suite enforces

| Rule | Why | Enforced by |
|---|---|---|
| Every skill ships an eval case (`evals/cases/<name>.json`: ≥3 positive triggers, ≥2 negative, ≥1 behavioral) | Skills are prose and regress silently; untested rules are hypotheses | `scripts/run-evals.py` (tier 2, in CI) |
| A tier-2 trigger failure means **fix the skill's description**, not the test prompt | The prompts model how users actually ask; if a realistic ask can't find the skill, the description is the bug | [evals/README.md](evals/README.md) |
| Bump the plugin version **only** when `plugins/factory/templates/**` changes | The version drives fleet propagation; a doc- or skill-only bump files pointless update PRs in every repo | `version-guard` workflow + `scripts/check-version-bump.sh` |
| Workflows in `.github/workflows/` that share a basename with a template stay **byte-identical** to it | This repo dogfoods its own templates; drift here means shipping something untested | validate.sh (re-sync: `cp plugins/factory/templates/<name> .github/workflows/<name>`) |
| No owner/marketplace literals in functional code or checks | Forks must validate green after `rebrand.sh` with zero patches | validate.sh derives names from the manifests |
| Auth is either `CLAUDE_CODE_OAUTH_TOKEN` (subscription, shipped default) or `ANTHROPIC_API_KEY` (API-billing forks) | See [FORKING.md § Billing](docs/FORKING.md#billing-subscription-or-api-key) | validate.sh accepts either |

## Changing skills vs. changing templates

The two layers have different blast radii — know which one you're
touching:

- **Skills** (`plugins/factory/skills/`) propagate from `main` with no
  version gate: every CI agent picks up the change on its next run. That
  freshness is deliberate, but it means a bad skill edit is a fleet-wide
  incident — the rollback runbook is in
  [OPERATIONS.md](docs/OPERATIONS.md#rolling-back-a-bad-skill-and-pinning-against-one).
  For a skill change that guards *behavior* (release discipline, safety
  rules), run its behavioral eval before merging:
  `python3 scripts/run-evals.py --behavioral <skill>` (spends tokens).
- **Templates** (`plugins/factory/templates/`) are snapshots: nothing
  reaches a repo until `/factory-update` runs there (or propagation files
  the update PR). Bump the version, and propagation handles the fleet.

## PR flow

Branch off `main`, open a PR, let the automatic review run, a human
merges. The same `release-flow` discipline the plugin ships applies to
the plugin's own repo — agents prepare, humans merge.

## What the other directories are

`docs/superpowers/` (specs, plans) and `.superpowers/sdd/` (task briefs,
review diffs) are the **historical build record** of this repo — how each
piece was designed and reviewed. They're kept on purpose as the "reasoning
attached" part of the README's promise, but they are not user
documentation; nothing routes there.
