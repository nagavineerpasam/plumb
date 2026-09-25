#!/bin/bash
# Builds plumb-voice.zip: Whisper base.en compiled for Core ML (WhisperKit's build, MIT) plus the
# tokenizer files, so Plumb's voice runs fully offline. Files sit at the top level of the zip.
# Usage: app/scripts/build-voice-model.sh     Output: dist/plumb-voice.zip
# Upload: gh release upload <tag> dist/plumb-voice.zip --clobber
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dist/voice"
MODEL="https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-base.en"
TOKENIZER="https://huggingface.co/openai/whisper-base.en/resolve/main"

rm -rf "$OUT" && mkdir -p "$OUT"
for part in AudioEncoder MelSpectrogram TextDecoder; do
  for file in analytics/coremldata.bin coremldata.bin metadata.json model.mil weights/weight.bin model.mlmodel; do
    # MelSpectrogram has no model.mlmodel; everything else must download.
    if [ "$part/$file" = "MelSpectrogram/model.mlmodel" ]; then continue; fi
    mkdir -p "$OUT/$part.mlmodelc/$(dirname "$file")"
    curl -fsSL --retry 3 -o "$OUT/$part.mlmodelc/$file" "$MODEL/$part.mlmodelc/$file"
  done
done
for file in config.json generation_config.json; do
  curl -fsSL --retry 3 -o "$OUT/$file" "$MODEL/$file"
done
for file in tokenizer.json tokenizer_config.json vocab.json merges.txt added_tokens.json special_tokens_map.json normalizer.json; do
  curl -fsSL --retry 3 -o "$OUT/$file" "$TOKENIZER/$file"
done

rm -f "$ROOT/dist/plumb-voice.zip"
(cd "$OUT" && zip -qr -X "$ROOT/dist/plumb-voice.zip" .)
echo "✓ $(du -sh "$ROOT/dist/plumb-voice.zip" | cut -f1) dist/plumb-voice.zip"
