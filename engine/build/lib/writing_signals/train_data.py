"""python -m writing_signals.train_data: build the fine-tuning set and the Kaggle upload.

Training rows come from public training splits (CoLA train, DAIR Emotion train, Pavlick
formality train) plus the Claude-written synthetic files in data/train/. No training
sentence may appear in any test set; `build` enforces that.
"""
import glob
import json
import os
import random
import re
import zipfile
from collections import Counter, defaultdict
from typing import Dict, Iterable, List

from .catalogue import CATALOGUE_VERSION, FLOW_QUESTION, FLOW_STATE_FORMAT, QUESTIONS
from .eval.datasets import DAIR_TO_CATALOGUE, DATA_DIR, load_cola, load_dair, load_drafted, load_flow

TRAIN_DIR = os.path.join(DATA_DIR, "train")
KAGGLE_DIR = os.path.join(DATA_DIR, "kaggle")
ENGINE_DIR = os.path.join(DATA_DIR, "..")
PER_LABEL_CAP = 1000  # keeps the big public sets from drowning the synthetic signals

Row = Dict[str, str]


def labels(signal: str) -> List[str]:
    question = FLOW_QUESTION if signal == "flow" else QUESTIONS[signal]
    if question["type"] == "noul":
        return ["no", "yes"]
    return list(question["criteria"])


def _key(sentence: str) -> str:
    return re.sub(r"\s+", " ", sentence).strip().lower()


def build(training: Iterable[Row], test_sentences: Iterable[str],
          test_pairs: Iterable[tuple] = ()) -> List[Row]:
    """Drops rows that overlap a test sentence (or, for flow, a test pair), repeat an earlier
    row, or carry a label the catalogue doesn't have."""
    banned = {_key(s) for s in test_sentences}
    banned_pairs = {(_key(p), _key(s)) for p, s in test_pairs}
    seen = set()
    rows = []
    for r in training:
        key = _key(r["sentence"])
        if r.get("signal") == "flow":
            key = (_key(r.get("previous", "")), key)
            if not key[1] or key in banned_pairs:
                continue
        elif not key or key in banned:
            continue
        if (key, r["signal"]) in seen:
            continue
        if r["signal"] not in QUESTIONS and r["signal"] != "flow":
            continue
        if r["expected"] not in labels(r["signal"]):
            continue
        seen.add((key, r["signal"]))
        rows.append({**r, "sentence": r["sentence"].strip()})
    return rows


def _cap(rows: List[Row], rng: random.Random) -> List[Row]:
    by_label = defaultdict(list)
    for r in rows:
        by_label[r["expected"]].append(r)
    capped = []
    for group in by_label.values():
        rng.shuffle(group)
        capped += group[:PER_LABEL_CAP]
    return capped


def load_public(rng: random.Random) -> List[Row]:
    from datasets import load_dataset

    cola = load_dataset("nyu-mll/glue", "cola", split="train")
    grammar = [{"sentence": r["sentence"], "signal": "grammar", "source": "cola-train",
                "expected": "no" if r["label"] == 1 else "yes"} for r in cola]

    dair = load_dataset("dair-ai/emotion", split="train")
    names = dair.features["label"].names
    emotion = [{"sentence": r["text"], "signal": "emotion", "source": "dair-train",
                "expected": DAIR_TO_CATALOGUE[names[r["label"]]]} for r in dair]

    # Pavlick scores run from -3 (informal) to +3 (formal). The gaps between buckets are
    # dropped so borderline sentences don't teach the wrong label.
    pavlick = load_dataset("osyvokon/pavlick-formality-scores", split="train")
    formality = []
    for r in pavlick:
        score, text = r["avg_score"], r["sentence"]
        if len(text.split()) < 4 or "http" in text or "@" in text:
            continue
        bucket = "informal" if score <= -1 else "formal" if score >= 1 else "neutral" if abs(score) <= 0.4 else None
        if bucket:
            formality.append({"sentence": text, "signal": "formality", "source": "pavlick-train",
                              "expected": bucket})
    return _cap(grammar, rng) + _cap(emotion, rng) + _cap(formality, rng)


def load_synthetic() -> List[Row]:
    rows = []
    for path in sorted(glob.glob(os.path.join(TRAIN_DIR, "synthetic_*.jsonl"))):
        with open(path, encoding="utf-8") as f:
            rows += [json.loads(line) for line in f if line.strip()]
    return rows


def test_sentences() -> List[str]:
    """Every sentence any accuracy check may score, including the full CoLA and DAIR splits."""
    return [e["sentence"] for e in load_cola() + load_dair() + load_drafted()]


def test_pairs() -> List[tuple]:
    return [(e["previous"], e["sentence"]) for e in load_flow()]


def _spot_check(rows: List[Row], rng: random.Random, n: int = 50) -> str:
    synthetic = [r for r in rows if r["source"] == "claude-synthetic"]
    sample = sorted(rng.sample(synthetic, min(n, len(synthetic))), key=lambda r: (r["signal"], r["expected"]))
    lines = ["# Spot-check: 50 Claude-labelled training rows", "",
             "Mark any label you disagree with. Rules: data/README.md → Labelling rules.", "",
             "| # | signal | label | sentence | OK? |", "|---|---|---|---|---|"]
    lines += [f"| {i} | {r['signal']} | {r['expected']} | {r['sentence'].replace('|', '/')} | |"
              for i, r in enumerate(sample, 1)]
    return "\n".join(lines) + "\n"


def main():
    rng = random.Random(20260925)
    rows = build(load_public(rng) + load_synthetic(), test_sentences(), test_pairs())
    rng.shuffle(rows)

    os.makedirs(KAGGLE_DIR, exist_ok=True)
    with open(os.path.join(KAGGLE_DIR, "train.jsonl"), "w", encoding="utf-8") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
    with open(os.path.join(KAGGLE_DIR, "catalogue.json"), "w", encoding="utf-8") as f:
        json.dump({"version": CATALOGUE_VERSION, "questions": QUESTIONS, "flow_question": FLOW_QUESTION,
                   "flow_state_format": FLOW_STATE_FORMAT}, f, indent=2)
    # The notebook runs this exact engine for the same accuracy check after training.
    with zipfile.ZipFile(os.path.join(KAGGLE_DIR, "engine.zip"), "w", zipfile.ZIP_DEFLATED) as z:
        for path in ["pyproject.toml", "data/README.md", "data/english_draft.jsonl",
                     "data/sense_test_draft.jsonl", "data/flow_test_draft.jsonl",
                     *glob.glob("writing_signals/**/*.py", root_dir=ENGINE_DIR, recursive=True)]:
            z.write(os.path.join(ENGINE_DIR, path), os.path.join("engine", path))
    with open(os.path.join(TRAIN_DIR, "spot_check.md"), "w", encoding="utf-8") as f:
        f.write(_spot_check(rows, rng))

    counts = Counter((r["signal"], r["expected"], r["source"]) for r in rows)
    print(f"{len(rows)} training rows (catalogue v{CATALOGUE_VERSION})")
    for (signal, label, source), n in sorted(counts.items()):
        print(f"  {signal:10} {label:15} {source:17} {n}")
    print(f"Kaggle upload folder: {os.path.abspath(KAGGLE_DIR)}")


if __name__ == "__main__":
    main()
