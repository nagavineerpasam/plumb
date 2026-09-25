"""Labelled test sets in one common format: sentence, language, signal, expected."""
import json
import os
from typing import Dict, List

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "data")
DRAFT_PATH = os.path.join(DATA_DIR, "english_draft.jsonl")

# DAIR Emotion has no neutral class, and "love" has no catalogue label; joy is its closest.
DAIR_TO_CATALOGUE = {
    "sadness": "sadness", "joy": "joy", "love": "joy",
    "anger": "anger", "fear": "fear", "surprise": "surprise",
}

Example = Dict[str, str]


def load_cola() -> List[Example]:
    """CoLA in-domain validation. Label 0 (unacceptable) means the sentence has a mistake."""
    from datasets import load_dataset
    rows = load_dataset("nyu-mll/glue", "cola", split="validation")
    return [{"sentence": r["sentence"], "language": "en", "signal": "grammar",
             "expected": "no" if r["label"] == 1 else "yes", "source": "cola"} for r in rows]


def load_dair() -> List[Example]:
    """DAIR Emotion test split, mapped onto the catalogue's emotion labels."""
    from datasets import load_dataset
    rows = load_dataset("dair-ai/emotion", split="test")
    names = rows.features["label"].names
    return [{"sentence": r["text"], "language": "en", "signal": "emotion",
             "expected": DAIR_TO_CATALOGUE[names[r["label"]]], "source": "dair"} for r in rows]


def load_drafted(path: str = DRAFT_PATH) -> List[Example]:
    """The Claude-drafted English set (DRAFT until the developer reviews it)."""
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]
