"""Generated training rows for run 3, each with a known position for the "which word" pointer.

- `inject`: one common learner mistake put into a correct sentence (a past participle for the
  past tense, a flipped agreement, the wrong article), with a pointer at the changed word.
- `known_misses`: the mistakes the validation run showed the model letting through, each with its
  correct twin.
- `because_nonsense`: "because" clauses that say nothing, for the sense check.
"""
import itertools
import random
import re
from typing import Dict, List, Optional, Tuple

from .catalogue import locate_words

Row = Dict[str, str]

PARTICIPLES = {"went": "gone", "saw": "seen", "took": "taken", "did": "done", "ate": "eaten",
               "wrote": "written", "gave": "given", "broke": "broken"}
# Before these, a past participle is right ("had gone"), so the swap wouldn't be a mistake.
AUXILIARIES = {"have", "has", "had", "was", "were", "be", "been", "is", "are", "am", "i've", "we've",
               "they've", "you've", "he's", "she's", "it's"}
AGREEMENT = {"is": "are", "are": "is", "was": "were", "were": "was", "has": "have", "have": "has",
             "doesn't": "don't", "don't": "doesn't"}


def _replace(sentence: str, start: int, end: int, new: str) -> Tuple[str, int]:
    return sentence[:start] + new + sentence[end:], start


def _participle(sentence: str, rng: random.Random) -> Optional[Tuple[str, int]]:
    words = locate_words(sentence)
    spots = [(i, w, s, e) for i, (w, s, e) in enumerate(words)
             if w.lower() in PARTICIPLES and (i == 0 or words[i - 1][0].lower() not in AUXILIARIES)]
    if not spots:
        return None
    _, w, s, e = rng.choice(spots)
    return _replace(sentence, s, e, PARTICIPLES[w.lower()])


def _agreement(sentence: str, rng: random.Random) -> Optional[Tuple[str, int]]:
    spots = [(w, s, e) for w, s, e in locate_words(sentence) if w.lower() in AGREEMENT]
    if not spots:
        return None
    w, s, e = rng.choice(spots)
    new = AGREEMENT[w.lower()]
    return _replace(sentence, s, e, new.capitalize() if w[0].isupper() else new)


def _article(sentence: str, rng: random.Random) -> Optional[Tuple[str, int]]:
    spots = [m for m in re.finditer(r"\b(a|an|A|An)\b(?= \w)", sentence)]
    if not spots:
        return None
    m = rng.choice(spots)
    new = {"a": "an", "an": "a", "A": "An", "An": "A"}[m.group()]
    return _replace(sentence, m.start(), m.end(), new)


def _pointer(sentence: str, at: int, source: str, kind: str) -> List[Row]:
    """The pointer at the word covering `at`, and that word's mistake type."""
    words = locate_words(sentence)
    i = next(i for i, (_, s, e) in enumerate(words) if e > at)
    return [{"sentence": sentence, "signal": "locate", "expected": f"w{i}", "source": source},
            {"sentence": sentence, "word": words[i][0], "signal": "mistake_type", "expected": kind, "source": source}]


def inject(sentences: List[str], seed: int = 20260926) -> List[Row]:
    """For each correct sentence, one mistake if one fits: a grammar "yes" row and its pointer."""
    rng = random.Random(seed)
    rows = []
    for sentence in sentences:
        kinds = [(_participle, "verb"), (_agreement, "agreement"), (_article, "article")]
        rng.shuffle(kinds)
        for make, kind in kinds:
            made = make(sentence, rng)
            if made and made[0] != sentence:
                wrong, at = made
                rows.append({"sentence": wrong, "signal": "grammar", "expected": "yes", "source": "generated-mistake"})
                rows += _pointer(wrong, at, "generated-mistake", kind)
                break
    return rows


def _pair(wrong: str, right: str, word: str, rows: List[Row], kind: str) -> None:
    rows.append({"sentence": wrong, "signal": "grammar", "expected": "yes", "source": "known-miss"})
    rows += _pointer(wrong, re.search(rf"\b{re.escape(word)}\b", wrong).start(), "known-miss", kind)
    rows.append({"sentence": right, "signal": "grammar", "expected": "no", "source": "known-miss"})


def known_misses(seed: int = 20260926, per_kind: int = 40) -> List[Row]:
    rng = random.Random(seed)
    rows: List[Row] = []

    def some(*lists):
        combos = list(itertools.product(*lists))
        return rng.sample(combos, min(per_kind, len(combos)))

    for s, v in some(["He", "She", "My brother", "The manager", "Our teacher", "My neighbour", "It"],
                     ["like coffee", "want to come", "know the answer", "work on Sundays", "need any help", "eat meat", "look ready"]):
        _pair(f"{s} don't {v}.", f"{s} doesn't {v}.", "don't", rows, "agreement")
    for s, (verb, rest), end in some(["I", "We"], [("meet", "you"), ("see", "you again"), ("hear", "from you"), ("meet", "the team"), ("see", "your new flat")],
                                     [".", " soon.", " next week."]):
        _pair(f"{s} look forward to {verb} {rest}{end}", f"{s} look forward to {verb}ing {rest}{end}", verb, rows, "verb")
    for head, noun, pred in some(["list", "box", "bag", "collection", "pile", "stack"], ["items", "books", "papers", "toys", "letters", "shoes"],
                                 ["too long", "on the table", "ready", "missing", "very heavy"]):
        _pair(f"The {head} of {noun} are {pred}.", f"The {head} of {noun} is {pred}.", "are", rows, "agreement")
    for frame, place in some(["Can you tell me", "Do you know", "Could you tell me"],
                             ["the station", "the bank", "the library", "the nearest hospital", "the post office", "your office", "the exit"]):
        _pair(f"{frame} where is {place}?", f"{frame} where {place} is?", "is", rows, "word_order")
    for s, obj, when in some(["We", "They", "The team", "The managers"], ["the plan", "the budget", "the problem", "your idea", "the new rules"],
                             ["yesterday", "this morning", "at the meeting", "for an hour"]):
        _pair(f"{s} discussed about {obj} {when}.", f"{s} discussed {obj} {when}.", "about", rows, "word_extra")
    return rows


def because_nonsense(seed: int = 20260926) -> List[Row]:
    starts = ["I stayed home", "We left early", "She was happy", "They cancelled the trip", "He called me",
              "I bought a new phone", "We changed the plan"]
    empty = ["because of okay", "because the blue", "because very", "because of yes", "because and then", "because of because"]
    real = ["because it was raining", "because of the traffic", "because she got the job", "because the shop was closed",
            "because I was tired", "because of the holiday"]
    rows = [{"sentence": f"{s} {r}.", "signal": "sense", "expected": "yes", "source": "generated-because"}
            for s, r in itertools.product(starts, empty)]
    rows += [{"sentence": f"{s} {r}.", "signal": "sense", "expected": "no", "source": "generated-because"}
             for s, r in itertools.product(starts, real)]
    random.Random(seed).shuffle(rows)
    return rows
