from writing_signals.eval.ship import passes, pick, score


def test_a_case_counts_as_flagged_when_any_of_its_sentences_is():
    cases = [
        {"set": "jfleg", "label": "grammar", "sentences": ["He go home.", "It was late."]},
        {"set": "jfleg", "label": "correct", "sentences": ["We went home."]},
        {"set": "fce", "label": "grammar", "sentences": ["She have a car."]},
        {"set": "fce", "label": "correct", "sentences": ["It was fun."]},
        {"set": "blimp", "label": "correct", "sentences": ["Actors tour stores."]},
    ]
    probs = {"He go home.": (0.9, 0.1), "It was late.": (0.1, 0.1), "We went home.": (0.1, 0.1),
             "She have a car.": (0.2, 0.1), "It was fun.": (0.1, 0.6), "Actors tour stores.": (0.6, 0.2)}
    m = score(cases, lambda text: probs[text], pointer_cases=[])
    assert m["jfleg_caught"] == 1.0 and m["jfleg_false_alarms"] == 0.0
    assert m["fce_caught"] == 0.0 and m["fce_false_alarms"] == 1.0  # sense >= 0.5 is a flag too
    assert m["blimp_false_alarms"] == 1.0


def test_the_pointer_and_type_thresholds_are_the_lowest_reaching_ninety_percent():
    pointer_cases = [{"hit": True, "p": 0.95, "type": "verb", "pred": "verb", "tp": 0.9},
                     {"hit": True, "p": 0.9, "type": "verb", "pred": "verb", "tp": 0.8},
                     {"hit": False, "p": 0.7, "type": "verb", "pred": "agreement", "tp": 0.95},
                     {"hit": True, "p": 0.6, "type": "article", "pred": "preposition", "tp": 0.4}]
    m = score([], lambda t: (0, 0), pointer_cases=pointer_cases)
    assert m["pointer_threshold"] == 0.9 and m["pointer_right"] == 1.0
    assert m["type_threshold"] <= 0.8 and m["type_right"] >= 0.9


def test_only_candidates_at_least_as_good_as_the_live_model_pass_and_the_best_catch_wins():
    floors = {"fce_caught": 0.784, "jfleg_caught": 0.884, "fce_false_alarms": 0.074, "blimp_false_alarms": 0.185}
    good = {"fce_caught": 0.80, "jfleg_caught": 0.89, "fce_false_alarms": 0.07, "blimp_false_alarms": 0.18,
            "pointer_right": 0.91, "type_right": 0.92, "signals_pass": True}
    better = {**good, "fce_caught": 0.82}
    worse = {**good, "fce_caught": 0.70}
    assert passes(good, floors) and not passes(worse, floors)
    assert not passes({**good, "type_right": 0.88}, floors)
    assert pick({"a": good, "b": better, "c": worse}, floors) == "b"
    assert pick({"c": worse}, floors) is None


def test_a_pointer_hits_the_corrected_words_or_for_a_missing_word_the_word_after_the_gap():
    from writing_signals.eval.ship import pointer_hit
    sentence = "🙂 I have went there."
    at = sentence.index("went")
    utf16 = lambda i: len(sentence[:i].encode("utf-16-le")) // 2
    found = {"start": utf16(at), "end": utf16(at + 4)}
    assert pointer_hit({"sentence": sentence, "span": [at, at + 4], "missing": False, "target_span": [at, at + 4]}, found)
    assert not pointer_hit({"sentence": sentence, "span": [2, 3], "missing": False, "target_span": [2, 3]}, found)
    gap = sentence.index("there")
    after = {"start": utf16(gap), "end": utf16(gap + 5)}
    assert pointer_hit({"sentence": sentence, "span": [gap, gap], "missing": True, "target_span": [gap, gap + 5]}, after)
