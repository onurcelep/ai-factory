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


if __name__ == "__main__":
    sys.exit(0)  # CLI added in Task 2
