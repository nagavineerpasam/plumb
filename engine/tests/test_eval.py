from writing_signals.eval.check import flow_accuracy, measure_latency, predict, summarise


class StubEngine:
    """Answers from a fixed table, standing in for Laya at the engine boundary."""

    def __init__(self, answers):
        self.answers = answers  # sentence -> (model, value, yes_probability)

    def score(self, sentences):
        out = []
        for s in sentences:
            model, value, yes = self.answers[s]
            distribution = {"yes": yes, "no": 1 - yes} if yes is not None else {value: 1.0}
            out.append({"model": model, "signals": {
                name: {"value": value, "distribution": distribution} for name in
                ("grammar", "tone", "formality", "emotion", "confidence", "clarity")}})
        return out


def ex(sentence, signal, expected, source, language="en"):
    return {"sentence": sentence, "language": language, "signal": signal, "expected": expected, "source": source}


def test_signal_passes_only_when_accuracy_on_its_bar_source_reaches_the_bar():
    engine = StubEngine({
        "a": ("english", "formal", None), "b": ("english", "formal", None),
        "c": ("english", "casual", None), "d": ("multilingual", "formal", None),
    })
    rows = predict(engine, [
        ex("a", "tone", "formal", "claude-draft"), ex("b", "tone", "formal", "claude-draft"),
        ex("c", "tone", "formal", "claude-draft"), ex("d", "tone", "casual", "claude-draft", "de"),
    ])

    tone = summarise(rows)["tone"]

    assert tone["accuracy"] == 0.5          # 2 of 4 right
    assert tone["pass"] is False            # bar is 0.70
    assert tone["by_language"]["en"] == {"n": 3, "accuracy": 2 / 3}
    assert tone["by_language"]["de"] == {"n": 1, "accuracy": 0.0}
    assert tone["majority_baseline"] == 0.75


def test_grammar_bar_is_judged_on_cola_and_reports_best_threshold():
    engine = StubEngine({
        "bad1": ("english", "no", 0.30), "bad2": ("english", "no", 0.20),
        "ok1": ("english", "no", 0.05), "ok2": ("english", "no", 0.10),
        "de": ("multilingual", "yes", 0.9),
    })
    rows = predict(engine, [
        ex("bad1", "grammar", "yes", "cola"), ex("bad2", "grammar", "yes", "cola"),
        ex("ok1", "grammar", "no", "cola"), ex("ok2", "grammar", "no", "cola"),
        ex("de", "grammar", "no", "claude-draft", "de"),
    ])

    grammar = summarise(rows)["grammar"]

    assert grammar["n"] == 4 and grammar["accuracy"] == 0.5   # argmax says "no" for all four
    assert grammar["best_threshold"]["accuracy"] == 1.0       # any cut in (0.10, 0.20] separates them
    assert 0.10 < grammar["best_threshold"]["threshold"] <= 0.20
    assert grammar["by_source"]["claude-draft"] == {"n": 1, "accuracy": 0.0}


def test_latency_reports_per_call_percentiles():
    engine = StubEngine({s: ("english", "x", None) for s in ["a", "b", "c"]})

    latency = measure_latency(engine, ["a", "b", "c"])

    assert latency["calls"] == 3
    assert 0 <= latency["p50_ms"] <= latency["p95_ms"]


def test_flow_is_judged_on_pairs_against_its_bar():
    class FlowStub:
        def flow(self, pairs):
            return [{"value": "yes" if "tuna" in s else "no", "distribution": {}} for _, s in pairs]

    pairs = [
        {"previous": "The report is due.", "sentence": "My cat loves tuna.", "expected": "yes"},
        {"previous": "The report is due.", "sentence": "I will send it Thursday.", "expected": "no"},
        {"previous": "It rained.", "sentence": "So we stayed in.", "expected": "no"},
        {"previous": "It rained.", "sentence": "Therefore it was sunny.", "expected": "yes"},
    ]

    flow = flow_accuracy(FlowStub(), pairs)

    assert flow["n"] == 4 and flow["accuracy"] == 0.75
    assert flow["pass"] is True  # bar is 0.75
