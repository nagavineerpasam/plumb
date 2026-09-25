<p align="center">
  <img src="app/scripts/AppIcon-1024.png" width="128" alt="Plumb icon">
</p>

<h1 align="center">Plumb</h1>

<p align="center">A private notes app that shows you, sentence by sentence, how well you write English.<br>
Grammar, sense, spelling, tone and confidence, live as you type or speak. Nothing leaves your Mac.</p>

---

## Install (Apple Silicon Mac, macOS 14 or newer)

1. **Download** `Plumb-0.1.0-arm64.dmg` from the [latest release](https://github.com/nagavineerpasam/plumb-releases/releases/latest).
2. **Open** the downloaded file and **drag Plumb onto Applications**.
3. **Open Plumb** from Applications. The first time, macOS stops it because it isn't from the App Store:
   - click **Done** on the warning,
   - open **System Settings → Privacy & Security**,
   - scroll down to *"Plumb" was blocked* and click **Open Anyway**, then **Open**.

   You only do this once. (Plumb isn't signed with a paid Apple developer certificate yet.)

On first launch Plumb downloads its writing model (about 800 MB) once, with a progress bar. After that it works completely offline.

**Requirements:** an Apple Silicon Mac (M1 or newer), macOS 14 or newer, and about 2.5 GB of free disk space. Speaking into notes needs macOS 26.

## What it does

As you write, Plumb checks each sentence the moment you pause:

| Mark | Meaning |
|---|---|
| Red underline | Likely a grammar mistake ("tech people **is** dumb") |
| Soft red highlight | Doesn't read as correct English ("…because of okay") |
| Amber dots | Spelling, capitals or punctuation ("wensday", "hello how are you") |

Hover any sentence to see its **Correctness %**, tone, emotion, confidence, clarity and formality. The side panel shows the whole note's Correctness, everything that needs a look, and your writing voice. Plumb never rewrites your text: it shows what's wrong so you learn to fix it yourself.

- **Speak instead of type:** click **Speak** by the note title (or press ⌥⌘D). Your words appear at the cursor and are checked like typed text. Recognition runs on your Mac.
- **Progress:** the Progress page charts each note's Correctness over time, so you can see yourself improving.
- **Your notes are plain files** in `~/Documents/Plumb`, one Markdown file per note.

## Privacy

Everything runs on your Mac: the writing model, speech recognition, your notes. There are no accounts, no tracking and no servers. The only network access is the one-time model download.

## How it works

Plumb is built on [Laya](https://github.com/NandhaKishorM/laya), an open-source model that answers typed questions about text in a single pass instead of generating text. Plumb fine-tunes Laya's English checkpoint to judge writing, and asks it about each sentence:

- does it contain a grammar mistake?
- does it make sense?
- what is its tone, emotion and formality?
- how confident and how clear is it?

Spelling, capitals and punctuation use the built-in macOS spell checker plus exact rules.

Accuracy of the shipped model, measured on text it never trained on:

| Signal | Test set | Accuracy |
|---|---|---|
| Grammar | CoLA (public) | 77.5% |
| Emotion | DAIR Emotion (public) | 90.6% |
| Sense, tone, formality, confidence, clarity | Hand-drafted English sets | 90–97% (optimistic: drafted like the training data) |

Real-world accuracy is lower than these numbers, especially for Sense. Plumb is a learning aid, not an authority.

## Build from source

```bash
git clone https://github.com/nagavineerpasam/plumb.git && cd plumb      # private: needs access
python3.12 -m venv .venv && .venv/bin/pip install -e "engine[test]"   # the signal engine
cd app && swift run                                                   # the app (uses the venv above)
```

- **Release build:** `app/scripts/build-release.sh 0.1.0` builds `dist/Plumb.app` and `dist/Plumb-0.1.0-arm64.dmg` with Python and the engine inside.
- **Tests:** `swift test` in `app/`, and `pytest` in `engine/`.
- **Retraining:** the model is fine-tuned on Kaggle with `engine/notebooks/writing_signals_finetune_kaggle.ipynb`.

## Credits

- [Laya](https://github.com/NandhaKishorM/laya) by Nanda Kishor M (Apache-2.0).
- Trained with [CoLA](https://nyu-mll.github.io/CoLA/), [DAIR Emotion](https://huggingface.co/datasets/dair-ai/emotion) and [Pavlick formality scores](https://huggingface.co/datasets/osyvokon/pavlick-formality-scores) (CC BY 3.0), plus hand-drafted English sets in `engine/data`.

## License

Apache-2.0. See [LICENSE](LICENSE).
