# ai-factory — reusable AI-development setup, design

**Date:** 2026-07-08
**Status:** Approved (design); implementation plan pending
**Owner:** Onur Celep

## Problem

Every repo that works with Claude agents (locally and via remote @claude on
GitHub) needs the same setup, currently redone by hand per repo: the
`claude.yml` / `claude-code-review.yml` workflows, secrets, and overlapping
CLAUDE.md prose (model-routing policy, local-vs-@claude push rules,
review-before-deploy flow). The existing agent-enabled repos each carry
hand-copied, already-drifting variants. New projects restart from zero.

## Decision drivers

1. **One command** must stamp config + boilerplate + process into any repo.
2. **Mixed update model:** shared skills/commands/process auto-propagate;
   per-repo files (workflows, CLAUDE.md) are stamped snapshots refreshed on
   demand.
3. **Project-specific CLAUDE.md content stays per-repo**, layered over the
   standard, and must survive re-stamping.
4. **Remote parity is the hard constraint:** @claude GitHub Actions and
   Claude Code cloud sessions never see `~/.claude`. They load only the
   repo's `CLAUDE.md` and `.claude/` plus whatever plugins reach them —
   but not the same way. Live verification on 2026-07-08 showed the
   @claude GitHub Action strips the repo's `.claude/settings.json` before
   the session starts, so for Actions the plugins are self-loaded by the
   workflow files themselves, via newline-separated `plugin_marketplaces`/
   `plugins` inputs. `.claude/settings.json` still serves its purpose for
   Claude Code cloud sessions and local checkouts. Everything shared must
   therefore be reachable *from the repo*, through whichever of the two
   mechanisms applies to the environment.
5. Retrofit the existing agent-enabled repos as first consumers.

## Alternatives considered (2026-07 research, verified against live sources)

- **spec-kit (github/spec-kit):** actively maintained but team/enterprise
  oriented (workflow DSL, presets, bundles); solo-dev fit poor — its own
  discussions report "work about work" on small projects. Rejected as a
  framework; the spec→plan→tasks *idea* is already covered by superpowers.
- **superpowers (obra/superpowers):** kept as the process layer
  (brainstorm → plan → TDD → review). Already installed locally; must be
  declared per-repo to reach remote agents.
- **Agent OS:** lighter standards-injection tool but development stalled
  (~2 months quiet after v3). Not adopted.
- **BMAD-method, claude-flow/ruflo:** team/swarm oriented; ruflo failed an
  independent audit (most claimed tools non-functional). Rejected.
- **AGENTS.md:** Linux Foundation standard read by 28+ tools; adopted as a
  thin stamped file pointing at CLAUDE.md.
- **Plain template repo (no plugin):** rejected — no propagation, preserves
  today's drift. **spec-kit adoption:** rejected as above.

## Architecture

One **public** GitHub repo, `ai-factory`, acting as both a personal
**plugin marketplace**
(auto-updating layer) and a **template source** (stamped layer). Public
visibility avoids per-repo PAT plumbing for remote marketplace fetches; the
repo contains only config and skills, never secrets.

```
ai-factory/
├── .claude-plugin/marketplace.json        # marketplace "onur", one plugin entry
├── docs/superpowers/specs/                # this spec, future specs/plans
└── plugins/factory/
    ├── .claude-plugin/plugin.json
    ├── skills/
    │   ├── factory-init/SKILL.md          # /factory-init — stamp a repo
    │   ├── factory-update/SKILL.md        # /factory-update — refresh standard sections
    │   ├── model-routing/SKILL.md         # Haiku/Sonnet/Opus routing policy
    │   │                                  #   (generalized from existing CLAUDE.md prose)
    │   └── release-flow/SKILL.md          # review-before-deploy; claude/ branch + PR
    │                                      #   rules (generalized from existing CLAUDE.md prose)
    ├── agents/                            # shared subagents; starts empty (YAGNI)
    └── templates/
        ├── claude.yml                     # @claude interactive workflow (Sonnet-pinned)
        ├── claude-code-review.yml         # auto PR-review workflow (Opus-pinned)
        ├── settings.json                  # repo .claude/settings.json template
        ├── CLAUDE.md.tmpl                 # marker-fenced skeleton (see below)
        └── AGENTS.md.tmpl                 # thin cross-tool pointer to CLAUDE.md
```

