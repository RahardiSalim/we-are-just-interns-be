#!/usr/bin/env bash
# GitHub refuses files over 100 MB, so model.safetensors (268 MB) is stored in 90 MB parts. Run once after pulling:
#   stt/models/classifier-distilbert-11/join.sh
set -euo pipefail
cd "$(dirname "$0")"
cat model.safetensors.part-* > model.safetensors
shasum -a 256 -c SHA256SUMS
