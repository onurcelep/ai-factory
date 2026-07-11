#!/usr/bin/env bash
# PreToolUse(Bash) guard: block direct pushes to main/master in local
# sessions of factory-stamped repos, making release-flow invariant 1
# ("nobody pushes main directly") mechanical where GitHub rulesets don't
# reach (local sessions; private repos without rulesets).
#
# Deliberately fail-open: any error in this script must never block a
# legitimate command — the ruleset on GitHub remains the backstop.
# Escape hatch (e.g. a brand-new repo's very first push):
#   FACTORY_ALLOW_MAIN_PUSH=1
set -u

[ "${FACTORY_ALLOW_MAIN_PUSH:-0}" = "1" ] && exit 0

FACTORY_HOOK_INPUT=$(cat 2>/dev/null) || exit 0
export FACTORY_HOOK_INPUT

python3 - <<'PY' >/dev/null 2>&1
# exit 0 = allow silently, exit 3 = push-to-main (blocked by the shell below)
import json, os, re, shlex, subprocess, sys

PROTECTED = ("main", "master")

try:
    data = json.loads(os.environ.get("FACTORY_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

cmd = (data.get("tool_input") or {}).get("command") or ""
if "git push" not in cmd:
    sys.exit(0)

# Only guard factory-stamped repos: limits blast radius to repos that
# actually adopted the standard (the plugin may be enabled user-wide).
cwd = data.get("cwd") or "."
try:
    with open(f"{cwd}/CLAUDE.md", encoding="utf-8") as f:
        if "factory:standard:begin" not in f.read():
            sys.exit(0)
except Exception:
    sys.exit(0)


def current_branch() -> str:
    try:
        return subprocess.run(
            ["git", "-C", cwd, "branch", "--show-current"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except Exception:
        return ""


def pushes_protected(segment: str) -> bool:
    try:
        toks = shlex.split(segment)
    except ValueError:
        return False
    for i in range(len(toks) - 1):
        if toks[i].endswith("git") and toks[i + 1] == "push":
            args = toks[i + 2:]
            break
    else:
        return False
    if "--delete" in args or "-d" in args:
        return False  # deleting a remote branch is not "pushing main"
    refs = [t for t in args if not t.startswith("-")]
    # refs = [remote, refspec...]; a bare push (no refspec) pushes HEAD
    if len(refs) <= 1:
        return current_branch() in PROTECTED
    for spec in refs[1:]:
        dst = spec.split(":", 1)[1] if ":" in spec else spec
        if dst in PROTECTED or dst in tuple(f"refs/heads/{b}" for b in PROTECTED):
            return True
        if spec in ("HEAD",) and current_branch() in PROTECTED:
            return True
    return False


for segment in re.split(r"&&|\|\||[|;]", cmd):
    if "git push" in segment and pushes_protected(segment):
        sys.exit(3)

sys.exit(0)
PY

status=$?
if [ "$status" = "3" ]; then
  echo "factory release-flow: direct pushes to main/master are blocked — every change ships via a short-lived branch and a PR (factory:release-flow skill). If this push is genuinely intended (e.g. a brand-new repo's first push), re-run with FACTORY_ALLOW_MAIN_PUSH=1." >&2
  exit 2
fi
exit 0
