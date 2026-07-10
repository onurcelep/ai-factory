# ai-factory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Publication note:** kept as a historical record. Machine-specific home
> paths are shortened to `~/...`, and the first consumer repo (private)
> appears as `repo-a`.

**Goal:** Build the `onurcelep/ai-factory` public repo — a personal Claude Code plugin marketplace plus repo-stamping templates — and retrofit repo-a and etude onto it.

**Architecture:** One repo is both a plugin marketplace (marketplace `onur`, plugin `factory`: auto-updating skills) and a template source (workflows, settings, marker-fenced CLAUDE.md stamped per repo by the `factory-init` skill, refreshed by `factory-update`). Per-repo `.claude/settings.json` declares the marketplace so remote @claude Actions and cloud sessions install the same plugins as local sessions.

**Tech Stack:** Markdown skill files, JSON manifests, GitHub Actions YAML, a bash validation script. No application code.

**Spec:** `docs/superpowers/specs/2026-07-08-ai-factory-design.md` (approved).

## Global Constraints

- Repo root is `~/code/ai-factory` (git repo exists, branch `main`, spec already committed).
- Marketplace name: `onur`. Plugin name: `factory`. GitHub repo: `onurcelep/ai-factory`, **public**.
- Marker strings, verbatim everywhere:
  - begin: `<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->`
  - end: `<!-- factory:standard:end -->`
- Auth secret for @claude workflows is `CLAUDE_CODE_OAUTH_TOKEN` (already set in both existing repos). Never commit any secret.
- Model pins: interactive @claude → `--model claude-sonnet-5 --max-turns 10`; auto PR review → `--model opus`.
- Init/update must never destroy user content: existing files are diffed and confirmed, never silently overwritten.
- ai-factory commits: plain imperative messages ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- The test harness is `scripts/validate.sh`; each task adds its checks FIRST (red), then adds files (green).
- Prose rule (user preference, mirrors etude): avoid em dashes in template/skill prose where practical.

---

### Task 1: Validation harness + marketplace and plugin manifests

**Files:**
- Create: `scripts/validate.sh`
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/factory/.claude-plugin/plugin.json`
- Create: `README.md`

**Interfaces:**
- Produces: `scripts/validate.sh` (bash, exit 0 = pass; later tasks append checks to it), marketplace `onur`, plugin `factory` at `plugins/factory/` (all later paths hang off this).

- [ ] **Step 1: Write the failing validation script**

Create `scripts/validate.sh`:

```bash
#!/usr/bin/env bash
# Validation suite for ai-factory. Each block is a check; first failure exits 1.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "ok: $1"; }

json_valid() { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; }

# --- Task 1: manifests ---
[ -f .claude-plugin/marketplace.json ] || fail "marketplace.json missing"
json_valid .claude-plugin/marketplace.json || fail "marketplace.json is not valid JSON"
grep -q '"name": "onur"' .claude-plugin/marketplace.json || fail "marketplace name must be 'onur'"
grep -q '"name": "factory"' .claude-plugin/marketplace.json || fail "marketplace must list plugin 'factory'"
[ -f plugins/factory/.claude-plugin/plugin.json ] || fail "plugin.json missing"
json_valid plugins/factory/.claude-plugin/plugin.json || fail "plugin.json is not valid JSON"
ok "manifests"

echo "ALL CHECKS PASSED"
```

Then: `chmod +x scripts/validate.sh`

- [ ] **Step 2: Run it to verify it fails**

Run: `./scripts/validate.sh`
Expected: `FAIL: marketplace.json missing` and exit code 1.

- [ ] **Step 3: Create the manifests and README**

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "onur",
  "owner": { "name": "Onur Celep" },
  "plugins": [
    {
      "name": "factory",
      "source": "./plugins/factory",
      "description": "Personal standard AI-dev setup: init/update stamps plus shared skills (model routing, release flow)."
    }
  ]
}
```

Create `plugins/factory/.claude-plugin/plugin.json`:

```json
{
  "name": "factory",
  "description": "Onur's standard AI-dev setup: /factory-init stamps a repo with @claude workflows, plugin wiring, and a marker-fenced CLAUDE.md; /factory-update refreshes the standard parts. Ships shared model-routing and release-flow skills.",
  "version": "0.1.0",
  "author": { "name": "Onur Celep" }
}
```

