"""The single definition of every writing signal, as Laya questions.

The accuracy check, the fine-tuning data builder and the worker all read this module,
so what we measure is exactly what the app shows. Bump CATALOGUE_VERSION on any change.
"""

CATALOGUE_VERSION = "1"

QUESTIONS = {
    "grammar": {
        "type": "noul",
        "instructions": "Does this sentence contain a grammatical mistake?",
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
