"""python -m writing_signals.train_data: build the fine-tuning set and the Kaggle upload.

Training rows come from public training splits (CoLA train, DAIR Emotion train, Pavlick
formality train) plus the Claude-written synthetic files in data/train/. No training
sentence may appear in any test set; `build` enforces that.
"""
import glob
import hashlib
import json
import os
import random
import re
import zipfile
from collections import Counter, defaultdict
from typing import Dict, Iterable, List

from .catalogue import (CATALOGUE_VERSION, FLOW_QUESTION, FLOW_STATE_FORMAT, LOCATE_MAX_WORDS, MISTAKE_TYPES,
                        QUESTIONS, locate_question, locate_words)
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


def sentence_hash(sentence: str) -> str:
    """How validation sentences are banned without storing their text (FCE may not be shared)."""
    return hashlib.sha1(_key(sentence).encode()).hexdigest()


def build(training: Iterable[Row], test_sentences: Iterable[str],
          test_pairs: Iterable[tuple] = (), banned_hashes: Iterable[str] = ()) -> List[Row]:
    """Drops rows that overlap a test sentence (or, for flow, a test pair) or a validation
    sentence (by hash), repeat an earlier row, or carry a label the catalogue doesn't have."""
    banned = {_key(s) for s in test_sentences}
    banned_hashes = set(banned_hashes)
    banned_pairs = {(_key(p), _key(s)) for p, s in test_pairs}
    seen = set()
    rows = []
    for r in training:
        key = _key(r["sentence"])
        if r.get("signal") == "mistake_type":
            key = (key, _key(r.get("word", "")))
            if r["expected"] not in MISTAKE_TYPES or not r.get("word") or sentence_hash(r["sentence"]) in banned_hashes:
                continue
            if (key, r["signal"]) in seen:
                continue
            seen.add((key, r["signal"]))
            rows.append({**r, "sentence": r["sentence"].strip()})
            continue
        if r.get("signal") == "flow":
            key = (_key(r.get("previous", "")), key)
            if not key[1] or key in banned_pairs:
                continue
        elif not key or key in banned or sentence_hash(r["sentence"]) in banned_hashes:
            continue
        if (key, r["signal"]) in seen:
            continue
        if r["signal"] == "locate":
            # the pointer's options are the sentence's own words
            if (len(locate_words(r["sentence"])) > LOCATE_MAX_WORDS
                    or r["expected"] not in locate_question(r["sentence"])["criteria"]):
                continue
        elif r["signal"] not in QUESTIONS and r["signal"] != "flow":
            continue
        elif r["expected"] not in labels(r["signal"]):
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


def fce_type(code: str, missing: bool):
    """Cambridge FCE error code -> Plumb's learner mistake type (None for word choice, spelling…).
    Codes are an operation (R replace, M missing, U unnecessary, F form…) plus a part of speech
    (V verb, N noun, D determiner, T preposition…). Tense and verb form are one lesson ("verb"),
    and every missing kind is one ("word_missing"): run 4 showed they're too easily confused."""
    if code in ("TV", "FV", "IV", "DV"):
        return "verb"
    if code.startswith("AG"):
        return "agreement"
    if code == "W":
        return "word_order"
    if code in ("FN", "IN", "CN"):
        return "number"
    if missing or code[0] == "M":
        return "word_missing" if code[0] == "M" else None
    if code.endswith("D") and code[0] in "RFU":
        return "article"
    if code.endswith("T") and code[0] in "RU":
        return "preposition"
    if code[0] == "U" and code[1:] in ("V", "N", "J", "Y", "A", "C", "Q"):
        return "word_extra"
    return None


# FCE error types that are spelling or punctuation: the rules' job, not grammar.
FCE_MECHANICS = {"S", "SA", "RP", "MP", "UP"}
_SENTENCE = re.compile(r"\S.*?(?:[.!?]+(?=[\"')\]]*(?:\s|$))[\"')\]]*|$)")


def split_sentences(text: str):
    """(sentence, start, end) per sentence; a line break always ends one, as in the app."""
    out, offset = [], 0
    for line in text.split("\n"):
        for m in _SENTENCE.finditer(line):
            s = m.group().strip()
            if len(s.split()) >= 2:
                out.append((s, offset + m.start(), offset + m.start() + len(s)))
        offset += len(line) + 1
    return out


