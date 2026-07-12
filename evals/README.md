# Skill evals

How this repo measures that its skills **trigger** when they should, **stay
distinct** from each other, and **change agent behavior** as promised.
Design ported from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)
(MIT); `evals[]` follows Anthropic skill-creator's `evals.json` schema, so its
tooling works against these files unmodified.

| Tier | What it checks | Runs | Cost |
|---|---|---|---|
| 1. Structural | Frontmatter, manifests, template parity | CI (`scripts/validate.sh`) | Free |
| 2. Trigger & routing | Positive prompts rank their skill top-k; negatives are outranked by their owner; no two descriptions near-collide | CI (`scripts/run-evals.py`) | Free |
| 3. Behavioral | An agent following the skill satisfies its `expectations[]` | Manual (`--behavioral`) | Tokens |

## Running

    python3 scripts/run-evals.py                                  # Tier 2, deterministic
    python3 scripts/run-evals.py --behavioral release-flow        # Tier 3, spends tokens
    python3 scripts/run-evals.py --behavioral all --dry-run       # print the plan only

Tier 2 is a lexical approximation (stemmed TF-IDF over descriptions). It can't
judge semantics — that's Tier 3 — but it catches the two failure modes that
dominate real trigger bugs: a description missing the vocabulary users say,
and an over-broad description that outranks the right skill. A Tier-2 failure
usually means *fix the description* (and bump the plugin version), not the eval.

## Why this exists

Skills fail silently: a headless agent whose process skill stops triggering
doesn't look broken — it quietly ships unverified work under a green check.
These evals make that failure loud, in CI, before it reaches a fleet. They are
also the model-transition harness: after any model or harness change, a Tier-2
run plus a targeted Tier-3 pass tells you which skills regressed.

## Case format

One file per skill: `evals/cases/<skill-name>.json` — see any existing case.
`trigger.positive[]` are realistic asks that must route here (`top_k` 1 for the
skill's signature ask); `trigger.negative[]` belong to another skill named in
`owner`, which must outrank this one. `evals[]` is skill-creator's schema;
an eval's `files[]` entries (`{path, content}`) are materialized into the
throwaway workspace and committed on `main` as the fixture before the run.
`trust_level: "provisional"` marks behavioral evals with no fixtures — treat
their results as sanity checks, not evidence (the release-flow smoke runs
proved why: without a fixture the agent has nothing real to act on, and the
grader correctly fails it for stopping to ask).

Every new skill ships with a case file (>=3 positive, >=2 negative, >=1
behavioral); the runner errors on missing files and warns below minimums.
