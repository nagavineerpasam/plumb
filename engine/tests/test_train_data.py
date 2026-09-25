from writing_signals.train_data import build


def row(sentence, signal="tone", expected="formal", source="claude-synthetic"):
    return {"sentence": sentence, "signal": signal, "expected": expected, "source": source}


def test_training_rows_never_overlap_the_test_sets():
    training = [row("Please find the report attached."), row("  please FIND the report   attached. "),
                row("See you at noon!"), row("The meeting is at ten.")]
    test_sentences = ["The meeting is at ten."]

    rows = build(training, test_sentences)

    assert [r["sentence"] for r in rows if "report" in r["sentence"]] == ["Please find the report attached."]
    assert "The meeting is at ten." not in {r["sentence"] for r in rows}
    assert {r["sentence"] for r in rows} == {"Please find the report attached.", "See you at noon!"}


def test_rows_with_labels_outside_the_catalogue_are_rejected():
    rows = build([row("Hi there!", expected="sarcastic"), row("Hi there, friend!", expected="friendly")], [])

    assert [r["expected"] for r in rows] == ["friendly"]


def test_flow_pairs_are_kept_and_guarded_by_pair():
    pair = {"previous": "The report is due.", "sentence": "My cat loves tuna.", "signal": "flow",
            "expected": "yes", "source": "claude-synthetic"}
    same_second_sentence = {**pair, "previous": "It rained all day."}

    rows = build([pair, same_second_sentence], test_sentences=[], test_pairs=[("The report is due.", "My cat loves tuna.")])

    assert rows == [same_second_sentence]
