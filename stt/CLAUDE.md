# stt

Speech-to-text reference pipeline: audio → VAD segments → STT per segment → filters → JSON window (`gosafe.stt.window.v1`) → text views for the classifier. Indonesian, with slang and code-mixing, recorded on noisy motorbike rides. Not deployed: the phones run STT on-device and the backend has no ML libraries (see the root [CLAUDE.md](../CLAUDE.md) and [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md)). Read [README.md](README.md) for layout, commands and benchmark numbers, and [contracts/stt-window.md](../contracts/stt-window.md) for the JSON contract.

## Rules

1. No fine-tuning. We have no training data. Our recordings are a test set only.
2. Do not change the JSON schema (`gosafe.stt.window.v1`) without telling the owner. Update [contracts/stt-window.md](../contracts/stt-window.md) in the same change, and bump the version if a field is removed or its meaning changes.
3. Force language `id`. Keep denoisers off by default.
4. Never put harassment or insult words in the slang map. Keep them as spoken.
5. Low-confidence or empty text is NOT "normal". Keep the status fields and flags.
6. Speaker tags are hints, not facts. No speaker recognition in this module.
7. Report only numbers we measured. Mark estimates as estimates. State how many voices and clips were tested.
8. No new dependencies without asking. The tests must keep running without torch.
9. Never commit audio, recordings or results (`stt/.gitignore`). Synthetic or third-party audio has its own licence; check it first.

## Tests

`python -m pytest -q` from `stt/`. Add a test with every change to masking, flags, segmenting or the window status.
