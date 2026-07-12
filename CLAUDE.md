# ai-factory — agent notes

This repo IS the standard other repos get stamped with: a skill edit here
reaches every CI agent in the fleet on its next run, ungated. Work
accordingly.

**Scope by role:** the gates below bind agents *changing* this repo. If
you are a read-only agent (the PR reviewer, an auditor), do not attempt
to run the validation suite or evals — your tool allowlist will deny it;
assess against the rules instead and report what you'd expect the gates
to catch.

- **Docs are hub-and-spoke.** The README's "Where to go" table routes each
  question to exactly one doc (`docs/WORKING.md`, `docs/OPERATIONS.md`,
  `docs/FORKING.md`, `docs/DECISIONS.md`, `docs/SECURITY-MODEL.md`,
  `evals/README.md`, `CONTRIBUTING.md`). Read the one the task needs, not
  all of them; every fact has one canonical home — link to it, never
  restate it.
- **Before pushing changes:** `bash scripts/validate.sh` must print
  `ALL CHECKS PASSED`. CI runs the same suite on every PR, so there is
  no need to re-run it from a review context.
- **The rules it enforces** are explained in `CONTRIBUTING.md` — notably:
  every skill ships an eval case (`evals/cases/<name>.json`), the plugin
  version bumps only for template changes, dogfooded workflows stay
  byte-identical to their templates, and nothing may hardcode the owner.
- **Know the layer you're touching:** skills propagate immediately;
  templates are version-gated snapshots (`CONTRIBUTING.md` has the
  blast-radius details). For a skill change that guards behavior, run its
  behavioral eval first.
- **Branch + PR always; humans merge.** The `release-flow` skill applies
  to this repo too.
