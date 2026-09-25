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


def test_uses_plumbs_model_when_installed_otherwise_the_english_checkpoint(engine):
    from writing_signals.engine import TRAINED_DIR, default_checkpoint

    results = engine.score(["Please send me the report by Friday."])

    expected = "plumb" if default_checkpoint() == TRAINED_DIR else "english"
    assert results[0]["model"] == expected
    assert engine.device == "cpu"


def test_catalogue_is_versioned():
    assert CATALOGUE_VERSION


def test_grammar_flags_broken_sentence_above_its_correction(engine):
    broken, fixed = engine.score(["She go to school yesterday.", "She went to school yesterday."])

    assert (
        broken["signals"]["grammar"]["distribution"]["yes"]
        > fixed["signals"]["grammar"]["distribution"]["yes"]
    )


def test_every_sentence_gets_a_sense_verdict(engine):
    result = engine.score(["I love cats and I hate dogs because of okay."])[0]

    assert set(result["signals"]["sense"]["distribution"]) == {"yes", "no"}
