#!/usr/bin/env python3
"""Reference implementation of ai-factory's *mechanical* stamping semantics.

The /factory-init and /factory-update skills are natural-language programs run
by an LLM. Their prose describes several purely mechanical transforms that must
be byte-exact and identical on every run. This module encodes those transforms
as executable truth so a skill-prose edit that changes behaviour is caught by
scripts/test-stamping.sh (golden-file diffs), and so the skills can point at a
reference instead of only prose.

It deliberately covers ONLY the mechanical parts — it does not decide build
commands, inspect repos, talk to git/gh, or generate prose. Those judgement
calls stay with the skill/LLM.

Transforms:
  init-claude    Stamp CLAUDE.md (the three cases from factory-init step 4).
  update-splice  Replace the marker-fenced standard block (factory-update step 4).
  merge-settings Merge the template's marketplace + plugin wiring into an
                 existing .claude/settings.json, preserving repo-owned keys.

Every transform is a pure function of its inputs and is idempotent: applying it
to its own output is a no-op. scripts/test-stamping.sh asserts that too.
"""

import argparse
import json
import re
import sys

# The markers are a hard contract shared with the templates and both skills.
# Verbatim, including the em dash.
BEGIN = "<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->"
END = "<!-- factory:standard:end -->"

HEADING = re.compile(r"^(#{1,6})(\s|$)")
FENCE = re.compile(r"^(```|~~~)")


def render(template: str, project_name: str, version: str, project_content: str) -> str:
    """Fill the template placeholders. Pure string substitution."""
    return (
        template.replace("{{PROJECT_NAME}}", project_name)
        .replace("{{FACTORY_VERSION}}", version)
        .replace("{{PROJECT_CONTENT}}", project_content)
    )


def demote(content: str) -> str:
    """Drop the old file's H1 title line and demote every remaining heading by
    one level, so the moved content becomes a valid subsection of `## Project`.

    Heading text and body stay byte-identical — only leading `#` markers and the
    single dropped H1 line change. `#` lines inside fenced code blocks are body,
    not headings, and are left untouched.
    """
    out = []
    in_fence = False
    dropped_h1 = False
    for line in content.split("\n"):
        if FENCE.match(line.lstrip()):
            in_fence = not in_fence
            out.append(line)
            continue
        if not in_fence:
            m = HEADING.match(line)
            if m:
                if m.group(1) == "#" and not dropped_h1:
                    dropped_h1 = True
                    continue  # drop the H1 title line entirely
                out.append("#" + line)  # demote by one level
                continue
        out.append(line)
    return "\n".join(out)


def init_claude(template: str, project_name: str, version: str,
                existing: str | None, project_content: str) -> str:
    """Stamp CLAUDE.md. The three cases from factory-init step 4."""
    if existing is not None and BEGIN in existing:
        # Markers already present -> already initialized; touch nothing.
        return existing
    if existing is None:
        # No CLAUDE.md -> render with a starter project skeleton.
        return render(template, project_name, version, project_content)
    # Exists without markers -> move the whole file under `## Project`,
    # demoted, and render the standard block above it.
    return render(template, project_name, version, demote(existing))


def extract_block(template: str, version: str) -> str:
    """The marker-fenced block from the template, version placeholder filled."""
    b = template.index(BEGIN)
    e = template.index(END) + len(END)
    return template[b:e].replace("{{FACTORY_VERSION}}", version)


def update_splice(target: str, template: str, version: str) -> str:
    """Replace the text between (and including) the markers in `target` with the
    refreshed block. Everything outside the markers is preserved byte-for-byte.
    """
    if BEGIN not in target or END not in target:
        raise ValueError("target has no marker-fenced block; run /factory-init first")
    block = extract_block(template, version)
    b = target.index(BEGIN)
    e = target.index(END) + len(END)
    return target[:b] + block + target[e:]


def merge_settings(target: dict, template: dict) -> dict:
    """Ensure the template's marketplace + plugin wiring is present and current,
    preserving every other repo-owned key and entry. Template values win for the
    keys it owns; repo-added entries in those maps survive.
    """
    for key in ("extraKnownMarketplaces", "enabledPlugins"):
        merged = dict(target.get(key, {}))
        merged.update(template.get(key, {}))
        target[key] = merged
    return target


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init-claude", help="stamp CLAUDE.md (three cases)")
    p.add_argument("--template", required=True)
    p.add_argument("--project-name", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--existing", help="path to an existing CLAUDE.md (omit for the fresh case)")
    p.add_argument("--project-content", help="starter skeleton for the fresh case")

    p = sub.add_parser("update-splice", help="refresh the marker-fenced block")
    p.add_argument("--template", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--version", required=True)

    p = sub.add_parser("merge-settings", help="merge settings.json wiring")
    p.add_argument("--template", required=True)
    p.add_argument("--target", required=True)

    args = ap.parse_args()

    try:
        if args.cmd == "init-claude":
            existing = _read(args.existing) if args.existing else None
            content = _read(args.project_content) if args.project_content else ""
            out = init_claude(_read(args.template), args.project_name,
                              args.version, existing, content)
            sys.stdout.write(out)
        elif args.cmd == "update-splice":
            out = update_splice(_read(args.target), _read(args.template), args.version)
            sys.stdout.write(out)
        elif args.cmd == "merge-settings":
            target = json.loads(_read(args.target))
            template = json.loads(_read(args.template))
            merged = merge_settings(target, template)
            sys.stdout.write(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
    except ValueError as e:
        print(f"factory_stamp: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
