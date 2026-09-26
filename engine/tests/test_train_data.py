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


# --- run 3: the "which word" pointer, the validation ban, essay flow pairs ---
from writing_signals.catalogue import locate_question, locate_words
from writing_signals.train_data import fce_rows, sentence_hash


def essay(eid, text, edits):
    """An FCE record: character offsets into `text`, one annotator."""
    return {"id": eid, "text": text, "edits": [[0, [list(e) for e in edits]]]}


def test_the_pointer_options_are_the_sentences_own_words():
    words = locate_words("I have went there, didn't I?")
    assert [w for w, _, _ in words] == ["I", "have", "went", "there", "didn't", "I"]
    q = locate_question("I have went there.")
    assert q["type"] == "choice" and list(q["criteria"]) == ["w0", "w1", "w2", "w3"]
    assert "went" in q["criteria"]["w2"]


def test_an_essay_mistake_becomes_a_grammar_row_and_a_pointer_at_the_corrected_word():
    text = "We met at noon. I have went there twice. It was fun."
    start = text.index("went")
    rows = fce_rows([essay("e1", text, [(start, start + 4, "been", "IV")])], holdout=set())

    grammar = {r["sentence"]: r["expected"] for r in rows if r["signal"] == "grammar"}
    assert grammar == {"We met at noon.": "no", "I have went there twice.": "yes", "It was fun.": "no"}
    [locate] = [r for r in rows if r["signal"] == "locate"]
    assert locate["sentence"] == "I have went there twice."
    assert locate_question(locate["sentence"])["criteria"][locate["expected"]].startswith("“went”")


def test_spelling_punctuation_and_multi_mistake_sentences_get_no_pointer():
    text = "I recieved it yesterday. He go and buy the books."
    s = text.index("recieved"); g = text.index("go"); b = text.index("buy")
    rows = fce_rows([essay("e1", text, [(s, s + 8, "received", "S"), (g, g + 2, "went", "TV"), (b, b + 3, "bought", "TV")])],
                    holdout=set())
    assert [r for r in rows if r["signal"] == "locate"] == []
    # a spelling-only sentence isn't a grammar example either way
    assert "I recieved it yesterday." not in {r["sentence"] for r in rows if r["signal"] == "grammar"}


def test_essay_neighbours_follow_and_strangers_dont():
    rows = fce_rows([essay("e1", "I like tea. It is warm.", []), essay("e2", "The bus was late. We waited.", []),
                     essay("held", "Keep this out. Never train.", [])], holdout={"held"}, rng_seed=1)
    flow = [(r["previous"], r["sentence"], r["expected"]) for r in rows if r["signal"] == "flow"]
    assert ("I like tea.", "It is warm.", "no") in flow and ("The bus was late.", "We waited.", "no") in flow
    assert any(e == "yes" for _, _, e in flow)
    assert all("Keep this out." not in (p, s) and "Never train." not in (p, s) for p, s, _ in flow)


def test_rows_matching_a_validation_sentence_are_dropped_by_hash():
    banned = {sentence_hash("  the RESULTS is ready. ")}
    rows = build([row("The results is ready.", "grammar", "yes"), row("The results are ready.", "grammar", "no")], [],
                 banned_hashes=banned)
    assert [r["sentence"] for r in rows] == ["The results are ready."]


def test_pointer_rows_must_name_one_of_the_sentences_words():
    ok = row("I have went there.", "locate", "w2")
    bad = row("I have gone there.", "locate", "w9")
    assert build([ok, bad], []) == [ok]


from writing_signals.mistakes import inject, known_misses, because_nonsense


def pointed_word(r):
    return locate_words(r["sentence"])[int(r["expected"][1:])][0]


def test_injected_mistakes_point_at_the_word_that_was_changed():
    rows = inject(["We went to the museum and saw an old ship.", "She is a teacher and they are students."], seed=3)
    grammar = [r for r in rows if r["signal"] == "grammar"]
    locate = [r for r in rows if r["signal"] == "locate"]
    assert grammar and all(r["expected"] == "yes" for r in grammar)
    assert len(locate) == len(grammar)
    for g, l in zip(grammar, locate):
        assert g["sentence"] == l["sentence"]
        assert g["sentence"] not in {"We went to the museum and saw an old ship.", "She is a teacher and they are students."}
        assert pointed_word(l) in {"gone", "seen", "a", "an", "are", "is", "was", "were", "has", "have", "doesn't", "don't"}


