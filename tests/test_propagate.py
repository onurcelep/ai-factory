"""Unit tests for the deterministic propagation planner.

Everything here runs offline: the planner is a pure function of file contents,
so the changed / unchanged / fallback decision is testable without cloning,
pushing, or talking to GitHub.
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
propagate = __import__("propagate")

WF = ".github/workflows/claude-code-review.yml"
BEGIN = "<!-- factory:standard:begin (managed by /factory-update — do not hand-edit) -->"
END = "<!-- factory:standard:end -->"

CLAUDE_TEMPLATE = (
    "# CLAUDE.md — {{PROJECT_NAME}}\n\n"
    f"{BEGIN}\n<!-- factory:version {{{{FACTORY_VERSION}}}} -->\nstandard rules\n{END}\n\n"
    "## Project\n\n{{PROJECT_CONTENT}}\n"
)
SETTINGS_TEMPLATE = json.dumps(
    {"extraKnownMarketplaces": {"onur": {"source": {"source": "github",
                                                    "repo": "onurcelep/ai-factory"}}},
     "enabledPlugins": {"factory@onur": True}},
    indent=2) + "\n"


def stamped_claude_md(version):
    return (f"# CLAUDE.md — consumer\n\n{BEGIN}\n<!-- factory:version {version} -->\n"
            f"standard rules\n{END}\n\n## Project\n\nrepo-owned.\n")


def templates(**overrides):
    base = {
        WF: "workflow v2\n",
        propagate.SETTINGS: SETTINGS_TEMPLATE,
        propagate.CLAUDE_MD: CLAUDE_TEMPLATE,
        propagate.MEMORY_INDEX: "# memory index\n",
        propagate.MEMORY_SEED: "# seeded fact\n",
    }
    base.update(overrides)
    return base


def current_repo_files(version="0.7.0"):
    """A consumer already stamped at `version` with pristine template copies."""
    return {
        WF: "workflow v2\n",
        propagate.SETTINGS: SETTINGS_TEMPLATE,
        propagate.CLAUDE_MD: stamped_claude_md(version),
        propagate.MEMORY_INDEX: "# memory index\n",
        propagate.MEMORY_SEED: "# seeded fact\n",
    }


class TestVersionComparison(unittest.TestCase):
    def test_double_digit_patch_beats_single_digit(self):
        self.assertGreater(propagate.version_key("0.6.10"), propagate.version_key("0.6.9"))

    def test_staleness_verdicts(self):
        self.assertEqual(propagate.staleness("0.7.0", "0.7.0"), propagate.CURRENT)
        self.assertEqual(propagate.staleness("0.8.0", "0.7.0"), propagate.AHEAD)
        self.assertEqual(propagate.staleness("0.6.0", "0.7.0"), "")
        self.assertEqual(propagate.staleness(None, "0.7.0"), "")

    def test_stamped_version_read_from_the_marker_block(self):
        self.assertEqual(propagate.stamped_version(stamped_claude_md("0.6.3")), "0.6.3")
        self.assertIsNone(propagate.stamped_version("# CLAUDE.md\n\nno stamp here\n"))


class TestOutcomeClassification(unittest.TestCase):
    def plan_for(self, repo_files, baselines=None, version="0.7.0", tmpl=None):
        return propagate.plan_stamp(repo_files, tmpl or templates(),
                                    baselines or {}, version)

    def test_changed_when_the_stamp_produces_a_diff(self):
        repo = current_repo_files(version="0.6.0")
        repo[WF] = "workflow v1\n"
        plan = self.plan_for(repo, baselines={WF: "workflow v1\n"})
        self.assertEqual(propagate.classify_outcome(plan), propagate.CHANGED)
        self.assertEqual(plan.files, sorted([WF, propagate.CLAUDE_MD]))
        self.assertIn("factory:version 0.7.0", plan.writes[propagate.CLAUDE_MD])
        self.assertIn("repo-owned.", plan.writes[propagate.CLAUDE_MD])

    def test_unchanged_when_everything_already_matches(self):
        plan = self.plan_for(current_repo_files())
        self.assertEqual(plan.files, [])
        self.assertEqual(propagate.classify_outcome(plan), propagate.UNCHANGED)

    def test_fallback_when_a_workflow_was_modified_locally(self):
        repo = current_repo_files(version="0.6.0")
        repo[WF] = "workflow v1 plus a repo-owned extra flag\n"
        plan = self.plan_for(repo, baselines={WF: "workflow v1\n"})
        self.assertEqual(propagate.classify_outcome(plan), propagate.FALLBACK)
        self.assertIn(WF, propagate.fallback_reason(plan))

    def test_fallback_when_the_baseline_template_is_unresolvable(self):
        """No baseline means we cannot tell an old template from a local edit,
        so the file is never clobbered."""
        repo = current_repo_files(version="0.6.0")
        repo[WF] = "workflow v1\n"
        plan = self.plan_for(repo, baselines={})
        self.assertEqual(propagate.classify_outcome(plan), propagate.FALLBACK)

    def test_fallback_when_claude_md_has_no_marker_block(self):
        repo = current_repo_files()
        repo[propagate.CLAUDE_MD] = "# CLAUDE.md\n\nnever initialized\n"
        plan = self.plan_for(repo)
        self.assertEqual(propagate.classify_outcome(plan), propagate.FALLBACK)

    def test_fallback_when_settings_json_is_unreadable(self):
        repo = current_repo_files()
        repo[propagate.SETTINGS] = "{not json"
        plan = self.plan_for(repo)
        self.assertEqual(propagate.classify_outcome(plan), propagate.FALLBACK)

    def test_fallback_when_the_push_is_refused(self):
        repo = current_repo_files(version="0.6.0")
        plan = self.plan_for(repo)
        self.assertEqual(propagate.classify_outcome(plan), propagate.CHANGED)
        self.assertEqual(
            propagate.classify_outcome(plan, push_error="403 workflow scope"),
            propagate.FALLBACK)

    def test_permission_errors_are_recognized(self):
        self.assertTrue(propagate.is_permission_error(
            "refusing to allow an OAuth App to create workflow: 403"))
        self.assertFalse(propagate.is_permission_error("could not resolve host"))


class TestPlanBoundaries(unittest.TestCase):
    def test_repo_owned_content_outside_the_markers_survives(self):
        repo = current_repo_files(version="0.6.0")
        repo[propagate.CLAUDE_MD] = repo[propagate.CLAUDE_MD].replace(
            "repo-owned.", "a project fact only this repo knows")
        plan = propagate.plan_stamp(repo, templates(), {}, "0.7.0")
        written = plan.writes[propagate.CLAUDE_MD]
        self.assertIn("a project fact only this repo knows", written)
        self.assertIn("# CLAUDE.md — consumer", written)  # H1 untouched

    def test_memory_files_are_created_but_never_overwritten(self):
        repo = current_repo_files()
        repo[propagate.MEMORY_INDEX] = None          # absent -> created
        repo[propagate.MEMORY_SEED] = "edited by the repo\n"  # present -> untouched
        plan = propagate.plan_stamp(repo, templates(), {}, "0.7.0")
        self.assertIn(propagate.MEMORY_INDEX, plan.writes)
        self.assertNotIn(propagate.MEMORY_SEED, plan.writes)

    def test_a_new_template_workflow_is_stamped_as_a_new_file(self):
        extra = ".github/workflows/claude-smoke-test.yml"
        repo = current_repo_files()
        repo[extra] = None
        plan = propagate.plan_stamp(repo, templates(**{extra: "smoke\n"}), {}, "0.7.0")
        self.assertEqual(plan.writes[extra], "smoke\n")
        self.assertEqual(plan.unreconcilable, [])

    def test_settings_formatting_alone_is_not_a_change(self):
        """A repo that formats its settings differently is not stale; the
        propagation must not reformat it on every run."""
        repo = current_repo_files()
        repo[propagate.SETTINGS] = json.dumps(json.loads(SETTINGS_TEMPLATE))  # one line
        plan = propagate.plan_stamp(repo, templates(), {}, "0.7.0")
        self.assertNotIn(propagate.SETTINGS, plan.writes)

    def test_settings_merge_keeps_repo_owned_keys_and_pins(self):
        repo = current_repo_files()
        repo[propagate.SETTINGS] = json.dumps({
            "permissions": {"allow": ["Bash(npm test)"]},
            "extraKnownMarketplaces": {"onur": {"source": {
                "source": "github", "repo": "onurcelep/ai-factory", "ref": "v0.6.0"}}},
            "enabledPlugins": {"local@thing": True},  # factory wiring missing
        }, indent=2) + "\n"
        plan = propagate.plan_stamp(repo, templates(), {}, "0.7.0")
        merged = json.loads(plan.writes[propagate.SETTINGS])
        self.assertEqual(merged["permissions"]["allow"], ["Bash(npm test)"])
        self.assertTrue(merged["enabledPlugins"]["local@thing"])
        self.assertTrue(merged["enabledPlugins"]["factory@onur"])  # wiring added
        self.assertEqual(
            merged["extraKnownMarketplaces"]["onur"]["source"]["ref"], "v0.6.0")


class TestTokenHandling(unittest.TestCase):
    """The token reaches consumer repos' issue bodies and the job summary
    through command output, so it must never enter a URL or a captured stream."""

    TOKEN = "ghp_exampletoken1234567890"

    def test_clone_url_carries_no_credentials(self):
        url = propagate.clone_url("owner/repo")
        self.assertNotIn("@", url)
        self.assertNotIn(self.TOKEN, url)

    def test_credentials_travel_in_the_environment_not_the_command(self):
        env = propagate.git_env(self.TOKEN)
        self.assertEqual(env["GIT_CONFIG_KEY_0"], "http.extraheader")
        self.assertIn(propagate.basic_auth(self.TOKEN), env["GIT_CONFIG_VALUE_0"])
        self.assertNotIn(self.TOKEN, env["GIT_CONFIG_VALUE_0"])  # encoded, not raw

    def test_command_error_stderr_is_redacted(self):
        with self.assertRaises(propagate.CommandError) as caught:
            propagate.run(["sh", "-c", f"echo {self.TOKEN} >&2; exit 3"],
                          redact_secret=self.TOKEN)
        self.assertNotIn(self.TOKEN, caught.exception.stderr)
        self.assertIn("***", caught.exception.stderr)
        # and it stays redacted all the way into the filed issue body
        body = propagate.issue_body("0.7.0", "0.6.0",
                                    f"push refused: {caught.exception.stderr}")
        self.assertNotIn(self.TOKEN, body)

    def test_basic_auth_form_is_redacted_too(self):
        encoded = propagate.basic_auth(self.TOKEN)
        self.assertEqual(propagate.redact(f"header: {encoded}", self.TOKEN),
                         "header: ***")

    def test_clone_leaves_no_token_in_the_repo_config(self):
        """Real clone through the same helpers: remote.origin.url and the
        on-disk config must come out credential-free."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            origin = tmp / "origin.git"
            subprocess.run(["git", "init", "--bare", "-b", "main", str(origin)],
                           check=True, capture_output=True)
            seed = tmp / "seed"
            subprocess.run(["git", "clone", str(origin), str(seed)],
                           check=True, capture_output=True)
            (seed / "README.md").write_text("hello\n")
            subprocess.run(["git", "add", "-A"], cwd=seed, check=True, capture_output=True)
            subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@e",
                            "commit", "-m", "seed"], cwd=seed, check=True,
                           capture_output=True)
            subprocess.run(["git", "push", "origin", "main"], cwd=seed,
                           check=True, capture_output=True)

            checkout = tmp / "clone"
            propagate.run(["git", "clone", "--single-branch", str(origin),
                           str(checkout)], redact_secret=self.TOKEN,
                          env=propagate.git_env(self.TOKEN))
            url = propagate.run(["git", "config", "--get", "remote.origin.url"],
                                cwd=checkout).stdout
            self.assertNotIn(self.TOKEN, url)
            self.assertNotIn(self.TOKEN, (checkout / ".git" / "config").read_text())


