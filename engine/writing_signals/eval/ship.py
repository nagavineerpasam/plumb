"""The ship bar, as one function the training notebook and the local check both use.

A candidate model ships only if it is at least as good as the live model on real learner writing,
and its pointer and mistake types are right at least 90% of the time when shown. Among candidates
that pass, the one catching the most essay mistakes wins; if none passes, nothing ships.
"""
from typing import Callable, Dict, List, Optional, Tuple

# A shown pointer or named type must be right this often.
BAR = 0.90
# ...while still being shown for at least this share of cases (a bar met by staying silent is no use).
MIN_POINTER_SHOWN = 0.10
MIN_TYPE_NAMED = 0.25


def _rate(xs: List[bool]) -> Optional[float]:
    return sum(xs) / len(xs) if xs else None


def _lowest_threshold(items: List[Tuple[float, bool]], min_share: float):
    """The lowest confidence at which the items at or above it are right >= BAR, shown for at
    least `min_share` of items. Returns (threshold, rate, shown share); threshold None if none."""
    best = (None, None, 0.0)
    for t in sorted({p for p, _ in items}):
        above = [ok for p, ok in items if p >= t]
        share = len(above) / len(items)
        rate = sum(above) / len(above)
        if best[1] is None or rate > best[1]:
            best = (None, rate, share)
        if rate >= BAR and share >= min_share:
            return t, rate, share
    return best


def score(cases: List[dict], probs: Callable[[str], Tuple[float, float]], pointer_cases: List[dict]) -> Dict:
    """`cases`: {set, label, sentences}, each sentence split the app's way; a case is flagged when
    any sentence has grammar or sense >= 0.5 (the point the app takes points off).
    `pointer_cases`: {hit, p, type, pred, tp} from held-out essays."""
    m: Dict = {}
    for name in ("jfleg", "fce", "blimp"):
        mine = [c for c in cases if c["set"] == name]
        flagged = [any(max(probs(s)) >= 0.5 for s in c["sentences"]) for c in mine]
        m[f"{name}_caught"] = _rate([f for f, c in zip(flagged, mine) if c["label"] == "grammar"])
        m[f"{name}_false_alarms"] = _rate([f for f, c in zip(flagged, mine) if c["label"] == "correct"])
    if pointer_cases:
        t, rate, shown = _lowest_threshold([(c["p"], c["hit"]) for c in pointer_cases], MIN_POINTER_SHOWN)
        m.update(pointer_threshold=t, pointer_right=rate, pointer_shown=shown)
        typed = [(c["tp"], c["pred"] == c["type"]) for c in pointer_cases if c["hit"] and c.get("type") and c.get("tp") is not None]
        if typed:
            t, rate, named = _lowest_threshold(typed, MIN_TYPE_NAMED)
            m.update(type_threshold=t, type_right=rate, type_named=named)
    return m


def passes(m: Dict, floors: Dict) -> bool:
    """At least as good as the live model on every floor, and pointer and types right >= BAR."""
    return (m.get("signals_pass", False)
            and (m.get("fce_caught") or 0) >= floors["fce_caught"]
            and (m.get("jfleg_caught") or 0) >= floors["jfleg_caught"]
            and (m.get("fce_false_alarms") if m.get("fce_false_alarms") is not None else 1) <= floors["fce_false_alarms"]
            and (m.get("blimp_false_alarms") if m.get("blimp_false_alarms") is not None else 1) <= floors["blimp_false_alarms"]
            and (m.get("pointer_right") or 0) >= BAR
            and (m.get("type_right") or 0) >= BAR)


def pick(candidates: Dict[str, Dict], floors: Dict) -> Optional[str]:
    """The passing candidate that catches the most essay mistakes, or None."""
    ok = [(m["fce_caught"], name) for name, m in candidates.items() if passes(m, floors)]
    return max(ok)[1] if ok else None


def pointer_hit(case: dict, found: dict) -> bool:
    """Whether the pointer (UTF-16 offsets, as the worker gives) lands on the examiner's corrected
    words, or, for a missing word, on the word right after the gap."""
    text = case["sentence"]
    start = len(text.encode("utf-16-le")[:2 * found["start"]].decode("utf-16-le"))
    end = len(text.encode("utf-16-le")[:2 * found["end"]].decode("utf-16-le"))
    lo, hi = case["target_span"] if case["missing"] else case["span"]
    return start < hi and lo < end


def evaluate(engine, data: Dict, batch: int = 64) -> Dict:
    """Scores one candidate model: the report's cases and the held-out pointer/type cases.
    `data` is the exported ship_cases.json ({cases, pointer})."""
    texts = sorted({s for c in data["cases"] for s in c["sentences"]})
    probs = {}
    for i in range(0, len(texts), batch):
        chunk = texts[i:i + batch]
        for text, r in zip(chunk, engine.score(chunk)):
            probs[text] = (r["signals"]["grammar"]["distribution"]["yes"], r["signals"]["sense"]["distribution"]["yes"])
    pointer_cases = []
    for c in data["pointer"]:
        found = engine.locate([c["sentence"]])[0]
        if found:
            pointer_cases.append({"hit": pointer_hit(c, found), "p": found["probability"], "type": c.get("type"),
                                  "pred": found.get("type"), "tp": found.get("type_probability")})
    return score(data["cases"], probs.__getitem__, pointer_cases)
