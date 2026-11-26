#!/usr/bin/env bash
# Score the whole pipeline on stt/eval/recordings: transcribe (Python), decide (the app's Dart code), report.
# Needs the models in stt/models/ (see stt/models/README.md) and Flutter. Output: stt/eval/out/report.md
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/eval/out"
mkdir -p "$OUT"
uv run --no-project --python 3.12 --with numpy --with scipy --with soundfile --with pywhispercpp \
  --with torch --with transformers --with safetensors --with silero-vad \
  python eval/score.py transcribe "$@"
(cd ../mobile && EVAL_ASR="$OUT/asr.json" EVAL_ACTIONS="$OUT/actions.json" \
  flutter test test/eval_replay_test.dart >/dev/null)
uv run --no-project --python 3.12 python eval/score.py report
echo "Full report: $OUT/report.md"