class TestFallbackIssueGuard(unittest.TestCase):
    """Filing the fallback issue can fail on its own (Issues disabled, a PAT
    without Issues: write). That must not abort the fleet loop."""

    def setUp(self):
        self._real = propagate.file_fallback_issue
        self.addCleanup(setattr, propagate, "file_fallback_issue", self._real)

    def test_a_failed_filing_becomes_a_visible_outcome(self):
        def boom(*_args, **_kwargs):
            raise propagate.CommandError(
                ["gh", "issue", "create"],
                subprocess.CompletedProcess([], 1, "", "403 Issues are disabled"))
        propagate.file_fallback_issue = boom
        detail = propagate.try_fallback_issue("o/r", "0.7.0", "0.6.0", "push refused")
        self.assertTrue(detail.startswith("could not file issue:"))
        self.assertIn("403", detail)
        # the unprocessed filter in main() keys off exactly this prefix
        self.assertFalse(detail.startswith(("filed", "issue already open", "would file")))

    def test_a_failed_filing_is_redacted(self):
        token = "ghp_secret_value_42"
        propagate._SECRET = token
        self.addCleanup(setattr, propagate, "_SECRET", None)

        def boom(*_args, **_kwargs):
            raise RuntimeError(f"remote rejected for {token}")
        propagate.file_fallback_issue = boom
        detail = propagate.try_fallback_issue("o/r", "0.7.0", "0.6.0", "push refused")
        self.assertNotIn(token, detail)

    def test_the_summary_survives_a_crash_in_the_loop(self):
        """write_summary runs in a finally, so results collected before an
        exception still reach the job summary."""
        source = (ROOT / "scripts" / "propagate.py").read_text()
        body = source[source.index("def main()"):]
        self.assertIn("finally:", body)
        self.assertLess(body.index("finally:"), body.index("write_summary(results)"))


class TestBodies(unittest.TestCase):
    def test_pr_body_is_plain_ascii_and_names_the_version(self):
        body = propagate.pr_body("0.7.0", [WF, propagate.CLAUDE_MD])
        body.encode("ascii")  # raises if a non-ASCII character slipped in
        self.assertIn("0.7.0", body)
        self.assertIn(WF, body)
        self.assertIn("review", body.lower())

    def test_fallback_issue_body_carries_the_reason_and_tags_claude(self):
        body = propagate.issue_body("0.7.0", "0.6.0", "push refused: 403")
        self.assertTrue(body.startswith("@claude"))
        self.assertIn("push refused: 403", body)
        self.assertIn("/factory-update", body)


if __name__ == "__main__":
    unittest.main()
