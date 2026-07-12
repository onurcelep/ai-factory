#!/usr/bin/env python3
"""Skill eval runner for ai-factory.

Tier 2 (deterministic trigger/routing checks) runs by default and is CI-safe.
Tier 3 (behavioral, token-spending) runs via --behavioral. Design ported from
addyosmani/agent-skills; evals[] follows Anthropic skill-creator's evals.json
schema so its tooling works against these files unmodified.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = ROOT / "plugins" / "factory" / "skills"
CASES_DIR = ROOT / "evals" / "cases"
RESULTS_DIR = ROOT / "evals" / "results"

STOPWORDS = set(
    "a an and are as at be before by for from has have how in is it its "
    "of on or that the this to use used using when where which who will "
    "with your our my i you we they what should".split()
)


def stem(word):
    """Light suffix stripper — enough to unify routing/routes/routed."""
    for suffix in ("ing", "ed", "es", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[: len(word) - len(suffix)]
    return word


def tokenize(text):
    words = re.findall(r"[a-z0-9@][a-z0-9@/.-]*", text.lower())
    return [stem(w) for w in words if w not in STOPWORDS and len(w) > 1]


def load_skills():
    """name -> searchable text (spaced name + description) for every skill."""
    skills = {}
    for skill_md in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        front = skill_md.read_text().split("---")[1]
        name = re.search(r"^name:\s*(.+)$", front, re.M).group(1).strip()
        desc = re.search(r"^description:\s*(.+)$", front, re.M).group(1).strip()
        skills[name] = f"{name.replace('-', ' ')} {desc}"
    return skills


def build_vectors(docs):
    """docs: name -> token list. Returns (tf-idf vectors, document freq, corpus size)."""
    df = {}
    for tokens in docs.values():
        for t in set(tokens):
            df[t] = df.get(t, 0) + 1
    n = len(docs)
    vecs = {}
    for name, tokens in docs.items():
        tf = {}
        for t in tokens:
            tf[t] = tf.get(t, 0) + 1
        vecs[name] = {
            t: (c / len(tokens)) * (math.log((n + 1) / (df[t] + 1)) + 1)
            for t, c in tf.items()
        }
    return vecs, df, n


def prompt_vector(prompt, df, n):
    tokens = tokenize(prompt)
    if not tokens:
        return {}
    tf = {}
    for t in tokens:
        tf[t] = tf.get(t, 0) + 1
    return {
        t: (c / len(tokens)) * (math.log((n + 1) / (df.get(t, 0) + 1)) + 1)
        for t, c in tf.items()
    }


def cosine(a, b):
    if not a or not b:
        return 0.0
    dot = sum(v * b[t] for t, v in a.items() if t in b)
    norm_a = math.sqrt(sum(v * v for v in a.values()))
    norm_b = math.sqrt(sum(v * v for v in b.values()))
    return dot / (norm_a * norm_b) if norm_a and norm_b else 0.0


def rank_prompt(prompt, skill_vecs, df, n):
    pvec = prompt_vector(prompt, df, n)
    scored = [(name, cosine(pvec, vec)) for name, vec in skill_vecs.items()]
    return sorted(scored, key=lambda x: (-x[1], x[0]))


COLLISION_ERROR = 0.75
COLLISION_WARN = 0.50
MIN_POSITIVE, MIN_NEGATIVE, MIN_EVALS = 3, 2, 1


def load_cases():
    cases = {}
    for case_file in sorted(CASES_DIR.glob("*.json")):
        case = json.loads(case_file.read_text())
        cases[case["skill_name"]] = case
    return cases


def check_collisions(skill_vecs):
    """All description pairs with cosine similarity >= COLLISION_WARN."""
    names = sorted(skill_vecs)
    pairs = []
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            sim = cosine(skill_vecs[a], skill_vecs[b])
            if sim >= COLLISION_WARN:
                pairs.append((a, b, sim))
    return pairs


def run_tier2(verbose=True):
    skills = load_skills()
    docs = {name: tokenize(text) for name, text in skills.items()}
    skill_vecs, df, n = build_vectors(docs)
    cases = load_cases()
    errors, warnings = [], []
    say = print if verbose else (lambda *a, **k: None)

    for name in skills:
        if name not in cases:
            errors.append(f"{name}: no eval case file (evals/cases/{name}.json)")
    for name in cases:
        if name not in skills:
            errors.append(f"cases/{name}.json: no such skill")

    rank1_hits = rank1_total = 0
    for name, case in cases.items():
        if name not in skills:
            continue
        trig = case.get("trigger", {})
        pos, neg, evals = trig.get("positive", []), trig.get("negative", []), case.get("evals", [])
        if len(pos) < MIN_POSITIVE or len(neg) < MIN_NEGATIVE or len(evals) < MIN_EVALS:
            warnings.append(
                f"{name}: below minimums ({len(pos)} positive/{len(neg)} negative/{len(evals)} evals; "
                f"want >={MIN_POSITIVE}/>={MIN_NEGATIVE}/>={MIN_EVALS})"
            )
        for p in pos:
            ranked = rank_prompt(p["prompt"], skill_vecs, df, n)
            order = [r[0] for r in ranked]
            top_k = p.get("top_k", 3)
            rank = order.index(name) + 1
            rank1_total += 1
            rank1_hits += rank == 1
            if rank > top_k:
                errors.append(
                    f"{name}: positive prompt ranked #{rank} (need top-{top_k}): "
                    f"{p['prompt']!r} — top hit was {order[0]!r}"
                )
        for p in neg:
            ranked = rank_prompt(p["prompt"], skill_vecs, df, n)
            order = [r[0] for r in ranked]
            owner = p.get("owner")
            if owner and owner in order and order.index(owner) > order.index(name):
                errors.append(
                    f"{name}: outranks owner {owner!r} on negative prompt: {p['prompt']!r}"
                )

    for a, b, sim in check_collisions(skill_vecs):
        msg = f"description collision {a} <-> {b}: {sim:.0%} similar"
        (errors if sim >= COLLISION_ERROR else warnings).append(msg)

    for w in warnings:
        say(f"warn: {w}")
    for e in errors:
        say(f"FAIL: {e}")
    if rank1_total:
        say(f"trigger rank-1 rate: {rank1_hits}/{rank1_total} ({rank1_hits / rank1_total:.0%})")
    say("tier 2: " + ("FAILED" if errors else "ok"))
    return 1 if errors else 0


def run_behavioral(target, dry_run):
    print("behavioral tier not implemented yet (Task 4)")
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--behavioral", metavar="SKILL", nargs="?", const="all",
                        help="run Tier-3 behavioral evals (spends tokens)")
    parser.add_argument("--dry-run", action="store_true",
                        help="with --behavioral: print the plan, run nothing")
    args = parser.parse_args()
    if args.behavioral:
        return run_behavioral(args.behavioral, args.dry_run)
    return run_tier2()


if __name__ == "__main__":
    sys.exit(main())
