import os
from typing import Any, Dict, List

from laya import Agent

from .catalogue import QUESTIONS

# English only, on the CPU: 2.0 GB and ~0.5 s per sentence on an M1, which fits 8 GB Macs.
# The Apple GPU path costs ~4 GB for the same model.
CHECKPOINT = "convaiinnovations/laya"
# Plumb's fine-tuned checkpoint, once installed. Preferred over the base model when present.
TRAINED_DIR = os.path.expanduser("~/Library/Application Support/Plumb/model")


def default_checkpoint() -> str:
    return TRAINED_DIR if os.path.exists(os.path.join(TRAINED_DIR, "model.safetensors")) else CHECKPOINT


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
    """Scores English sentences for every catalogue signal, batched in one Laya call."""

    def __init__(self, checkpoint: str = None, device: str = "cpu"):
        self.device = device
        self.checkpoint = checkpoint or default_checkpoint()
        self.model = "plumb" if self.checkpoint == TRAINED_DIR else "english"
        self.agent = Agent(self.checkpoint, device=device)

    def score(self, sentences: List[str]) -> List[Dict[str, Any]]:
        if not sentences:
            return []
        outputs = self.agent.predict_batch(sentences, QUESTIONS)
        return [
            {
                "model": self.model,
                "signals": {
                    name: _signal(out["answers"][name], QUESTIONS[name]) for name in QUESTIONS
                },
            }
            for out in outputs
        ]
