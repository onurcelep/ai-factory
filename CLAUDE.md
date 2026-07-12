# ai-factory — agent notes

This repo IS the standard other repos get stamped with: a skill edit here
reaches every CI agent in the fleet on its next run, ungated. Work
accordingly.

- **Docs are hub-and-spoke.** The README's "Where to go" table routes each
  question to exactly one doc (`docs/WORKING.md`, `docs/OPERATIONS.md`,
  `docs/FORKING.md`, `docs/DECISIONS.md`, `docs/SECURITY-MODEL.md`,
  `evals/README.md`, `CONTRIBUTING.md`). Read the one the task needs, not
  all of them; every fact has one canonical home — link to it, never
  restate it.
- **Before pushing:** `bash scripts/validate.sh` must print
  `ALL CHECKS PASSED`. CI runs the same suite on every PR.
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
