# Text classifier: IndoBERT-lite, 5 labels (experiment, 2026-11-27)

Trained on a laptop as an experiment to replace the 11-label DistilBERT. **Not validated for decisions about people**: one speaker's recordings and a small hand-written test.

| | |
|---|---|
| Base | `indobenchmark/indobert-lite-base-p1` (ALBERT, 11.7M parameters, **Indonesian** WordPiece vocab). Licence per its model card: MIT (check before production) |
| File | `model.safetensors`, 46.8 MB, fp32. PyTorch / Hugging Face format (not ONNX) |
| Labels | `normal`, `sexual`, `threat`, `uncomfortable`, `victim` (refusal or distress from the person being harmed) |
| Training data | The team's synthetic set (`synth_single_sentence_all`, 3,591 sentences, 11 labels mapped to 5; 10 of 60 generation rounds held out) plus `stt/data/classifier_extra.csv` (340 rows: look-alikes, friendly swearing, complaints, slang threats, insults, victim speech) repeated 3x. 6 epochs, AdamW 4e-5, class weights, seed 7. See `experiment.json` |
| Script | `stt/eval/train_classifier.py` in the repo |

## Results

| Test | Old DistilBERT | This model |
|---|---|---|
| Held-out synthetic rounds (same generator: optimistic) | 92% | 98% |
| Hand-written ride lines (same author as the extra data: optimistic) | 59%, 9/36 harmless flagged | 89%, 0/36 harmless flagged |
| One speaker's voice through the whole pipeline (`stt/eval/run.sh`, with keywords) | 14/16 danger caught, 3/42 false alarms | 15/16 caught, 1/42 false alarms |

## Load it

**Use `BertTokenizer`** (saved that way here, so `AutoTokenizer` also picks it). The base model's config names an ALBERT tokenizer that turns every Indonesian word into unknown pieces: every sentence then looks the same and training learns nothing.

```python
from transformers import AutoModelForSequenceClassification, AutoTokenizer
tok = AutoTokenizer.from_pretrained("models/clf-lite-5x", local_files_only=True)
model = AutoModelForSequenceClassification.from_pretrained("models/clf-lite-5x", local_files_only=True).eval()
```

The app maps the labels in `mobile/lib/services/dev_ml.dart` (`devLabelMap`). Run with the laptop service: `dev_server.py --classifier models/clf-lite-5x`.