Create `README.md`:

```markdown
# ai-factory

Personal Claude Code plugin marketplace + repo templates. One repo, two layers:

- **Plugin `factory`** (auto-updating): shared skills — `factory-init`,
  `factory-update`, `model-routing`, `release-flow`. Fetched fresh at session
  start by local Claude Code, @claude GitHub Actions, and cloud sessions.
- **Templates** (stamped snapshots): `plugins/factory/templates/` — @claude
  workflows, `.claude/settings.json` wiring, marker-fenced `CLAUDE.md`,
  `AGENTS.md`. Stamped into a repo by `/factory-init`, refreshed by
  `/factory-update`.

## Use

In any repo: enable the marketplace once (`/plugin marketplace add
onurcelep/ai-factory`), install `factory@onur`, then run `/factory-init`.

Design: `docs/superpowers/specs/2026-07-08-ai-factory-design.md`.
Validate after changes: `./scripts/validate.sh`.
```

- [ ] **Step 4: Run validation to verify it passes**

Run: `./scripts/validate.sh`
Expected: `ok: manifests` then `ALL CHECKS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add marketplace/plugin manifests, README, validation harness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: model-routing and release-flow skills

**Files:**
- Modify: `scripts/validate.sh` (append checks before the final echo)
- Create: `plugins/factory/skills/model-routing/SKILL.md`
- Create: `plugins/factory/skills/release-flow/SKILL.md`

**Interfaces:**
- Produces: skills invocable as `factory:model-routing` and `factory:release-flow`; the stamped CLAUDE.md standard block (Task 3) references them by these names.

- [ ] **Step 1: Add failing checks to scripts/validate.sh**

Insert before the final `echo "ALL CHECKS PASSED"` line:

```bash
# --- Task 2: shared skills ---
for s in model-routing release-flow; do
  f="plugins/factory/skills/$s/SKILL.md"
  [ -f "$f" ] || fail "$f missing"
  head -1 "$f" | grep -q '^---$' || fail "$f missing frontmatter"
  grep -q '^name: ' "$f" || fail "$f missing name field"
  grep -q '^description: ' "$f" || fail "$f missing description field"
done
ok "shared skills"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/validate.sh`
Expected: `FAIL: plugins/factory/skills/model-routing/SKILL.md missing`, exit 1.

- [ ] **Step 3: Create the two skills**

Create `plugins/factory/skills/model-routing/SKILL.md` (content extracted from repo-a's CLAUDE.md "Model policy" section, generalized):

```markdown
---
name: model-routing
description: Model routing policy for token efficiency. Use when spawning subagents, choosing a model for an agent/workflow, or editing model pins in @claude GitHub workflow files.
---

# Model routing (token efficiency)

Route agent work to the cheapest capable model. Always set the model
explicitly: an omitted model silently inherits an expensive default.

- **Haiku**: implementers executing fully-specified plan tasks (the plan
  contains the complete code; the job is transcription plus running tests).
- **Sonnet**: fix subagents, task reviewers, GitHub routines, and the
  interactive @claude Actions responder (`--model claude-sonnet-5
  --max-turns 10`). Judgment work needs at least mid-tier: turn count beats
  token price. An under-modeled agent that takes 3x the turns costs more
  than a capable one.
- **Opus**: research sweeps, architecture/design work, and the auto PR-review
  workflow (runs once per PR; review depth matters).
- **Most capable model**: session controller and the final whole-branch
  review only.

Escalate one level when a task is BLOCKED or produces repeated review
findings; never escalate by default.

Workflow pins live in `.github/workflows/claude.yml` (Sonnet, turn-capped)
and `.github/workflows/claude-code-review.yml` (Opus). Keep pins and this
policy in sync when either changes.
```

Create `plugins/factory/skills/release-flow/SKILL.md` (standardized from etude's "Local vs @claude" section; repo specifics stay in each repo's CLAUDE.md):

```markdown
---
name: release-flow
description: Standard review-and-release discipline for local work vs the remote @claude CI agent. Use before pushing, merging, deploying, or when acting as the @claude GitHub Actions agent.
---

# Release flow (local vs @claude)

Two independent paths. The CI agent setup does not change how local work is
done.

