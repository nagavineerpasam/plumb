"""Scores SignalEngine on labelled examples and judges each signal against its bar."""
import statistics
import time
from collections import defaultdict
from typing import Any, Dict, List

# Which labelled source each signal's bar is judged on, and the bar itself.
BARS = {
    "grammar": ("cola", 0.75),
    "emotion": ("dair", 0.55),
    "tone": ("claude-draft", 0.70),
    "formality": ("claude-draft", 0.70),
    "confidence": ("claude-draft", 0.70),
    "clarity": ("claude-draft", 0.70),
}


def predict(engine, examples: List[Dict[str, str]], batch_size: int = 32) -> List[Dict[str, Any]]:
    """Adds `predicted`, `yes_probability` (grammar only) and `model` to each example."""
    out = []
    for start in range(0, len(examples), batch_size):
        chunk = examples[start:start + batch_size]
        for example, result in zip(chunk, engine.score([e["sentence"] for e in chunk])):
            signal = result["signals"][example["signal"]]
            out.append({**example, "predicted": signal["value"], "model": result["model"],
                        "yes_probability": signal["distribution"].get("yes")})
    return out


def _accuracy(rows) -> float:
    return sum(r["predicted"] == r["expected"] for r in rows) / len(rows) if rows else 0.0


def _majority(rows) -> float:
    counts = defaultdict(int)
    for r in rows:
        counts[r["expected"]] += 1
    return max(counts.values()) / len(rows) if rows else 0.0


def best_threshold(rows) -> Dict[str, float]:
    """The yes-probability cut-off that maximises grammar accuracy on these rows."""
    best = {"threshold": 0.5, "accuracy": 0.0}
    for step in range(1, 100):
        t = step / 100
        acc = sum((r["yes_probability"] >= t) == (r["expected"] == "yes") for r in rows) / len(rows)
        if acc > best["accuracy"]:
            best = {"threshold": t, "accuracy": acc}
    return best


def summarise(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Per-signal accuracy vs bar, per source and per language."""
    signals = {}
    for signal, (bar_source, bar) in BARS.items():
        mine = [r for r in rows if r["signal"] == signal]
        judged = [r for r in mine if r["source"] == bar_source]
        by_source = defaultdict(list)
        by_language = defaultdict(list)
        for r in mine:
            by_source[r["source"]].append(r)
            by_language[r["language"]].append(r)
        accuracy = _accuracy(judged)
        entry = {
            "bar_source": bar_source, "bar": bar, "n": len(judged),
            "accuracy": accuracy, "majority_baseline": _majority(judged),
            "pass": bool(judged) and accuracy >= bar,
            "by_source": {s: {"n": len(v), "accuracy": _accuracy(v)} for s, v in sorted(by_source.items())},
            "by_language": {l: {"n": len(v), "accuracy": _accuracy(v)} for l, v in sorted(by_language.items())},
        }
        if signal == "grammar" and judged:
            entry["best_threshold"] = best_threshold(judged)
        signals[signal] = entry
    return signals


def measure_latency(engine, sentences: List[str]) -> Dict[str, Any]:
    """One call per sentence, all six signals, as the app sends an edited sentence."""
    times = []
    for text in sentences:
        started = time.perf_counter()
        engine.score([text])
        times.append((time.perf_counter() - started) * 1000)
    cuts = statistics.quantiles(times, n=100, method="inclusive") if len(times) > 1 else times * 99
    return {"calls": len(times), "p50_ms": cuts[49], "p95_ms": cuts[94]}
