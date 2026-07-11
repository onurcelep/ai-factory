---
name: release-flow
description: Standard branch-and-PR release discipline (trunk-based, PR-per-change) for local work and the remote @claude CI agent. Use before branching, opening a PR, merging, deploying, or when acting as the @claude GitHub Actions agent.
---

# Release flow (trunk-based, PR-per-change)

One flow for every change, by anyone (human or @claude): work on a
short-lived branch, open a pull request, get it reviewed, then a human
merges to `main`. Nobody pushes to `main` directly — and in local sessions
of stamped repos this is mechanical, not advisory: the plugin's
`protect-main` hook blocks the push (override for legitimate cases, e.g. a
brand-new repo's first push, with `FACTORY_ALLOW_MAIN_PUSH=1`).

## The flow

1. Branch off `main` (short-lived, ideally named `claude/<topic>`).
2. Commit, then verify the change the way THIS repo verifies it (tests, a
   real browser, a smoke run) — see the repo's `## Project`.
3. Open a PR. The auto review (Opus) runs on it; run `/code-review`
   yourself too for anything nontrivial.
4. A human merges. @claude never merges, and running with `contents: read`
   it cannot push `main` even by accident.
5. Verify after merge (see invariants).

## Invariants (hold for every repo)

1. **`main` is always releasable.** Never knowingly merge something red.
2. **Every user-facing change is reviewed before it merges** — the PR
   review, plus `/code-review` when the change warrants it.
3. **Branches are short-lived.** Merge within about a day; do not let a
   branch diverge from `main`. Long-lived branches are what cause painful
   conflicts and cross-session collisions.
4. **Verify after merge.** Confirm the deployed artifact actually changed
   (a marker curl, a smoke check, whatever the repo provides).

## What "merge to main" means is per-repo

Merging is the single integration point, but its side effect differs by
repo and is documented in each repo's `## Project`:

- Some repos deploy on merge (merge = release).
- Some deploy only *part* of the tree on merge (e.g. a site, with other
  paths ignored). Know which paths trigger a deploy.
- Some ship through a separate, deliberate release train (a version bump
  plus a tag that builds a package). A merge must NOT trigger those; only
  the deliberate act does. Never conflate "merged" with "released" for
  these.

Hold any outward-facing release step (store upload, publishing a package,
tagging a version) for explicit human intent, never as a side effect of a
merge.
