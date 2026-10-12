# Bare --force-with-lease rejects pushes from a single-branch clone

Learned: 2026-10-12 (re-verify before acting if the area has changed)

A bare `git push --force-with-lease origin <b>` takes its expected value
from the remote-tracking ref that the remote's fetch refspec maps `<b>`
to. A `--single-branch` clone maps only the default branch, so a push to
any other branch is rejected as `(stale info)`, even right after an
explicit `git fetch origin +refs/heads/<b>:refs/remotes/origin/<b>`. It
looks correct, and it fails only when the branch already exists on the
remote, i.e. on reruns. How to apply: from a single-branch clone, always
pass the lease explicitly: `--force-with-lease=refs/heads/<b>:<sha>` with
the fetched sha, or an empty value (`refs/heads/<b>:`) to require that
the branch does not exist yet. `scripts/propagate.py` does this.
