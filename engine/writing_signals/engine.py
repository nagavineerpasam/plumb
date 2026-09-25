from typing import Any, Dict, List

from laya import Router

from .catalogue import QUESTIONS


def _signal(answer: Dict[str, Any], question: Dict[str, Any]) -> Dict[str, Any]:
    kind = answer["type"]
    if kind == "noul":
        yes = answer["noul"]
        distribution = {"yes": yes, "no": 1.0 - yes}
    elif kind == "choice":
        distribution = dict(answer["probabilities"])
    else:  # score: key the distribution by label, keep the 0..1 position for gauges
        labels = question["criteria"]
        distribution = {labels[int(i)]: p for i, p in answer["probabilities"].items()}
        position = answer["score"] / (len(labels) - 1)
    signal = {"value": max(distribution, key=distribution.get), "distribution": distribution}
    if kind == "score":
        signal["score"] = position
    return signal


class SignalEngine:
    """Scores sentences for every catalogue signal, one Laya pass per sentence."""

    def __init__(self, router: Router = None):
        # One checkpoint in memory at a time keeps 8 GB Macs viable.
        self.router = router or Router(max_loaded=1)

    def score(self, sentences: List[str]) -> List[Dict[str, Any]]:
        if not sentences:
            return []
        outputs = self.router.predict_batch(
            [{"state": text, "questions": QUESTIONS} for text in sentences]
        )
        return [
            {
                "model": out["routing"]["model"],
                "signals": {
                    name: _signal(out["answers"][name], QUESTIONS[name]) for name in QUESTIONS
                },
            }
            for out in outputs
        ]
