#!/usr/bin/env python3
"""Deterministic fleet propagation for ai-factory.

For every factory-stamped repo of an owner that is behind the current plugin
version, this clones the repo, applies the *mechanical* stamp from
`scripts/lib/factory_stamp.py` (the same reference implementation the golden
tests pin), commits on `factory-update/<version>`, pushes, and opens a pull
request. Nothing is merged: a human still does that.

Where the deterministic path cannot reach, the repo falls back to the old
route -- an `@claude` issue asking the responder to run `/factory-update` --
with the reason in the body, so no repo is ever silently skipped.

The stamp is mechanical only: workflow files, `.claude/settings.json` wiring,
the marker-fenced CLAUDE.md block, and the memory index when absent. Anything
needing judgement (AGENTS.md build/test commands, a repo that diverged from
the templates) is a fallback, not a guess.

Dry run: `--dry-run` (or FACTORY_PROPAGATE_DRY_RUN=1) prints the per-repo plan
and writes nothing anywhere.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import factory_stamp  # noqa: E402  (path set above)

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = "plugins/factory/templates"
PLUGIN_JSON = "plugins/factory/.claude-plugin/plugin.json"

CLAUDE_MD = "CLAUDE.md"
# The stamp marker a repo must carry to be part of the fleet (the full begin
# marker, minus the parenthetical, lives in factory_stamp.BEGIN).
STAMP_MARKER = "factory:standard:begin"
SETTINGS = ".claude/settings.json"
MEMORY_INDEX = "docs/memory/MEMORY.md"
MEMORY_SEED = "docs/memory/ci-claude-silent-failures.md"

# Outcomes, in the vocabulary the job summary and the tests use.
CHANGED = "changed"      # stamp produced a diff -> branch pushed, PR opened/updated
UNCHANGED = "unchanged"  # stamp was a no-op -> nothing pushed
FALLBACK = "fallback"    # deterministic path refused -> @claude issue filed
CURRENT = "current"      # already on this version
AHEAD = "ahead"          # stamped from a newer version; never downgraded

GIT_AUTHOR_NAME = "ai-factory propagation"
GIT_AUTHOR_EMAIL = "ai-factory-propagation@users.noreply.github.com"


# --------------------------------------------------------------------------
# Pure helpers (no network, no filesystem): the part the unit tests cover.
# --------------------------------------------------------------------------

def version_key(version: str) -> tuple:
    """Sort key for a dotted version. Numeric segments compare numerically;
    anything else compares as text after the numbers (so 0.6.10 > 0.6.9 and
    0.6.10 > 0.6.10-rc1 is not claimed -- unknown shapes just sort low)."""
    parts = []
    for segment in re.split(r"[.\-+]", version or ""):
        if segment.isdigit():
            parts.append((1, int(segment), ""))
        elif segment:
            parts.append((0, 0, segment))
    return tuple(parts)


def stamped_version(claude_md: str) -> str | None:
    """The machine-readable stamp `/factory-update` writes, or None."""
    match = re.search(r"factory:version\s+([0-9][0-9A-Za-z.\-+]*)", claude_md or "")
    return match.group(1) if match else None


def staleness(stamped: str | None, latest: str) -> str:
    """CURRENT / AHEAD / '' (stale, including an unversioned stamp)."""
    if stamped is None:
        return ""
    if stamped == latest:
        return CURRENT
    return AHEAD if version_key(stamped) > version_key(latest) else ""


@dataclass
class StampPlan:
    """What the mechanical stamp would write, and what it refuses to touch."""

    writes: dict[str, str] = field(default_factory=dict)
    unreconcilable: list[str] = field(default_factory=list)

    @property
    def files(self) -> list[str]:
        return sorted(self.writes)


def plan_workflow(target: str, repo_file: str | None, template: str,
                  baseline: str | None, plan: StampPlan) -> None:
    """A workflow file is reconcilable only when the repo's copy is a template
    copy: identical to the new one (nothing to do) or to the one it was stamped
    from (a clean upgrade). Anything else carries repo-owned edits the
    mechanical stamp would destroy."""
    if repo_file is None:
        plan.writes[target] = template  # new standard file
    elif repo_file == template:
        pass
    elif baseline is not None and repo_file == baseline:
        plan.writes[target] = template
    else:
        plan.unreconcilable.append(
            f"{target}: modified locally (matches neither the current template "
            f"nor the one it was stamped from)")


def plan_stamp(repo_files: dict[str, str | None], templates: dict[str, str],
               baselines: dict[str, str | None], version: str) -> StampPlan:
    """Compute the whole stamp as a set of file writes. Pure: callers supply
    file contents, so this is fully testable without a repo."""
    plan = StampPlan()

    for target, template in sorted(templates.items()):
        if target.startswith(".github/workflows/"):
            plan_workflow(target, repo_files.get(target), template,
                          baselines.get(target), plan)

    settings_template = templates.get(SETTINGS)
    current = repo_files.get(SETTINGS)
    if settings_template is not None:
        if current is None:
            plan.writes[SETTINGS] = settings_template
        else:
            try:
                before = json.loads(current)
                merged = factory_stamp.merge_settings(
                    json.loads(current), json.loads(settings_template))
            except (json.JSONDecodeError, TypeError, AttributeError) as exc:
                plan.unreconcilable.append(f"{SETTINGS}: unreadable JSON ({exc})")
            else:
                # Compare parsed, write rendered: a repo that formats its
                # settings differently is not stale, and must not be reformatted
                # on every propagation.
                if merged != before:
                    plan.writes[SETTINGS] = json.dumps(
                        merged, indent=2, ensure_ascii=False) + "\n"

    claude_template = templates.get(CLAUDE_MD)
    claude_current = repo_files.get(CLAUDE_MD)
    if claude_template is not None:
        if claude_current is None:
            plan.unreconcilable.append(f"{CLAUDE_MD}: missing; run /factory-init")
        else:
            try:
                spliced = factory_stamp.update_splice(
                    claude_current, claude_template, version)
            except ValueError as exc:
                plan.unreconcilable.append(f"{CLAUDE_MD}: {exc}")
            else:
                if spliced != claude_current:
                    plan.writes[CLAUDE_MD] = spliced

    for target in (MEMORY_INDEX, MEMORY_SEED):
        template = templates.get(target)
        if template is not None and repo_files.get(target) is None:
            plan.writes[target] = template  # create-if-missing; never overwrite

    return plan


def classify_outcome(plan: StampPlan, push_error: str | None = None) -> str:
    """changed / unchanged / fallback, from the stamp plan and the push result.

    A file the stamp refuses to reconcile sends the whole repo down the
    fallback path: a partial stamp would leave the repo in a state neither the
    version guard nor the next propagation can reason about."""
    if plan.unreconcilable:
        return FALLBACK
    if push_error:
        return FALLBACK
    return CHANGED if plan.writes else UNCHANGED


def fallback_reason(plan: StampPlan, push_error: str | None = None) -> str:
    if plan.unreconcilable:
        return "files the mechanical stamp cannot reconcile: " + \
            "; ".join(plan.unreconcilable)
    return push_error or ""


def pr_body(version: str, files: list[str]) -> str:
    """Plain-ASCII PR body. No trailers, no generated-with line."""
    listing = "\n".join(f"- {f}" for f in files)
    return f"""Automatic propagation from ai-factory: this restamps the standard
