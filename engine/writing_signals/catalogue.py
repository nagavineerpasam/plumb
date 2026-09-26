"""The single definition of every writing signal, as Laya questions.

The accuracy check, the fine-tuning data builder and the worker all read this module,
so what we measure is exactly what the app shows. Bump CATALOGUE_VERSION on any change.
"""

import re

CATALOGUE_VERSION = "5"

QUESTIONS = {
    "grammar": {
        "type": "noul",
        "instructions": "Does this sentence contain a grammatical mistake?",
    },
    # v2. "yes" means a problem, like grammar: broken phrasing, word salad, a meaningless ending.
    "sense": {
        "type": "noul",
        "instructions": "Does this sentence fail to make sense as natural English, for example broken phrasing, word salad or a meaningless ending?",
    },
    "tone": {
        "type": "choice",
        "instructions": "What is the tone of this sentence?",
        "criteria": {
            "formal": "professional, official, impersonal wording",
            "neutral": "plain, matter-of-fact wording",
            "casual": "relaxed, informal, conversational wording",
            "friendly": "warm, kind, personal wording",
        },
    },
    "formality": {
        "type": "score",
        "instructions": "How formal is this sentence?",
        "criteria": ["informal", "neutral", "formal"],
    },
    "emotion": {
        "type": "choice",
        "instructions": "Which emotion does this sentence express?",
        "criteria": {
            "joy": "happiness, gratitude, excitement, love",
            "anger": "annoyance, frustration, rage",
            "sadness": "disappointment, grief, loneliness",
            "fear": "worry, anxiety, nervousness",
            "surprise": "astonishment, shock, amazement",
            "neutral": "no clear emotion",
        },
    },
    "confidence": {
        "type": "score",
        "instructions": "How confident does the writer sound?",
        "criteria": ["hesitant", "neutral", "assertive"],
    },
    "clarity": {
        "type": "score",
        "instructions": "How clear and easy to understand is this sentence?",
        "criteria": ["confusing", "somewhat clear", "clear"],
    },
}

SIGNALS = tuple(QUESTIONS)

# Flow is asked about a pair of neighbouring sentences, so it has its own question and state.
# "yes" means a problem, like grammar and sense.
FLOW_QUESTION = {
    "type": "noul",
    "instructions": "Does the second sentence fail to follow naturally from the first, for example a sudden topic jump, a contradiction or a broken connection?",
}


# How a sentence pair is shown to the model. Training uses exactly the same format.
FLOW_STATE_FORMAT = "First sentence: {previous}\nSecond sentence: {sentence}"


def flow_state(previous: str, sentence: str) -> str:
    return FLOW_STATE_FORMAT.format(previous=previous, sentence=sentence)


# "Which word is wrong?" is asked only about a sentence already flagged for grammar. Its options
# are the sentence's own words, so the question is built per sentence; training uses this same
# function. Long sentences get no pointer: too many options for the model to weigh well.
LOCATE_INSTRUCTIONS = "Which single word in this sentence is grammatically wrong?"
LOCATE_MAX_WORDS = 30
_WORD = re.compile(r"[\w'’]+")


def locate_words(sentence: str):
    """The sentence's words as (word, start, end), character offsets into the sentence."""
    return [(m.group(), m.start(), m.end()) for m in _WORD.finditer(sentence)]


def locate_question(sentence: str) -> dict:
    words = locate_words(sentence)
    return {"type": "choice", "instructions": LOCATE_INSTRUCTIONS,
            "criteria": {f"w{i}": f"“{w}” (word {i + 1})" for i, (w, _, _) in enumerate(words)}}


# What kind of mistake the marked word is, so Plumb can teach the rule without giving the answer.
# Asked only after the pointer has marked a word; the state shows the sentence and that word.
MISTAKE_TYPES = {
    "verb": "the verb's tense or form is wrong, like 'goes' for 'went', 'gone' for 'went' or 'to meet' for 'to meeting'",
    "agreement": "a word doesn't agree with another, like 'he don't' or 'the list are'",
    "article": "the wrong or an unneeded 'a', 'an' or 'the' (or 'this', 'some')",
    "preposition": "the wrong or an unneeded small linking word like 'in', 'on', 'at', 'to', 'about'",
    "number": "singular or plural is wrong, or a noun that can't be counted",
    "word_order": "the words are in an unusual order",
    "word_missing": "a word is missing before the marked word",
    "word_extra": "the marked word shouldn't be there",
}
MISTAKE_TYPE_QUESTION = {
    "type": "choice",
    "instructions": "What kind of grammar mistake is at the marked word?",
    "criteria": MISTAKE_TYPES,
}
TYPE_STATE_FORMAT = "Sentence: {sentence}\nMarked word: {word}"


def type_state(sentence: str, word: str) -> str:
    return TYPE_STATE_FORMAT.format(sentence=sentence, word=word)