def test_known_misses_come_with_correct_twins_and_pointers():
    rows = known_misses(seed=1)
    wrong = {r["sentence"] for r in rows if r["signal"] == "grammar" and r["expected"] == "yes"}
    right = {r["sentence"] for r in rows if r["signal"] == "grammar" and r["expected"] == "no"}
    assert any("don't" in s for s in wrong) and any("look forward to meet " in s for s in wrong)
    assert any("doesn't" in s for s in right) and any("look forward to meeting" in s for s in right)
    assert not wrong & right
    for r in rows:
        if r["signal"] == "locate":
            assert pointed_word(r) in {"don't", "meet", "see", "hear", "are", "is", "about"}


def test_because_nonsense_is_a_sense_problem_and_real_reasons_are_fine():
    rows = because_nonsense(seed=1)
    assert {r["signal"] for r in rows} == {"sense"}
    assert any(r["expected"] == "yes" and "because of okay" in r["sentence"] for r in rows)
    assert any(r["expected"] == "no" for r in rows)


def test_pointer_rows_for_sentences_too_long_to_point_in_are_dropped():
    long = " ".join(["word"] * 30) + " goes here."
    assert build([row(long, "locate", "w30")], []) == []


# --- run 4: mistake types and missing-word pointers ---
from writing_signals.catalogue import MISTAKE_TYPES, type_state
from writing_signals.train_data import fce_type


def test_cambridge_codes_map_to_the_eight_learner_types():
    assert fce_type("TV", missing=False) == "tense"
    assert fce_type("FV", missing=False) == fce_type("IV", missing=False) == "verb_form"
    assert fce_type("AGV", missing=False) == fce_type("AGN", missing=False) == "agreement"
    assert fce_type("RD", missing=False) == fce_type("UD", missing=False) == "article"
    assert fce_type("MD", missing=True) == "article_missing"
    assert fce_type("RT", missing=False) == "preposition" and fce_type("MT", missing=True) == "preposition_missing"
    assert fce_type("CN", missing=False) == fce_type("FN", missing=False) == "number"
    assert fce_type("W", missing=False) == "word_order"
    assert fce_type("MV", missing=True) == "word_missing" and fce_type("UA", missing=False) == "word_extra"
    assert fce_type("RN", missing=False) is None and fce_type("S", missing=False) is None  # word choice, spelling
    assert set(MISTAKE_TYPES) >= {"tense", "verb_form", "agreement", "article", "article_missing", "preposition",
                                  "preposition_missing", "number", "word_order", "word_missing", "word_extra"}


def test_a_missing_word_points_at_the_word_after_the_gap_and_gets_its_type():
    text = "I went to shop yesterday."
    gap = text.index("shop")
    rows = fce_rows([essay("e1", text, [(gap, gap, "the ", "MD")])], holdout=set())

    [locate] = [r for r in rows if r["signal"] == "locate"]
    assert pointed_word(locate) == "shop"
    [kind] = [r for r in rows if r["signal"] == "mistake_type"]
    assert kind["expected"] == "article_missing" and kind["word"] == "shop"


def test_type_rows_name_the_marked_word_in_their_state():
    text = "Yesterday I goes to the gym."
    s = text.index("goes")
    rows = fce_rows([essay("e1", text, [(s, s + 4, "went", "TV")])], holdout=set())
    [kind] = [r for r in rows if r["signal"] == "mistake_type"]
    assert kind["expected"] == "tense"
    assert "goes" in type_state(kind["sentence"], kind["word"]) and "Yesterday I goes" in type_state(kind["sentence"], kind["word"])


def test_generated_mistakes_and_known_misses_carry_their_type():
    injected = inject(["We went to the museum and saw an old ship."], seed=3)
    [kind] = [r for r in injected if r["signal"] == "mistake_type"]
    assert kind["expected"] in {"verb_form", "agreement", "article"} and kind["word"] in kind["sentence"]
    misses = {r["sentence"]: r for r in known_misses(seed=1) if r["signal"] == "mistake_type"}
    assert misses["He don't like coffee."]["expected"] == "agreement"
    assert any(r["expected"] == "verb_form" and r["word"] == "meet" for r in misses.values())
    assert any(r["expected"] == "word_order" for r in misses.values())
    assert any(r["expected"] == "word_extra" and r["word"] == "about" for r in misses.values())