def fce_rows(essays, holdout, rng_seed: int = 20260926) -> List[Row]:
    """Rows from FCE training essays (never the report's dev/test essays; `holdout` essays are
    kept for tuning). Per sentence: grammar yes/no from the examiners' corrections, a pointer at
    the corrected word when there's exactly one grammar correction, and flow pairs: neighbours
    follow, sentences from two different essays don't."""
    rng = random.Random(rng_seed)
    rows, used = [], [e for e in essays if e["id"] not in holdout]
    per_essay = []
    for e in used:
        edits = [x for _, group in e["edits"] for x in group]
        sentences = split_sentences(e["text"])
        per_essay.append([s for s, _, _ in sentences])
        for s, a, b in sentences:
            hit = [x for x in edits if a <= x[0] < b or x[0] == x[1] == b or x[0] < a < x[1]]
            grammar = [x for x in hit if x[3] not in FCE_MECHANICS]
            if hit and not grammar:
                continue  # only spelling or punctuation: not a grammar example either way
            rows.append({"sentence": s, "signal": "grammar", "expected": "yes" if grammar else "no", "source": "fce-train"})
            words = locate_words(s)
            if len(grammar) == 1 and len(words) <= LOCATE_MAX_WORDS:
                # A missing word (an insertion) points at the word after the gap.
                at, missing = grammar[0][0] - a, grammar[0][0] == grammar[0][1]
                i = next((i for i, (_, ws, we) in enumerate(words) if we > at), None)
                if i is not None:
                    rows.append({"sentence": s, "signal": "locate", "expected": f"w{i}", "source": "fce-train"})
                    kind = fce_type(grammar[0][3], missing)
                    if kind:
                        rows.append({"sentence": s, "word": words[i][0], "signal": "mistake_type", "expected": kind, "source": "fce-train"})
        for p, s in zip(per_essay[-1], per_essay[-1][1:]):
            rows.append({"previous": p, "sentence": s, "signal": "flow", "expected": "no", "source": "fce-train"})
    for i, sents in enumerate(per_essay):
        others = [j for j in range(len(per_essay)) if j != i and per_essay[j]]
        if sents and others:
            rows.append({"previous": rng.choice(sents), "sentence": rng.choice(per_essay[rng.choice(others)]),
                         "signal": "flow", "expected": "yes", "source": "fce-train"})
    return rows


def fce_holdout(essay_id: str) -> bool:
    """About 10% of FCE's training essays are kept out of training, for tuning the pointer's
    threshold and checking flow. Chosen by hash, so the evaluation finds the same ones."""
    return int(hashlib.sha1(essay_id.encode()).hexdigest()[:2], 16) < 26


def _take(rows: List[Row], signal: str, expected, n: int, rng: random.Random) -> List[Row]:
    group = [r for r in rows if r["signal"] == signal and (expected is None or r["expected"] == expected)]
    rng.shuffle(group)
    return group[:n]


def load_run3(raw_dir: str, rng: random.Random) -> List[Row]:
    """Run 3's additions, from local copies of FCE v2.1 (research use, never committed) and BLiMP.
    `raw_dir` holds fce/json/fce.train.json and blimp/*.jsonl (see data/README.md)."""
    from .mistakes import because_nonsense, inject, known_misses

    with open(os.path.join(raw_dir, "fce", "json", "fce.train.json"), encoding="utf-8") as f:
        essays = [json.loads(line) for line in f]
    holdout = {e["id"] for e in essays if fce_holdout(e["id"])}
    fce = fce_rows(essays, holdout)
    clean = [r["sentence"] for r in fce if r["signal"] == "grammar" and r["expected"] == "no"]
    rows = (_take(fce, "grammar", "yes", 2000, rng) + _take(fce, "grammar", "no", 3600, rng)
            + _take(fce, "locate", None, 4000, rng) + _take(fce, "flow", "no", 800, rng) + _take(fce, "flow", "yes", 800, rng))
    # Mistake types, capped per type so common ones (prepositions) don't drown rare ones (word order).
    for kind in {r["expected"] for r in fce if r["signal"] == "mistake_type"}:
        rows += _take(fce, "mistake_type", kind, 700, rng)
    rows += inject(rng.sample(clean, min(900, len(clean))))
    rows += known_misses() + because_nonsense()

    # BLiMP pairs the validation run didn't test (build drops any that match by hash): the right
    # twin teaches that odd but grammatical sentences are fine.
    banned = validation_hashes()
    for path in sorted(glob.glob(os.path.join(raw_dir, "blimp", "*.jsonl"))):
        with open(path, encoding="utf-8") as f:
            pairs = [json.loads(line) for line in f]
        pairs = [p for p in pairs if sentence_hash(p["sentence_good"]) not in banned and sentence_hash(p["sentence_bad"]) not in banned]
        for p in rng.sample(pairs, min(15, len(pairs))):
            rows.append({"sentence": p["sentence_good"], "signal": "grammar", "expected": "no", "source": "blimp-train"})
            rows.append({"sentence": p["sentence_bad"], "signal": "grammar", "expected": "yes", "source": "blimp-train"})
    return rows


def validation_hashes() -> set:
    with open(os.path.join(DATA_DIR, "validation_hashes.txt"), encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip() and not line.startswith("#")}


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
    raw_dir = os.environ.get("PLUMB_RAW_DATA")
    if not raw_dir:
        raise SystemExit("Set PLUMB_RAW_DATA to the folder holding fce/ and blimp/ (see data/README.md).")
    rows = build(load_public(rng) + load_synthetic() + load_run3(raw_dir, rng), test_sentences(), test_pairs(),
                 banned_hashes=validation_hashes())
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
    # A fresh sample for a human to eyeball each build; kept with the upload, out of git.
    with open(os.path.join(KAGGLE_DIR, "spot_check.md"), "w", encoding="utf-8") as f:
        f.write(_spot_check(rows, rng))

    counts = Counter((r["signal"], r["expected"], r["source"]) for r in rows)
    print(f"{len(rows)} training rows (catalogue v{CATALOGUE_VERSION})")
    for (signal, label, source), n in sorted(counts.items()):
        print(f"  {signal:10} {label:15} {source:17} {n}")
    print(f"Kaggle upload folder: {os.path.abspath(KAGGLE_DIR)}")


if __name__ == "__main__":
    main()
