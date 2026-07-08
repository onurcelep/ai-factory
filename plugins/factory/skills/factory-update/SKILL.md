---
name: factory-update
description: Refresh the ai-factory standard parts of an already-initialized repo - the @claude workflows, plugin wiring in .claude/settings.json, and the marker-fenced standard block in CLAUDE.md. Use after the ai-factory templates change. Never touches project-specific content.
---

# factory-update

Refresh only the standard, stamped parts. Templates live in
`${CLAUDE_PLUGIN_ROOT}/templates/`.

## 1. Preflight

CLAUDE.md must contain BOTH markers:
begin: `<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->`
end: `<!-- factory:standard:end -->`
If either is missing, stop and say "not initialized; run /factory-init".

This tool will never modify content outside the marker boundaries.

## 2. Refresh workflows and settings

Same diff-and-confirm copy as factory-init, same targets:
`.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`.
For `.claude/settings.json`, merge (preserve any repo-added keys); only
ensure the `onur` marketplace and the `factory@onur` +
`superpowers@claude-plugins-official` plugin entries are present and current.

## 3. Refresh the CLAUDE.md standard block

Extract the text between (and including) the two markers from
`templates/CLAUDE.md.tmpl` (the {{PROJECT_NAME}} placeholder is not inside
the block, so no placeholder resolution is needed) and replace the text
between (and including) the markers in the repo's CLAUDE.md with it. Show
the diff before writing.
NEVER modify anything outside the markers: the `## Project` section and
everything else in the file belong to the repo.

## 4. Report

List changed/current files. If nothing changed, say so explicitly.
