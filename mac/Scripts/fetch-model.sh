#!/usr/bin/env bash
# Download the WhisperKit base.en CoreML model + its tokenizer into Models/ so the app can
# run fully offline (no first-run download). Idempotent. The files are gitignored (large,
# reproducible) — like the Windows app's baked-in speech model.
set -euo pipefail
cd "$(dirname "$0")/.."   # → mac/

MODEL_REPO="argmaxinc/whisperkit-coreml"
MODEL_PATH="openai_whisper-base.en"
TOKENIZER_REPO="openai/whisper-base.en"
DEST="Models/$MODEL_PATH"
SENTINEL="$DEST/TextDecoder.mlmodelc/weights/weight.bin"

if [ -f "$SENTINEL" ] && [ -f "$DEST/tokenizer.json" ]; then
  echo "Model already present at $DEST"
  exit 0
fi

echo "Fetching CoreML model ($MODEL_PATH, ~147 MB)…"
FILES=$(curl -sf "https://huggingface.co/api/models/$MODEL_REPO/tree/main/$MODEL_PATH?recursive=true" \
  | python3 -c "import sys,json;[print(x['path']) for x in json.load(sys.stdin) if x['type']=='file']")
for f in $FILES; do
  echo "  $f"
  curl -sfL --create-dirs -o "Models/$f" "https://huggingface.co/$MODEL_REPO/resolve/main/$f"
done

# Tokenizer lives in the original Whisper repo; placed in the model folder so WhisperKit's
# loadTokenizer finds it locally (it searches modelFolder for tokenizer.json) — no download.
echo "Fetching tokenizer…"
for t in tokenizer.json tokenizer_config.json special_tokens_map.json; do
  echo "  $t"
  curl -sfL --create-dirs -o "$DEST/$t" "https://huggingface.co/$TOKENIZER_REPO/resolve/main/$t"
done

echo "Done: $DEST"
