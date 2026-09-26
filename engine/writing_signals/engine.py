import os
from typing import Any, Dict, List, Tuple

from laya import Agent

from .catalogue import (FLOW_QUESTION, LOCATE_MAX_WORDS, MISTAKE_TYPE_QUESTION, QUESTIONS, flow_state, locate_question,
                        locate_words, type_state)

# English only, on the CPU: 2.0 GB and ~0.5 s per sentence on an M1, which fits 8 GB Macs.
# The Apple GPU path costs ~4 GB for the same model.
CHECKPOINT = "convaiinnovations/laya"
# Plumb's fine-tuned checkpoint, once installed. Preferred over the base model when present.
TRAINED_DIR = os.path.expanduser("~/Library/Application Support/Plumb/model")


# Mistake types were first trained in run 4; an older model would only guess, so it names none.
TYPES_FROM_RUN = 4


def model_run(checkpoint: str) -> int:
    """Which training run a model folder holds, from its plumb_model.json (run 3 on); 2 before."""
    import json
    try:
        with open(os.path.join(checkpoint, "plumb_model.json")) as f:
            return int(json.load(f).get("run", 2))
    except (OSError, ValueError):
        return 2


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
        self.knows_types = model_run(self.checkpoint) >= TYPES_FROM_RUN

    def score(self, sentences: List[str], signals: List[str] = None) -> List[Dict[str, Any]]:
        """Every catalogue signal for each sentence, or only `signals`. Each signal is its own pass
        over the sentence, so asking for grammar and sense alone is about 4x faster."""
        if not sentences:
            return []
        questions = {k: QUESTIONS[k] for k in signals if k in QUESTIONS} if signals else QUESTIONS
        # Runs of spaces are the rules' job; the model sees each sentence with single spaces.
        outputs = self.agent.predict_batch([" ".join(s.split()) for s in sentences], questions)
        return [
            {
                "model": self.model,
                "signals": {
                    name: _signal(out["answers"][name], QUESTIONS[name]) for name in questions
                },
            }
            for out in outputs
        ]

    def flow(self, pairs: List[Tuple[str, str]]) -> List[Dict[str, Any]]:
        """For each (previous, sentence) pair: does the sentence fail to follow on?"""
        if not pairs:
            return []
        outputs = self.agent.predict_batch([flow_state(p, s) for p, s in pairs], {"flow": FLOW_QUESTION})
        return [_signal(out["answers"]["flow"], FLOW_QUESTION) for out in outputs]

    def locate(self, sentences: List[str]) -> List[Any]:
        """For each sentence, the word most likely to be wrong: its text, UTF-16 offsets (as the
        app counts) and probability, plus what kind of mistake it is and how sure that is. None for
        a sentence with no words or too many to weigh."""
        found = []
        for text in sentences:
            words = locate_words(text)
            if not words or len(words) > LOCATE_MAX_WORDS:
                found.append(None)
                continue
            answer = self.agent.predict_batch([text], {"locate": locate_question(text)})[0]["answers"]["locate"]
            key = max(answer["probabilities"], key=answer["probabilities"].get)
            word, start, end = words[int(key[1:])]
            utf16 = lambda i: len(text[:i].encode("utf-16-le")) // 2
            label = confidence = None
            if self.knows_types:
                kind = self.agent.predict_batch([type_state(text, word)], {"type": MISTAKE_TYPE_QUESTION})[0]["answers"]["type"]
                label = max(kind["probabilities"], key=kind["probabilities"].get)
                confidence = kind["probabilities"][label]
            found.append({"text": word, "start": utf16(start), "end": utf16(end),
                          "probability": answer["probabilities"][key], "type": label, "type_probability": confidence})
        return found