- **Local (human + CLI)**: commit, run `/code-review` on the diff, then push
  per THIS repo's rules. The repo's `CLAUDE.md` `## Project` section defines
  the specifics (direct-to-main with push=deploy, or feature branches + PR).
  `/code-review` before push is the quality gate either way.
- **@claude (remote CI agent)**: never push to `main`; open a pull request a
  human reviews and merges. The workflow runs with `contents: read` to
  enforce this; treat it as an absolute rule regardless. Keep changes small
  and reviewable.
- The auto PR review (Opus) only runs on PRs. Local direct-to-main commits
  skip it, so `/code-review` before pushing is their gate. To get the bot
  review on local work, push a branch and open a PR instead.
- Hold outward-facing actions (deploy, release, store upload) for explicit
  human approval unless the repo's rules say otherwise.
```

- [ ] **Step 4: Run validation to verify it passes**

Run: `./scripts/validate.sh`
Expected: `ok: shared skills` and `ALL CHECKS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add model-routing and release-flow shared skills

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Templates (workflows, settings, CLAUDE.md, AGENTS.md)

**Files:**
- Modify: `scripts/validate.sh`
- Create: `plugins/factory/templates/claude.yml`
- Create: `plugins/factory/templates/claude-code-review.yml`
- Create: `plugins/factory/templates/settings.json`
- Create: `plugins/factory/templates/CLAUDE.md.tmpl`
- Create: `plugins/factory/templates/AGENTS.md.tmpl`

**Interfaces:**
- Consumes: skill names `model-routing`, `release-flow` (Task 2).
- Produces: five template files under `plugins/factory/templates/`; `factory-init` (Task 4) copies them; `factory-update` (Task 5) re-copies workflows/settings and extracts the CLAUDE.md.tmpl fenced block. Placeholders use `{{PROJECT_NAME}}`, `{{BUILD_COMMAND}}`, `{{TEST_COMMAND}}` (double-brace, filled by factory-init).

- [ ] **Step 1: Add failing checks to scripts/validate.sh**

Insert before the final `echo "ALL CHECKS PASSED"`:

```bash
# --- Task 3: templates ---
T=plugins/factory/templates
for f in claude.yml claude-code-review.yml settings.json CLAUDE.md.tmpl AGENTS.md.tmpl; do
  [ -f "$T/$f" ] || fail "$T/$f missing"
done
json_valid "$T/settings.json" || fail "settings.json template is not valid JSON"
grep -q 'onurcelep/ai-factory' "$T/settings.json" || fail "settings.json must reference onurcelep/ai-factory"
grep -q 'factory@onur' "$T/settings.json" || fail "settings.json must enable factory@onur"
grep -q 'superpowers@claude-plugins-official' "$T/settings.json" || fail "settings.json must enable superpowers"
grep -qF '<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing begin marker"
grep -qF '<!-- factory:standard:end -->' "$T/CLAUDE.md.tmpl" || fail "CLAUDE.md.tmpl missing end marker"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$T/claude.yml" || fail "claude.yml must use CLAUDE_CODE_OAUTH_TOKEN"
grep -q 'claude-sonnet-5 --max-turns 10' "$T/claude.yml" || fail "claude.yml must pin sonnet turn-capped"
grep -q 'model opus' "$T/claude-code-review.yml" || fail "review workflow must pin opus"
ok "templates"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/validate.sh`
Expected: `FAIL: plugins/factory/templates/claude.yml missing`, exit 1.

- [ ] **Step 3: Create the five templates**

Create `plugins/factory/templates/claude.yml` (merge of the two existing repos: etude's structure, repo-a's turn-capped pin):

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
      issues: read
      id-token: write
      actions: read # Required for Claude to read CI results on PRs
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Run Claude Code
        id: claude
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          # Model policy: see the factory:model-routing skill. Sonnet for
          # responder work, turn-capped. Escalate per-issue by writing
          # "use opus" in the issue body if needed.
          claude_args: '--model claude-sonnet-5 --max-turns 10'
          additional_permissions: |
            actions: read
