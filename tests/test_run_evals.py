import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
run_evals = __import__("run-evals")


class TestLexicalEngine(unittest.TestCase):
    CORPUS = {
        "cooking": ["bake", "oven", "bread", "flour", "knead", "dough"],
        "sailing": ["boat", "sail", "wind", "harbor", "anchor", "knot"],
        "gardening": ["plant", "soil", "water", "seed", "prune", "grow"],
    }

    def test_stem_strips_common_suffixes(self):
        self.assertEqual(run_evals.stem("routing"), "rout")
        self.assertEqual(run_evals.stem("stamped"), "stamp")
        self.assertEqual(run_evals.stem("repos"), "repo")
        # too short to strip: would leave < 3 chars
        self.assertEqual(run_evals.stem("is"), "is")

    def test_tokenize_lowercases_stems_and_drops_stopwords(self):
        toks = run_evals.tokenize("The agent is Routing repos to the harbor")
        self.assertIn("rout", toks)
        self.assertIn("repo", toks)
        self.assertIn("harbor", toks)
        self.assertNotIn("the", toks)
        self.assertNotIn("to", toks)

    def test_tokenize_keeps_at_mentions_and_slashes(self):
        toks = run_evals.tokenize("diagnose the @claude run in docs/memory")
        self.assertIn("@claude", toks)
        self.assertIn("docs/memory", toks)

    def test_cosine_identical_and_disjoint(self):
        a = {"x": 1.0, "y": 2.0}
        self.assertAlmostEqual(run_evals.cosine(a, a), 1.0, places=6)
        self.assertEqual(run_evals.cosine(a, {"z": 3.0}), 0.0)
        self.assertEqual(run_evals.cosine({}, a), 0.0)

    def test_rank_prompt_prefers_matching_doc(self):
        vecs, df, n = run_evals.build_vectors(self.CORPUS)
        ranked = run_evals.rank_prompt("knead the dough and bake bread", vecs, df, n)
        self.assertEqual(ranked[0][0], "cooking")
        self.assertGreater(ranked[0][1], ranked[1][1])

    def test_rank_prompt_unknown_terms_score_zero(self):
        vecs, df, n = run_evals.build_vectors(self.CORPUS)
        ranked = run_evals.rank_prompt("quantum flux capacitor", vecs, df, n)
        self.assertTrue(all(score == 0.0 for _, score in ranked))

    def test_load_skills_finds_all_factory_skills(self):
        skills = run_evals.load_skills()
        self.assertIn("factory-init", skills)
        self.assertIn("model-routing", skills)
        self.assertEqual(len(skills), 7)
        # searchable text includes both the spaced name and description words
        self.assertIn("factory init", skills["factory-init"].lower())


class TestTier2(unittest.TestCase):
    def test_check_collisions_flags_near_duplicates(self):
        docs = {
            "alpha": run_evals.tokenize("stamp the repository with standard workflows and settings"),
            "beta": run_evals.tokenize("stamp the repository with standard workflows and wiring"),
            "gamma": run_evals.tokenize("prune the garden and water the seeds"),
        }
        vecs, _, _ = run_evals.build_vectors(docs)
        pairs = run_evals.check_collisions(vecs)
        names = {frozenset((a, b)) for a, b, _ in pairs}
        self.assertIn(frozenset(("alpha", "beta")), names)
        self.assertNotIn(frozenset(("alpha", "gamma")), names)

    def test_load_cases_returns_case_per_file(self):
        cases = run_evals.load_cases()
        for name, case in cases.items():
            self.assertEqual(case["skill_name"], name)

    def test_run_tier2_passes_on_current_repo(self):
        # The repo's own cases + descriptions must stay green; this is the
        # same gate CI runs via validate.sh.
        self.assertEqual(run_evals.run_tier2(verbose=False), 0)


if __name__ == "__main__":
    unittest.main()
