# Labelled test data

Every example uses one format: `sentence`, `language`, `signal`, `expected`, `source`. The accuracy check (`python -m writing_signals.eval`) loads all three sources below.

| Source | Signal | Where it comes from | Size |
|---|---|---|---|
| `cola` | grammar | CoLA in-domain validation (`nyu-mll/glue`, config `cola`), downloaded at run time | 1,043 |
| `dair` | emotion | DAIR Emotion test split (`dair-ai/emotion`), downloaded at run time | 2,000 |
| `claude-draft` | tone, formality, confidence, clarity, grammar, emotion (neutral only) | `english_draft.jsonl` in this folder | 800 |

These are **test sets only**. Nothing here may be used for fine-tuning. The training data built in ticket 04 must not overlap with them.

## Status: DRAFT, awaiting developer review

Claude drafted `english_draft.jsonl`, and nobody has checked it yet. Until the developer reviews it and applies any fixes, accuracy on this set is **provisional**.

## Label mappings

**CoLA → grammar.** CoLA label `0` (unacceptable) maps to `yes` (has a mistake), and label `1` (acceptable) maps to `no`. About 69% of CoLA validation is acceptable, so answering `no` every time already scores ~0.69. The report prints this majority baseline next to the bar (0.75).

**DAIR Emotion → emotion.**

| DAIR label | Catalogue label |
|---|---|
| sadness | sadness |
| joy | joy |
| love | joy (the catalogue has no "love" label; joy is the closest) |
| anger | anger |
| fear | fear |
| surprise | surprise |

DAIR has **no neutral class**, so every `neutral` prediction on DAIR counts as wrong. The drafted set covers `neutral`.

## The drafted English set

v1 is English only (decided 2026-09-25 to fit 8 GB Macs). The set has 50 sentences per label value:

| Signal | Labels |
|---|---|
| tone | formal, neutral, casual, friendly |
| formality | informal, neutral, formal |
| confidence | hesitant, neutral, assertive |
| clarity | confusing, somewhat clear, clear |
| grammar | yes (has a mistake), no, written as twins: each wrong sentence has a corrected twin |
| emotion | neutral only (DAIR covers the other emotions) |

### Labelling rules

Label each sentence on its own, with no surrounding context. Pick the single most fitting label.

- **tone**
  - `formal`: official or institutional wording. Set phrases ("hereby", "please be advised"), impersonal constructions, distance from the reader.
  - `neutral`: plain statements of fact with no attitude, not addressed warmly or casually.
  - `casual`: relaxed, conversational wording. Slang, contractions and fragments ("gonna", "kinda", "idk"). Relaxed but not especially warm.
  - `friendly`: warm, kind, personal wording aimed at the reader (well wishes, thanks, encouragement, welcomes).
- **formality** (the register, regardless of warmth)
  - `informal`: chat register. Often lowercase, abbreviations, slang, dropped words.
  - `neutral`: standard everyday written language, neither stiff nor slangy.
  - `formal`: elevated, ceremonial or legal-administrative register.
- **confidence** (how sure the writer sounds, not whether they are right)
  - `hesitant`: hedges, qualifiers, apologies, questions used as suggestions ("maybe", "I might be wrong").
  - `neutral`: plain statements with no hedging and no emphasis.
  - `assertive`: commitments, certainty, imperatives, strong recommendations ("I am certain", "we must", "no doubt").
- **clarity**
  - `confusing`: the meaning can't be recovered on a first read. Examples: stacked negatives, unclear pronoun references, nested clauses, empty jargon, circular or contradictory phrasing.
  - `somewhat clear`: the meaning is recoverable but vague. Placeholders like "the thing", missing specifics, hedged details.
  - `clear`: specific and unambiguous. Who, what, when and why are stated where relevant.
- **grammar**
  - `yes`: the sentence contains at least one grammatical mistake (agreement, tense, verb form, pronoun case, word order, article, preposition, plural, double negative). Each wrong sentence has a correct twin labelled `no`. Spelling, punctuation and style alone never count as mistakes.
  - `no`: a native speaker would accept it as grammatical.
- **emotion**: the emotion the writer expresses.
  - `joy`: includes gratitude and love.
  - `anger`: includes annoyance and frustration.
  - `sadness`: includes disappointment and grief.
  - `fear`: includes worry and anxiety.
  - `surprise`
  - `neutral`: purely factual.

### Known weaknesses to check during review

- Tone and formality overlap by design: a `formal` tone sentence is usually `formal` in register too. They are drafted as separate sentences.
- The `confusing` clarity examples are deliberately extreme. Real confusing writing is subtler.
- 50 sentences per label gives roughly ±7 points of noise on per-label accuracy.