```

Create `plugins/factory/templates/claude-code-review.yml` (etude's version, Opus-pinned per spec):

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]

jobs:
  claude-review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
      issues: read
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Run Claude Code Review
        id: claude-review
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          # Model policy: see the factory:model-routing skill. Opus for the
          # auto PR review; it runs once per PR and depth matters.
          claude_args: '--model opus'
          plugin_marketplaces: 'https://github.com/anthropics/claude-code.git'
          plugins: 'code-review@claude-code-plugins'
          prompt: '/code-review:code-review ${{ github.repository }}/pull/${{ github.event.pull_request.number }}'
```

Create `plugins/factory/templates/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "onur": {
      "source": { "source": "github", "repo": "onurcelep/ai-factory" }
    }
  },
  "enabledPlugins": {
    "factory@onur": true,
    "superpowers@claude-plugins-official": true
  }
}
```

Create `plugins/factory/templates/CLAUDE.md.tmpl`:

```markdown
# CLAUDE.md — {{PROJECT_NAME}}

<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->
Read by Claude Code locally and by the @claude GitHub Action, so both
inherit the same rules. Standard setup is stamped by ai-factory
(`/factory-update` refreshes this block only; everything under `## Project`
belongs to this repo).

## Standard rules

- **Remote @claude (CI agent): never push to `main`. Open a pull request.**
  Keep changes small and reviewable. Full discipline: `factory:release-flow`
  skill.
- **Local work: run `/code-review` on the diff before any push that reaches
  users.** Push/deploy specifics for THIS repo are under `## Project`.
- **Model routing: consult the `factory:model-routing` skill** before
  spawning subagents or editing the model pins in
  `.github/workflows/claude*.yml`.
- Scale tooling to the task: prefer the lightest mechanism that works
  (inline edit < subagent < worktree < workflow).
<!-- factory:standard:end -->

## Project

<!-- Everything below is owned by this repo. /factory-update never touches it. -->

{{PROJECT_CONTENT}}
```

Create `plugins/factory/templates/AGENTS.md.tmpl`:

```markdown
# {{PROJECT_NAME}}

See `CLAUDE.md` for full agent guidance (rules, commands, conventions).

- Build: {{BUILD_COMMAND}}
- Test: {{TEST_COMMAND}}
```

- [ ] **Step 4: Run validation to verify it passes**

Run: `./scripts/validate.sh`
Expected: `ok: templates` and `ALL CHECKS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add stamp templates: workflows, settings, CLAUDE.md, AGENTS.md

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: factory-init skill

**Files:**
- Modify: `scripts/validate.sh`
- Create: `plugins/factory/skills/factory-init/SKILL.md`

**Interfaces:**
- Consumes: `${CLAUDE_PLUGIN_ROOT}/templates/*` (Task 3), placeholder names `{{PROJECT_NAME}}`, `{{BUILD_COMMAND}}`, `{{TEST_COMMAND}}`, `{{PROJECT_CONTENT}}`, marker strings from Global Constraints.
- Produces: skill invocable as `/factory-init`; stamps target repos.

- [ ] **Step 1: Add failing checks to scripts/validate.sh**

Insert before the final `echo "ALL CHECKS PASSED"`:

```bash
# --- Task 4: factory-init skill ---
FI=plugins/factory/skills/factory-init/SKILL.md
[ -f "$FI" ] || fail "$FI missing"
grep -q 'CLAUDE_PLUGIN_ROOT' "$FI" || fail "factory-init must reference CLAUDE_PLUGIN_ROOT templates"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$FI" || fail "factory-init must mention the auth secret"
grep -qF 'factory:standard:begin' "$FI" || fail "factory-init must document the markers"
ok "factory-init skill"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/validate.sh`
Expected: `FAIL: plugins/factory/skills/factory-init/SKILL.md missing`, exit 1.

- [ ] **Step 3: Create the skill**

Create `plugins/factory/skills/factory-init/SKILL.md`:

```markdown
---
name: factory-init
description: Stamp the current repository with the standard AI-dev setup - @claude workflows, .claude/settings.json plugin wiring, marker-fenced CLAUDE.md, AGENTS.md. Use when initializing a new repo or onboarding an existing repo onto the ai-factory standard.
---

# factory-init

Stamp this repository with the ai-factory standard. Templates live in
`${CLAUDE_PLUGIN_ROOT}/templates/`. Follow the steps in order; never
overwrite existing content without showing a diff and getting confirmation.

## 1. Preflight (abort with a clear message if any fails)

- `git rev-parse --is-inside-work-tree` succeeds; otherwise say "not a git
  repo, run git init first" and stop.
- `gh auth status` succeeds (needed for the manual-steps checklist; if it
  fails, continue stamping but flag it).
- Note the repo slug from `gh repo view --json nameWithOwner -q .nameWithOwner`
  (no remote is fine; the App/secret steps just move to the checklist).

## 2. Stamp the fixed files

Copy each template to its target. If the target exists and differs, show a
unified diff and ask the user per file (keep existing / take template).
If identical, report "already current" and skip.

| Template | Target |
|---|---|
| `templates/claude.yml` | `.github/workflows/claude.yml` |
| `templates/claude-code-review.yml` | `.github/workflows/claude-code-review.yml` |
| `templates/settings.json` | `.claude/settings.json` |

For `.claude/settings.json`, if the target exists, MERGE instead of replace:
add the `onur` marketplace to `extraKnownMarketplaces` and the two entries to
`enabledPlugins`, preserving everything else in the file.

## 3. Stamp AGENTS.md

Render `templates/AGENTS.md.tmpl`: fill `{{PROJECT_NAME}}` with the repo
directory name, and `{{BUILD_COMMAND}}` / `{{TEST_COMMAND}}` by inspecting
the repo (Cargo.toml -> cargo build / cargo test; package.json -> its
scripts; a plain static site -> "none (static site)" / "manual browser
check"). If unsure, ask the user. If AGENTS.md exists, diff-and-confirm.

## 4. Stamp CLAUDE.md (three cases)

Markers, verbatim:
begin: `<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->`
end: `<!-- factory:standard:end -->`

- **No CLAUDE.md:** render `templates/CLAUDE.md.tmpl`. Fill
  `{{PROJECT_NAME}}`; replace `{{PROJECT_CONTENT}}` with a starter skeleton:
  a `## Commands` heading (build/test/lint found in step 3) and a
  `## Hard rules` heading with a `<!-- add project rules here -->` comment.
- **CLAUDE.md exists, no markers:** render the template, then move the ENTIRE
  existing file content under `## Project` (replacing `{{PROJECT_CONTENT}}`).
  Do not delete or rewrite any of it; if the old content duplicates a
  standard rule, point the duplication out to the user and let them decide.
- **Markers already present:** say "already initialized; run /factory-update
  to refresh" and touch nothing.

## 5. Manual-steps checklist (print at the end)

1. Install the Claude GitHub App on this repo: https://github.com/apps/claude
2. Set the auth secret: `gh secret set CLAUDE_CODE_OAUTH_TOKEN`
   (generate via `claude setup-token` if needed).
3. Review the stamped files, then commit them per this repo's rules (the
   skill does not commit for you).

## 6. Report

List every file written/skipped/merged and the checklist above. Idempotent:
re-running on a stamped repo must produce only "already current" and the
"already initialized" message.
```

- [ ] **Step 4: Run validation to verify it passes**

Run: `./scripts/validate.sh`
Expected: `ok: factory-init skill` and `ALL CHECKS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add factory-init skill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: factory-update skill

**Files:**
- Modify: `scripts/validate.sh`
- Create: `plugins/factory/skills/factory-update/SKILL.md`

**Interfaces:**
- Consumes: templates (Task 3), marker strings, factory-init's file map (Task 4).
- Produces: skill invocable as `/factory-update`.

- [ ] **Step 1: Add failing checks to scripts/validate.sh**

Insert before the final `echo "ALL CHECKS PASSED"`:

```bash
# --- Task 5: factory-update skill ---
FU=plugins/factory/skills/factory-update/SKILL.md
[ -f "$FU" ] || fail "$FU missing"
grep -qF 'factory:standard:begin' "$FU" || fail "factory-update must document the markers"
grep -q 'never' "$FU" || fail "factory-update must state it never touches project content"
ok "factory-update skill"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/validate.sh`
Expected: `FAIL: plugins/factory/skills/factory-update/SKILL.md missing`, exit 1.

- [ ] **Step 3: Create the skill**

Create `plugins/factory/skills/factory-update/SKILL.md`:

```markdown
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

## 2. Refresh workflows and settings

Same diff-and-confirm copy as factory-init, same targets:
`.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`.
For `.claude/settings.json`, merge (preserve any repo-added keys); only
ensure the `onur` marketplace and the `factory@onur` +
`superpowers@claude-plugins-official` plugin entries are present and current.

## 3. Refresh the CLAUDE.md standard block

Extract the text between (and including) the two markers from
`templates/CLAUDE.md.tmpl`, resolve `{{PROJECT_NAME}}` is NOT inside the
block so no placeholders apply, and replace the text between (and including)
the markers in the repo's CLAUDE.md with it. Show the diff before writing.
NEVER modify anything outside the markers: the `## Project` section and
everything else in the file belong to the repo.

## 4. Report

List changed/current files. If nothing changed, say so explicitly.
```

- [ ] **Step 4: Run validation to verify it passes**

Run: `./scripts/validate.sh`
Expected: `ok: factory-update skill` and `ALL CHECKS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add factory-update skill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Publish to GitHub and register locally

**Files:**
- Modify: `~/.claude/settings.json` (user-level, outside the repo)

**Interfaces:**
- Consumes: complete repo from Tasks 1-5.
- Produces: public `github.com/onurcelep/ai-factory`; marketplace `onur` + plugin `factory@onur` available in every local session.

- [ ] **Step 1: Final validation and publish**

```bash
./scripts/validate.sh   # expect ALL CHECKS PASSED
gh repo create onurcelep/ai-factory --public --source ~/code/ai-factory --push
```

Expected: repo created, `main` pushed.

- [ ] **Step 2: Register the marketplace and plugin locally**

Edit `~/.claude/settings.json`: add to the EXISTING
`extraKnownMarketplaces` object (it already has `context-mode`):

```json
"onur": { "source": { "source": "github", "repo": "onurcelep/ai-factory" } }
```

and to the EXISTING `enabledPlugins` object:

```json
"factory@onur": true
```

Preserve every other key in the file.

- [ ] **Step 3: Verify the plugin loads**

Run: `claude --print "/factory-init is available? List skills whose name starts with factory. Reply with just the names."` from any directory, OR start a new interactive session and check `/factory-init` appears in the skills list.
Expected: `factory-init` and `factory-update` are listed. If the marketplace fails to resolve, run `/plugin marketplace add onurcelep/ai-factory` in an interactive session and re-check.

- [ ] **Step 4: Smoke-test the stamp on a scratch repo**

```bash
mkdir -p "$SCRATCHPAD"/factory-smoke   # any throwaway dir outside real repos
cd "$SCRATCHPAD"/factory-smoke
git init -b main
```

Then execute the factory-init SKILL.md procedure against this scratch repo
(follow its steps literally, as the skill would run). Verify afterwards:

```bash
ls .github/workflows/claude.yml .github/workflows/claude-code-review.yml .claude/settings.json AGENTS.md CLAUDE.md
grep -c 'factory:standard' CLAUDE.md   # expect 2 (begin + end markers)
```