**Update semantics:** `skills/` and `agents/` propagate automatically —
plugins are fetched at session start locally and remotely. `templates/`
output is a per-repo snapshot until `/factory-update` re-stamps it.

### Per-repo wiring

`/factory-init` commits a `.claude/settings.json` to the target repo:

```json
{
  "extraKnownMarketplaces": {
    "onur": { "source": { "source": "github", "repo": "onurcelep/ai-factory" } }
  },
  "enabledPlugins": {
    "factory@onur": true,
    "superpowers@claude-plugins-official": true
  }
}
```

This file is what makes Claude Code cloud sessions and local checkouts
behave alike: both install `factory@onur` and
`superpowers@claude-plugins-official` fresh at session start by reading
`.claude/settings.json`. @claude GitHub Action runs are different: the
Action strips `.claude/settings.json` before the session starts, so the
workflow files (`templates/claude.yml`, `templates/claude-code-review.yml`)
self-load `factory@onur` directly via their `plugin_marketplaces`/`plugins`
inputs instead.

Two things worth noting:

- superpowers is intentionally NOT loaded into @claude Action runs. The
  turn-capped responder doesn't need the process-skills layer (brainstorm →
  plan → TDD → review), and loading it would just cost context for no
  benefit. It stays local + cloud only.
- Observed locally: listing a plugin under `enabledPlugins` in
  `settings.json` alone did not surface it in a running session. A
  one-time `claude plugin install factory@onur` was needed before the
  plugin actually loaded.

### CLAUDE.md layering

Stamped CLAUDE.md files use fenced markers:

```markdown
<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->
…standard block: local-vs-@claude push rules, review-before-deploy summary,
one-line pointers to the model-routing and release-flow skills…
<!-- factory:standard:end -->

## Project
…project-specific content, owned entirely by the repo…
```

`/factory-update` rewrites only the fenced block. Long standard prose lives
in plugin skills (auto-updating), keeping the stamped block short and
re-stamps rare. Project knowledge (a tool's engine gotchas, a codec's
DSP/loudness rules) is structurally protected below the fence.

### /factory-init behavior

Run inside any repo:

1. Copies `claude.yml`, `claude-code-review.yml`, `.claude/settings.json`,
   `AGENTS.md`.
2. Generates CLAUDE.md from the template. If a CLAUDE.md exists, wraps its
   current content into the `## Project` section — never overwrites.
3. Walks the user through the two manual steps it cannot perform: Claude
   GitHub App install and `gh secret set CLAUDE_CODE_OAUTH_TOKEN` (the
   auth secret the @claude workflows use).
4. Idempotent: re-running diffs against current files and skips what is
   already up to date; conflicts are shown, never silently overwritten.

`/factory-update` is the same machinery restricted to standard sections
(workflows, settings.json, the fenced CLAUDE.md block).

### Error handling

- Init/update never destroy user content: existing files are merged
  (CLAUDE.md) or diffed-and-confirmed (workflows, settings).
- Missing prerequisites (not a git repo, no `gh` auth) abort with a clear
  message before any file is written.
- A repo whose CLAUDE.md lacks markers is treated as un-initialized for the
  standard block: the block is prepended, existing content moved under
  `## Project`.

## Rollout / testing

1. Build the ai-factory repo, publish to GitHub (public), add the `onur`
   marketplace locally.
2. Retrofit the simplest existing repo first (ideally one with no `.claude/`
   dir yet — the cleanest case): run `/factory-init`, fold its CLAUDE.md
   model-policy prose into the `model-routing` skill, verify a test PR gets
   the auto review and an `@claude` mention responds using the standard rules.
3. Retrofit a more complex existing repo: fold duplicated workflow/CLAUDE.md
   sections into the plugin; keep any repo-specific CI (e.g. a browser-verify
   workflow and its MCP config) as project-specific extras — not templated
   until a second repo needs the same thing (YAGNI).
4. These first retrofits are the acceptance test for the design; new projects
   thereafter are `/factory-init` + fill in `## Project`.

## Out of scope

- Moving personal user-level agents/skills into the plugin — they are
  machine-local by nature; revisit only if a repo needs them remotely.
- Templating browser-verify CI, devcontainers, and MCP configs — add when a
  second repo needs each.
- Any spec-kit style lifecycle tooling — superpowers covers process.
