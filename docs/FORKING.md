# Forking ai-factory

Everything you change once to make this *your* standard: identity,
process layer, billing, models. For what the defaults are and why, see
[DECISIONS.md](DECISIONS.md); for changing skills and templates after the
fork, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Rebrand

Everything functional is owner-agnostic except two strings — the GitHub
repo slug and the marketplace name — and one script rewrites both:

```bash
gh repo fork onurcelep/ai-factory --clone    # or "Use this template" on GitHub
cd ai-factory
./scripts/rebrand.sh <your-github-user>/ai-factory    # optional 2nd arg: marketplace name
```

The script rewrites the manifests, templates, and docs, then re-runs the
validation suite (which checks cross-file consistency, not owner literals,
so it passes for any fork). Review the diff, optionally put your own name
in the two manifests' owner/author fields, push — then continue from the
[Quick start](../README.md#quick-start) with your own slug. Keep the fork
public and secret-free; from there the skills and templates are yours to
edit.

## Swapping the process layer

The process layer is a default, not a requirement. To drop it, delete the
`"superpowers@claude-plugins-official": true` line from
`plugins/factory/templates/settings.json` — and the comma that ended the
line above it, now the last entry (JSON forbids a trailing comma); to swap
it, replace that line in place with your own plugin's
`"<plugin>@<marketplace>": true` (and add its marketplace under
`extraKnownMarketplaces`). The validator only requires
`factory@<marketplace>`, so it stays green either way.

## Billing: subscription or API key

The shipped default is **subscription billing**: workflow runs
authenticate with an OAuth token minted from the operator's Claude
subscription (`claude setup-token` → `gh secret set
CLAUDE_CODE_OAUTH_TOKEN`), so agent runs draw from the plan you already
pay for. Every template, diagnostic string, and playbook is written
around that secret.

A fork can run on **API billing** (metered per token) instead — the
underlying `claude-code-action` accepts either credential. What to
change, once, in your fork's templates:

1. In `plugins/factory/templates/claude*.yml` (all three workflows),
   replace the credential line:

   ```yaml
   # subscription (shipped default)
   claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
   # API billing
   anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
   ```

2. Also update the **silent-failure diagnostic messages** in those
   templates — they tell the operator to suspect and rotate
   `CLAUDE_CODE_OAUTH_TOKEN` by name, and a playbook that names the wrong
   secret is worse than none. Search each template for the string and
   reword to your secret.
3. Set the secret per repo (`gh secret set ANTHROPIC_API_KEY`) or once at
   org level, bump the plugin version, and let propagation (or
   `/factory-update`) carry it to your fleet.

The validation suite accepts either secret name, so a converted fork
stays green without patching the suite. Mixed fleets also work — the
credential is chosen per repo by whatever the stamped workflow names. The
trade-off is purely commercial: subscription runs are capped by your
plan's limits; API runs are uncapped and metered (watch them with
`scripts/cost-report.sh`).

## Choosing your models

Model choice is a fork decision, not a config option: every model is
pinned explicitly *where it runs*, so rerouting is a one-time edit in
your fork rather than indirection the workflows resolve at runtime. The
complete list of pin locations:

| What | Where the pin lives | Shipped default |
|---|---|---|
| `@claude` issue/PR responder | `plugins/factory/templates/claude.yml` → `claude_args: '--model … --max-turns …'` | Sonnet, turn-capped |
| Automatic PR review | `plugins/factory/templates/claude-code-review.yml` → `claude_args` | Opus (once per PR, depth pays) |
| Scheduled smoke probe | `plugins/factory/templates/claude-smoke-test.yml` → `claude_args` | Haiku (a liveness check needs no depth) |
| Routed subagents | `plugins/factory/agents/factory-{implementer,reviewer,researcher}.md` → `model:` frontmatter | haiku / sonnet / opus |
| The routing *policy* (when to use which) | `plugins/factory/skills/model-routing/SKILL.md` | prose — update it to match your pins |

The validation suite enforces the invariants these pins exist for — every
workflow names a model explicitly and probe/responder runs carry a turn
cap — but never the specific model names, so your choices validate green.
Keep the *shape* even if you change every name: cheapest for the probe
and fully-specified implementation, strongest where judgment concentrates
(the PR review), and don't under-model judgment work — a wrong design
costs more than any model tier saves. Template edits require a plugin
version bump (enforced), and propagation carries them to your fleet;
after any model change, run the
[model-transition checklist](OPERATIONS.md#model-transitions) — renamed
cheaper tiers can leave judgment work under-modeled without anything
failing loudly.

Per-repo exceptions need no factory machinery: edit that repo's stamped
workflow directly — `/factory-update` preserves deliberate
customizations.