Re-run the procedure a second time; expected: only "already current" /
"already initialized" outcomes, zero file changes (`git status` clean if the
first run's output was committed, or identical diff otherwise).

- [ ] **Step 5: Commit any repo fixes found during the smoke test**

If the smoke test exposed template or skill-text bugs, fix them in ai-factory,
re-run `./scripts/validate.sh`, commit, and push:

```bash
git add -A && git commit -m "Fix issues found in stamp smoke test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" && git push
```

---

### Task 7: Retrofit repo-a

**Files:**
- Create: `~/code/repo-a/.claude/settings.json`
- Modify: `~/code/repo-a/CLAUDE.md`
- Modify: `~/code/repo-a/.github/workflows/claude.yml`
- Modify: `~/code/repo-a/.github/workflows/claude-code-review.yml`
- Create: `~/code/repo-a/AGENTS.md`

**Interfaces:**
- Consumes: published plugin (Task 6); repo rules: push only `claude/`-prefixed branches, open a PR, never push main.

- [ ] **Step 1: Branch**

```bash
cd ~/code/repo-a
git checkout -b claude/factory-init
```

- [ ] **Step 2: Run the factory-init procedure**

Execute the factory-init SKILL.md steps against this repo. Expected outcomes,
per file:

- `.claude/settings.json`: created from template (no existing file).
- Workflows: both exist and differ from templates (review workflow currently
  pins `claude-sonnet-5`; template pins `opus`). Take the template for both;
  this standardizes the review model per the approved spec.
- `AGENTS.md`: created; `{{PROJECT_NAME}}` = `repo-a`,
  `{{BUILD_COMMAND}}` = `cargo build`, `{{TEST_COMMAND}}` = `cargo test`.
- `CLAUDE.md`: exists without markers. Standard block goes on top; existing
  content moves under `## Project`.

- [ ] **Step 3: Deduplicate the project section of CLAUDE.md**

In the moved `## Project` content, replace the entire
`## Model policy (token efficiency)` section with a one-line pointer (the
policy now lives in the plugin and auto-updates):

```markdown
## Model policy

See the `factory:model-routing` skill (standard, auto-updating). Repo
addition: implementers for fully-specified plan tasks here are Haiku.
```

Keep `## Commands` and `## Hard rules` verbatim: they are project-specific.
The "Push only claude/-prefixed branches..." hard rule stays; it is this
repo's release-flow specifics, exactly where release-flow says they belong.

- [ ] **Step 4: Verify and open the PR**

```bash
cargo test --quiet 2>&1 | tail -3   # config-only change; confirm nothing broke
git add -A
git commit -m "[task retrofit] Adopt ai-factory standard setup

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin claude/factory-init
gh pr create --title "[retrofit] Adopt ai-factory standard setup" --body "Stamps the ai-factory standard: .claude/settings.json plugin wiring, marker-fenced CLAUDE.md (model policy moved to the factory:model-routing skill), standardized @claude workflows (review now Opus-pinned per spec), AGENTS.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 5: Verify remote behavior on the PR**

Watch the PR checks: the Claude Code Review workflow must run and post a
review. Then comment `@claude reply with the first bullet of the
factory:release-flow skill to confirm plugin loading` on the PR and confirm
the response quotes the skill (proves the Action installed the marketplace
plugins from `.claude/settings.json`).
Expected: both succeed. If plugin loading fails in CI, check the Action run
log for marketplace resolution errors before changing anything.

STOP if the review workflow fails to start (App/secret problem, not a
template problem): surface to the user.

- [ ] **Step 6: Merge gate**

The user reviews and merges the PR (repo rule: only a human merges). Do not
merge it yourself.

---

### Task 8: Retrofit etude

**Files:**
- Create: `~/code/etude/.claude/settings.json` (or merge if `.claude/` has one)
- Modify: `~/code/etude/CLAUDE.md`
- Modify: `~/code/etude/.github/workflows/claude.yml`
- Create: `~/code/etude/AGENTS.md`
- NOT touched: `claude-code-review.yml` (already matches template semantics: Opus + code-review plugin), `claude-browser-verify.yml`, `.github/mcp/ci.mcp.json`, `deploy-pages.yml`, `etude-looper-ext-release.yml` (project-specific; spec keeps them out of the standard).

**Interfaces:**
- Consumes: published plugin (Task 6); repo rules: local-first, `[local]` commit prefix, never `git push` until explicitly told to deploy (push = production deploy).

- [ ] **Step 1: Run the factory-init procedure (no branch: this repo works direct-on-main, local-first)**

```bash
cd ~/code/etude
git status   # must be clean before starting; stop if not
```

Execute the factory-init SKILL.md steps. Expected outcomes:

- `.claude/settings.json`: created (merge if one exists under `.claude/`).
- `claude.yml`: differs only by `--max-turns 10` and the policy comment; take
  the template.
- `claude-code-review.yml`: diff against template; it already pins Opus and
  the code-review plugin. Take whichever is identical-in-effect; if the diff
  is only comments, keep the existing file.
- `AGENTS.md`: created; `{{PROJECT_NAME}}` = `Etude`, `{{BUILD_COMMAND}}` =
  `none (static site, no build step)`, `{{TEST_COMMAND}}` =
  `python3 -m http.server + real-browser check`.
- `CLAUDE.md`: exists without markers; standard block on top, everything
  else under `## Project`.

- [ ] **Step 2: Deduplicate the project section of CLAUDE.md**

Within `## Project`, edit ONLY these spots (all other sections stay verbatim,
including Golden rules, Looper internals, extension docs):

1. In `## For the @claude GitHub Action`: delete the first bullet
   ("Never push to main. Open a pull request...") — now covered by the
   standard block and `factory:release-flow`. Keep the etude-specific
   bullets (no build step, label-gated browser verify).
2. In `## Local vs @claude: who pushes where`: keep the section (it defines
   THIS repo's specifics: direct-to-main push=deploy) but delete the last
   paragraph ("The auto Opus PR-review only runs on PRs...") — now in
   `factory:release-flow`.
3. In `## When to use specs, subagents, or workflows`, replace the line
   "Do not adopt GSD / Superpowers / Spec Kit here." with:
   "The superpowers plugin is enabled (standard setup); use its process
   skills only when starting a net-new tool. Do not adopt spec-kit or heavy
   orchestration for edits to an existing tool."
   (The old line now contradicts the stamped settings; this keeps its
   intent — scale tooling down — without the contradiction.)

- [ ] **Step 3: Review and local-commit (do NOT push)**

```bash
git add -A
git commit -m "[local] Adopt ai-factory standard setup"
```

Run `/code-review` on the diff per repo rules. Fix findings, amend.
**Do not `git push`: push deploys to production. Hold for the user's
explicit deploy approval** (repo golden rule).

- [ ] **Step 4: After user approves and pushes: verify remote parity**

Once the user deploys, open a test issue: `@claude reply with the repo's
standard rules from CLAUDE.md` and confirm the reply quotes the fenced block
(proves remote CLAUDE.md + plugin wiring). Close the issue after.

---

### Task 9: Record the standard in memory and wrap up

**Files:**
- Create: `~/.claude/projects/<workspace>/memory/ai-factory-standard.md`
- Modify: `~/.claude/projects/<workspace>/memory/MEMORY.md`

**Interfaces:**
- Consumes: everything shipped in Tasks 1-8.

- [ ] **Step 1: Write the memory file**

Create `~/.claude/projects/<workspace>/memory/ai-factory-standard.md`:

```markdown
---
name: ai-factory-standard
description: Standard reusable AI-dev setup lives in public repo onurcelep/ai-factory (plugin marketplace "onur", plugin "factory"); new repos get /factory-init, updates via /factory-update.
metadata:
  type: project
---

The standard AI-dev setup (decided 2026-07-08) is the `ai-factory` repo at
~/code/ai-factory (public, github.com/onurcelep/ai-factory): a personal
plugin marketplace (`onur`) with plugin `factory` (skills: factory-init,
factory-update, model-routing, release-flow) plus stamp templates
(@claude workflows Sonnet/Opus-pinned, .claude/settings.json wiring,
marker-fenced CLAUDE.md, AGENTS.md). New repos: run `/factory-init`.
Template changes: bump templates in ai-factory, run `/factory-update` in
consuming repos. Skills auto-propagate (fetched at session start, local and
remote); stamped files are snapshots. Superpowers stays the process layer;
spec-kit was evaluated and rejected (team-oriented). Related:
[[model-routing-preference]], [[repo-a-project]].
```

- [ ] **Step 2: Add the MEMORY.md index line**

Append to `MEMORY.md`:

```markdown
- [ai-factory standard](ai-factory-standard.md) — reusable AI-dev setup; /factory-init new repos, /factory-update to refresh.
```

- [ ] **Step 3: Final report**

Summarize to the user: repo URL, how to init a new repo, how updates
propagate, PR link (repo-a) and pending deploy approval (etude).

---

## Self-review notes (done at write time)

- **Spec coverage:** repo+manifests (T1), shared skills (T2), templates (T3), init (T4), update (T5), publish public + local registration + idempotent smoke test (T6), retrofit repo-a first with @claude verification (T7), retrofit etude keeping browser-verify as project extra (T8). Spec's "out of scope" items are not planned anywhere. Gap check: none found.
- **Secret name:** spec was corrected to `CLAUDE_CODE_OAUTH_TOKEN` (matches both existing repos' workflows).
- **Consistency:** marker strings, plugin/marketplace names, placeholder names, and skill names (`factory:model-routing`, `factory:release-flow`) are identical across T2-T8.
- **Known judgment call:** repo-a's review workflow moves Sonnet→Opus (spec standardizes on Opus); flagged in the T7 PR body so the user sees it at merge time.
