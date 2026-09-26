<p align="center">
  <img src="app/scripts/AppIcon-1024.png" width="128" alt="Plumb icon">
</p>

<h1 align="center">Plumb</h1>

<p align="center"><b>Just speak. See your mistakes. Get better at English.</b><br>
A private AI English coach for your Mac: talk or type, and Plumb catches your mistakes live, on your Mac.<br>
Free and open source, forever. · <a href="https://plumbapp.vercel.app">plumbapp.vercel.app</a></p>

<p align="center"><b>Install:</b> paste this into Terminal and press Return</p>

```bash
curl -fsSL https://plumbapp.vercel.app/install.sh | bash
```

<p align="center"><sub>Apple Silicon (M1 or newer) · macOS 14 or newer · free · <a href="install.sh">read the script</a></sub></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/dark-editor.png">
    <img src="docs/screenshots/light-editor.png" alt="A note with grammar mistakes underlined in red, spelling in amber, and a side panel showing 45% correctness">
  </picture>
</p>

---

## Why Plumb

Most tools fix your English for you, so you never learn. Plumb does the opposite: it **shows** you what's off and leaves the fixing to you. Every note becomes practice, and the Progress chart shows you getting better week by week.

- **Just speak.** Click **Speak** and talk naturally. Plumb writes down what you say and checks it, so it even catches the grammar mistakes you make out loud.
- **Or type, and it checks as you go.** Grammar mistakes, sentences that don't read as real English, spelling, capitals and punctuation, all marked the moment you pause.
- **A Correctness score for every note.** One number that tells you how clean your English is, with a short list of what needs a look.
- **Your writing voice.** See the tone, emotion, confidence, clarity and formality of what you write, so an email to your manager doesn't sound like a text to a friend.
- **Progress you can see.** Every note is scored and charted, so you can see yourself improving.
- **Private by design.** The AI model runs on your Mac. No account, no cloud, no tracking. Your notes never leave your computer.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/dark-progress.png">
    <img src="docs/screenshots/light-progress.png" alt="The Progress page: a line chart of each note's correctness over a month, trending upward">
  </picture>
</p>

## What the marks mean

| Mark | Meaning | Example |
|---|---|---|
| Red underline | Likely a grammar mistake | "The results **is** ready." |
| Soft red highlight | Doesn't read as correct English | "…because of okay" |
| Amber dots | Spelling, capitals or punctuation | "wensday", "hello how are you" |

Hover any sentence for its Correctness and voice:

<p align="center">
  <img src="docs/screenshots/light-card.png" alt="Hovering a sentence shows its correctness, sense, tone, emotion, confidence, clarity and formality">
</p>

## Install

Open **Terminal**, paste this and press Return:

```bash
curl -fsSL https://plumbapp.vercel.app/install.sh | bash
```

That's it: Plumb opens when it's done. Run the same command later to update.

The script ([`install.sh`](install.sh)) is short and safe to read first. It checks your Mac, downloads Plumb from this repo's releases, refuses the download unless it matches its published fingerprint, copies Plumb into Applications and opens it. It needs no password and changes no macOS security settings. Your notes are left untouched. Nothing else needs to be installed first, not even on a brand-new Mac.

On first launch Plumb downloads its writing model (about 800 MB) once, with a progress bar. The first time you click **Speak**, it also downloads its voice model (about 130 MB). After that it works completely offline.

**Requirements:** an Apple Silicon Mac (M1 or newer), macOS 14 or newer, and about 2.7 GB of free disk space.

Your notes are plain Markdown files in `~/Library/Application Support/Plumb/Notes` (Settings → Show notes in Finder).

## Privacy

Everything runs on your Mac: the writing model, speech recognition, your notes. There are no accounts, no tracking and no servers. The only network access is the one-time download of the writing and voice models from GitHub.

## How it works

Plumb is built on [Laya](https://github.com/NandhaKishorM/laya), an open-source model that answers typed questions about text in a single pass instead of generating text. That makes it fast enough to run on a laptop CPU. Plumb fine-tunes Laya's English checkpoint to judge writing and asks it about what you write:

- does it contain a grammar mistake?
- does it make sense?
- what is its tone, emotion and formality?
- how confident and how clear is it?

Spelling, capitals and punctuation use the built-in macOS spell checker plus exact rules.

Speech is turned into text by [Whisper](https://github.com/openai/whisper) (base.en), running on the Neural Engine through [WhisperKit](https://github.com/argmaxinc/WhisperKit). Whisper writes down what you actually said, mistakes included, so Plumb can show you the grammar slips you make out loud.

Accuracy of the shipped model, measured on text it never trained on:

| Signal | Test set | Accuracy |
|---|---|---|
| Grammar | CoLA (public) | 82.1% |
| Emotion | DAIR Emotion (public) | 89.8% |
| Sense, tone, formality, confidence, clarity | Hand-drafted English sets | 91–97% (optimistic: drafted like the training data) |

On real learner writing it catches 88% of the sentences experts corrected (JFLEG) and 78% of corrected sentences inside Cambridge exam essays (FCE), and wrongly objects to 7% of correct essay sentences. When it points at the wrong word, it's the word examiners changed about 88% of the time.

Real-world accuracy is lower than these numbers, especially for Sense. Plumb is a learning aid, not an authority.

## Build from source

```bash
git clone https://github.com/nagavineerpasam/plumb.git && cd plumb
python3.12 -m venv .venv && .venv/bin/pip install -e "engine[test]"   # the signal engine
cd app && swift run                                                   # the app (uses the venv above)
```

- **Release build:** `app/scripts/build-release.sh 0.1.0` builds the release disk image and its SHA-256 fingerprint in `dist/` (upload both; the installer checks the fingerprint), with Python and the engine inside the app.
- **Tests:** `swift test` in `app/`, and `pytest` in `engine/`.
- **Retraining:** the model is fine-tuned on Kaggle with `engine/notebooks/writing_signals_finetune_kaggle.ipynb`.

## Credits

- [Laya](https://github.com/NandhaKishorM/laya) by Nanda Kishor M (Apache-2.0).
- [Whisper](https://github.com/openai/whisper) by OpenAI (MIT), run with [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax (MIT).
- Trained with [CoLA](https://nyu-mll.github.io/CoLA/), [DAIR Emotion](https://huggingface.co/datasets/dair-ai/emotion) and [Pavlick formality scores](https://huggingface.co/datasets/osyvokon/pavlick-formality-scores) (CC BY 3.0), plus hand-drafted English sets in `engine/data`.
- Also trained and tested with the [Cambridge Learner Corpus FCE dataset](https://www.cl.cam.ac.uk/research/nl/bea2019st/) (non-commercial research and education use): Yannakoudakis, Helen and Briscoe, Ted and Medlock, Ben, *A New Dataset and Method for Automatically Grading ESOL Texts*, Proceedings of the 49th Annual Meeting of the Association for Computational Linguistics: Human Language Technologies, 2011. Also [BLiMP](https://github.com/alexwarstadt/blimp) (CC BY 4.0) and [JFLEG](https://github.com/keisks/jfleg) (CC BY-NC-SA 4.0, testing only). None of these datasets is included in this repository.

## License

- **Code:** Apache-2.0. See [LICENSE](LICENSE).
- **The writing model** (`plumb-model.zip` on the releases page) is free for **non-commercial use**. It was fine-tuned from Laya on data that includes research-and-education-only datasets (CoLA, DAIR Emotion, Cambridge FCE) and sentences drafted with the help of an AI assistant. It's meant for personal learning, not for building paid products. If you fork Plumb to sell it, retrain the model on data you're licensed to use commercially.
