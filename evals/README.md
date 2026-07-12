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

An eval may declare `"role": "readonly"` — the executor then runs with an
assess-only allowlist (Read/Glob/Grep, like the PR reviewer's posture)
instead of the full toolbox. Use it to test the role contract
(docs/SECURITY-MODEL.md): given a change-shaped task it cannot perform,
the agent must report its limitation, not flail against denials.

## Trust and upkeep

**Stability baseline** (2026-07-12, release-flow#1, fixtured): 4/4 graded
runs passed across separate invocations. Two additional attempts hit
subscription usage limits — the runner distinguishes those (executor exit,
evidence in `evals/results/*.debug/`, `total_cost_usd: 0`,
`terminal_reason: api_error`) from skill failures; do not count them
against a skill. Re-measure after any grader or model change.

**Hermeticity caveat:** behavioral evals run in the operator's local
harness, and the environment leaks in — plugins, MCP servers, harness
tools. The readonly role closes the known escape hatches
(`--strict-mcp-config`, disallowed Task/ToolSearch — added after an eval
agent found a local MCP shell tool to route around its denials), but
default-role results still reflect skill + model + *environment*.
Compare runs across machines with care; a CI-hermetic runner is future
work.

**Regression rule:** every *real* routing miss or rule violation observed
in actual use becomes a case entry — a trigger prompt for a routing miss,
an expectation (or new eval) for a behavior miss. Authored prompts prove
the descriptions match our guesses; accumulated real misses are what make
the suite ground truth.