files from the templates at plugin version {version}.

Files in this PR:

{listing}

Workflow files under .github/workflows/ are included. Propagation pushes
with a PAT that carries the workflow scope, so the manual follow-up step
that used to accompany a template change is gone.

If this PR changes the review workflow, the automatic review check does
not run on it: the action refuses to run a workflow file that differs
from the default branch. That skip reports green with a notice, and the
review runs normally on the next PR after this one merges.

Nothing here is merged automatically. Review and merge as usual.
"""


def issue_body(version: str, stamped: str | None, reason: str) -> str:
    """The @claude fallback, with the reason the deterministic path stepped
    aside. Kept as one paragraph: the responder reads it as instructions."""
    why = f"\n\nAutomatic propagation did not open a PR for this repo: {reason}" if reason else ""
    return (
        f"@claude the ai-factory standard changed on main (now v{version}; this repo "
        f"is stamped {stamped or 'pre-0.5.0'}). Run /factory-update per the "
        "factory:factory-update skill. Your session's plugin cache was installed fresh "
        "from the marketplace at run start, so stamp directly from "
        "${CLAUDE_PLUGIN_ROOT}/templates/ - do not attempt git clone or network fetches "
        "(the sandbox blocks them). Refresh the settings wiring and the CLAUDE.md "
        "standard block (including its version stamp - that alone closes this issue even "
        "if nothing else changed). Workflow files under .github/workflows/ are OFF LIMITS "
        "in this session: this Action's token cannot write there, so never call Edit or "
        "Write on them - Read-diff them against the templates instead and report the exact "
        "diff in your summary for a human to apply by hand, per the factory:factory-update "
        "skill's Action-session limitation. Commit only the files you actually changed on a "
        "claude/ branch and push. Post the Create PR link when done. Touch nothing outside "
        "the stamped files and the standard block." + why
    )


# --------------------------------------------------------------------------
# IO layer: git, gh, and the ai-factory checkout.
# --------------------------------------------------------------------------

class CommandError(RuntimeError):
    def __init__(self, cmd: list[str], result: subprocess.CompletedProcess):
        self.stderr = (result.stderr or "").strip()
        self.returncode = result.returncode
        super().__init__(f"{cmd[0]} {' '.join(cmd[1:3])} failed: {self.stderr[:400]}")


def run(cmd: list[str], cwd: Path | None = None, check: bool = True,
        redact: str | None = None) -> subprocess.CompletedProcess:
    shown = [c.replace(redact, "***") for c in cmd] if redact else cmd
    print(f"  $ {' '.join(shown)}", flush=True)
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise CommandError(cmd, result)
    return result


def gh_json(args: list[str]) -> object:
    return json.loads(run(["gh", *args]).stdout or "null")


def is_permission_error(message: str) -> bool:
    lowered = message.lower()
    return any(marker in lowered for marker in (
        "403", "permission", "not authorized", "resource not accessible",
        "denied", "workflow scope", "must have admin"))


def template_targets(root: Path) -> dict[str, str]:
    """target path in a consumer repo -> template content, read from `root`."""
    src = root / TEMPLATES
    targets = {}
    for path in sorted(src.glob("*.yml")):
        targets[f".github/workflows/{path.name}"] = path.read_text(encoding="utf-8")
    targets[SETTINGS] = (src / "settings.json").read_text(encoding="utf-8")
    targets[CLAUDE_MD] = (src / "CLAUDE.md.tmpl").read_text(encoding="utf-8")
    targets[MEMORY_INDEX] = (src / "MEMORY.md.tmpl").read_text(encoding="utf-8")
    targets[MEMORY_SEED] = (src / "ci-claude-silent-failures.md").read_text(encoding="utf-8")
    return targets


def baseline_targets(root: Path, version: str | None) -> dict[str, str | None]:
    """The workflow templates as they were at `version`, so an untouched
    consumer file can be told apart from a locally modified one. Empty when the
    version cannot be located in history (then every differing file is treated
    as modified: never clobber what we cannot explain)."""
    if not version:
        return {}
    commits = run(["git", "log", "--format=%H", "--", PLUGIN_JSON],
                  cwd=root, check=False)
    match = None
    for sha in commits.stdout.split():
        blob = run(["git", "show", f"{sha}:{PLUGIN_JSON}"], cwd=root, check=False)
        if blob.returncode != 0:
            continue
        try:
            if json.loads(blob.stdout).get("version") == version:
                match = sha
                break
        except json.JSONDecodeError:
            continue
    if match is None:
        return {}
    baselines: dict[str, str | None] = {}
    for name in sorted((root / TEMPLATES).glob("*.yml")):
        blob = run(["git", "show", f"{match}:{TEMPLATES}/{name.name}"],
                   cwd=root, check=False)
        baselines[f".github/workflows/{name.name}"] = (
            blob.stdout if blob.returncode == 0 else None)
    return baselines


@dataclass
class RepoResult:
    repo: str
    stamped: str | None
    outcome: str
    detail: str = ""


def read_repo_files(work: Path, targets: list[str]) -> dict[str, str | None]:
    files: dict[str, str | None] = {}
    for target in targets:
        path = work / target
        files[target] = path.read_text(encoding="utf-8") if path.is_file() else None
    return files


def apply_plan(work: Path, plan: StampPlan) -> None:
    for target, content in plan.writes.items():
        path = work / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def open_or_update_pr(slug: str, branch: str, base: str, version: str,
                      files: list[str]) -> str:
    existing = gh_json(["pr", "list", "-R", slug, "--head", branch,
                        "--state", "open", "--json", "number,url"]) or []
    if existing:
        return f"updated {existing[0]['url']}"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
        handle.write(pr_body(version, files))
        body_file = handle.name
    try:
        created = run(["gh", "pr", "create", "-R", slug, "--base", base,
                       "--head", branch, "--title", f"factory-update to {version}",
                       "--body-file", body_file])
    finally:
        os.unlink(body_file)
    return f"opened {created.stdout.strip().splitlines()[-1]}"


def file_fallback_issue(slug: str, version: str, stamped: str | None,
                        reason: str) -> str:
    title = f"factory-update to {version}"
    existing = gh_json(["issue", "list", "-R", slug, "--state", "open",
                        "--search", f'"{title}" in:title', "--json", "number,url"]) or []
    if existing:
        return f"issue already open: {existing[0]['url']}"
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
        handle.write(issue_body(version, stamped, reason))
        body_file = handle.name
    try:
        created = run(["gh", "issue", "create", "-R", slug, "--title", title,
                       "--body-file", body_file])
    finally:
        os.unlink(body_file)
    return f"filed {created.stdout.strip().splitlines()[-1]}"


def propagate_repo(slug: str, stamped: str | None, version: str, root: Path,
                   templates: dict[str, str], token: str, dry_run: bool) -> RepoResult:
    """Stamp one consumer repo. Never raises: every failure becomes a fallback."""
    name = slug.split("/")[-1]
    branch = f"factory-update/{version}"
    work = Path(tempfile.mkdtemp(prefix=f"propagate-{name}-"))
    checkout = work / "repo"
    try:
        url = f"https://x-access-token:{token}@github.com/{slug}.git"
        try:
            run(["git", "clone", "--filter=blob:none", "--single-branch", url,
                 str(checkout)], redact=token)
        except CommandError as exc:
            return RepoResult(slug, stamped, FALLBACK, f"clone failed: {exc.stderr[:200]}")

        base = run(["git", "rev-parse", "--abbrev-ref", "HEAD"],
                   cwd=checkout).stdout.strip()
        repo_files = read_repo_files(checkout, list(templates))
        baselines = baseline_targets(root, stamped)
        plan = plan_stamp(repo_files, templates, baselines, version)

        outcome = classify_outcome(plan)
        if outcome == FALLBACK:
            reason = fallback_reason(plan)
            if dry_run:
                return RepoResult(slug, stamped, FALLBACK, f"would file issue: {reason}")
            return RepoResult(slug, stamped, FALLBACK,
                              file_fallback_issue(slug, version, stamped, reason))

        if outcome == UNCHANGED:
            return RepoResult(slug, stamped, UNCHANGED,
                              "stamp is a no-op; nothing to propagate")

        if dry_run:
            return RepoResult(slug, stamped, CHANGED,
                              f"would push {branch} and open a PR: {', '.join(plan.files)}")

        try:
            run(["git", "checkout", "-b", branch], cwd=checkout)
            apply_plan(checkout, plan)
            run(["git", "add", "--", *plan.files], cwd=checkout)
            run(["git",
                 "-c", f"user.name={GIT_AUTHOR_NAME}",
                 "-c", f"user.email={GIT_AUTHOR_EMAIL}",
                 "commit", "-m", f"factory-update to {version}",
                 "-m", "Restamp the ai-factory standard files from the templates "
                       "at this version. Mechanical stamp only; repo-owned "
                       "content is untouched."], cwd=checkout)
            # Fetch the remote branch first so --force-with-lease has a lease
            # to check: reruns for the same version update their own PR and
            # nothing else.
            run(["git", "fetch", "origin",
                 f"+refs/heads/{branch}:refs/remotes/origin/{branch}"],
                cwd=checkout, check=False)
            run(["git", "push", "--force-with-lease", "origin", branch], cwd=checkout)
            detail = open_or_update_pr(slug, branch, base, version, plan.files)
        except CommandError as exc:
            reason = ("push or PR creation was refused for permission reasons: "
                      if is_permission_error(exc.stderr) else "push or PR creation failed: ")
            reason += exc.stderr[:200]
            outcome = classify_outcome(plan, push_error=reason)
            return RepoResult(slug, stamped, outcome,
                              file_fallback_issue(slug, version, stamped,
                                                  fallback_reason(plan, reason)))
        return RepoResult(slug, stamped, CHANGED, f"{detail} ({len(plan.files)} files)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def consumer_repos(owner: str, self_name: str, limit: int,
                   only: list[str]) -> list[tuple[str, str | None]]:
    """(slug, stamped version) for every factory-stamped repo of the owner."""
    names = only or [r["name"] for r in
                     gh_json(["repo", "list", owner, "--limit", str(limit),
                              "--json", "name"]) or []]
    found = []
    for name in names:
        if name == self_name:
            continue
        blob = run(["gh", "api", f"repos/{owner}/{name}/contents/{CLAUDE_MD}",
                    "--jq", ".content"], check=False)
        if blob.returncode != 0 or not blob.stdout.strip():
            continue
        try:
            claude_md = base64.b64decode(blob.stdout).decode("utf-8", "replace")
        except ValueError:
            continue
        if STAMP_MARKER not in claude_md:
            continue
        found.append((f"{owner}/{name}", stamped_version(claude_md)))
    return found


def write_summary(results: list[RepoResult]) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = ["| Repo | Stamped | Outcome | Detail |", "|---|---|---|---|"]
    for r in results:
        detail = r.detail.replace("|", "\\|")
        lines.append(f"| {r.repo} | {r.stamped or 'unversioned'} | {r.outcome} | {detail} |")
    table = "\n".join(lines)
    print("\n" + table)
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("## Propagation outcomes\n\n" + table + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--owner", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""))
    ap.add_argument("--self", dest="self_name",
                    default=os.environ.get("GITHUB_REPOSITORY", "/").split("/")[-1])
    ap.add_argument("--version", help="plugin version to propagate (default: this checkout's)")
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--only", default="", help="comma-separated repo names (skips discovery)")
    ap.add_argument("--dry-run", action="store_true",
                    default=os.environ.get("FACTORY_PROPAGATE_DRY_RUN") == "1",
                    help="print the per-repo plan; write nothing anywhere")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN", "")
    if not token:
        print("::notice::FACTORY_PROPAGATE_TOKEN not set - skipping propagation. "
              "See docs/OPERATIONS.md to enable.")
        return 0
    if not args.owner:
        print("propagate: --owner is required", file=sys.stderr)
        return 2

    version = args.version or json.loads((ROOT / PLUGIN_JSON).read_text())["version"]
    templates = template_targets(ROOT)
    only = [n for n in args.only.split(",") if n]
    print(f"Propagating factory v{version} for owner {args.owner}"
          f"{' (dry run)' if args.dry_run else ''}")

    results: list[RepoResult] = []
    for slug, stamped in consumer_repos(args.owner, args.self_name, args.limit, only):
        state = staleness(stamped, version)
        if state in (CURRENT, AHEAD):
            results.append(RepoResult(slug, stamped, state,
                                      "no update" if state == AHEAD else ""))
            continue
        results.append(propagate_repo(slug, stamped, version, ROOT, templates,
                                      token, args.dry_run))

    write_summary(results)
    unprocessed = [r for r in results
                   if r.outcome == FALLBACK and not r.detail.startswith(
                       ("filed", "issue already open", "would file"))]
    if unprocessed:
        for r in unprocessed:
            print(f"::error::{r.repo}: left unprocessed - {r.detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
