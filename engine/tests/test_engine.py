import pytest

from writing_signals import CATALOGUE_VERSION, SIGNALS, SignalEngine


@pytest.fixture(scope="module")
def engine():
    return SignalEngine()


def test_scores_every_signal_for_each_sentence(engine):
    results = engine.score(["I think we should maybe meet next week, if that's okay."])

    assert len(results) == 1
    signals = results[0]["signals"]
    assert set(signals) == set(SIGNALS)
    for name, signal in signals.items():
        assert signal["value"] in signal["distribution"], name
        assert sum(signal["distribution"].values()) == pytest.approx(1.0, abs=1e-3), name


def test_routes_by_language(engine):
    results = engine.score([
        "Please send me the report by Friday.",
        "Bitte schicken Sie mir den Bericht bis Freitag.",
        "कृपया शुक्रवार तक मुझे रिपोर्ट भेजें।",
    ])

    assert [r["model"] for r in results] == ["english", "multilingual", "multilingual"]


def test_catalogue_is_versioned():
    assert CATALOGUE_VERSION


def test_grammar_flags_broken_sentence_above_its_correction(engine):
    broken, fixed = engine.score(["She go to school yesterday.", "She went to school yesterday."])

    assert (
        broken["signals"]["grammar"]["distribution"]["yes"]
        > fixed["signals"]["grammar"]["distribution"]["yes"]
    )
