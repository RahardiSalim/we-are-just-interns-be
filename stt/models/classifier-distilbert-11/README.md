# Text classifier (DistilBERT, 11 labels)

**Provenance unknown and not validated.** This folder was copied from a `temp/` folder that Akmal supplied. Nothing here says what data trained it, how it was evaluated, or what input it expects. Do not use it for decisions about people until the person who trained it has answered those questions.

| | |
|---|---|
| Architecture | `DistilBertForSequenceClassification`, 6 layers, 768 dimensions, 67.0 million parameters, fp32 |
| File | `model.safetensors`, 267,860,252 bytes, plus `config.json`, `tokenizer.json`, `tokenizer_config.json` |
| Problem type | single label (softmax over 11) |
| Tokenizer | `BertTokenizer`, lower-case, **English WordPiece vocabulary of 30,522 tokens** |

Labels (id: name): 0 LOGISTICS, 1 SERVICE_CONFLICT, 2 NON_PARTICIPANT, 3 APPEARANCE_SEXUAL, 4 SEXUAL_EXPLICIT, 5 PERSONAL_PROBING, 6 CONTACT_SOLICIT, 7 INTIMIDATION, 8 INSULT_DEGRADING, 9 REFUSAL, 10 DISTRESS.

## Known problems (measured 2026-11-26)

- **The vocabulary is English.** Only 1 of 20 common Indonesian words ("yang") is a single token, while 15 of 15 common English words are. "saya" becomes `say ##a`. The base is almost certainly `distilbert-base-uncased` fine-tuned on Indonesian text, not an Indonesian model such as IndoBERT, which `contracts/ARCHITECTURE.md` plans.
- **On the 24 sentences of `stt/dialog_script.csv`** (perfect text) it gave 18 the label LOGISTICS and caught 4 of the 9 harassing lines. It missed "Diam aja, saya tau kamu tinggal di mana" (LOGISTICS, 0.98) and never predicted REFUSAL. It labelled one normal goodbye APPEARANCE_SEXUAL (0.66).
- **On ordinary phone conversation between friends** (DataHive sample, 4 conversations, 635 segments) 11.2% of segments got a non-neutral label with probability 0.8 or more, 3.0% at 0.95 and none at 0.99. The sample of alarms looked like greetings and small talk. This is a reading by the authors, not a human label.
- **Stability against speech-to-text errors** (192 ride clips, only 6 distinct non-neutral sentences): with maleo text a non-neutral label survives 83% of the time, with stock tiny 52%.

## Load it

Weights are read from safetensors only:

```python
from transformers import AutoModelForSequenceClassification, AutoTokenizer
tok = AutoTokenizer.from_pretrained("models/classifier", local_files_only=True)
model = AutoModelForSequenceClassification.from_pretrained("models/classifier", local_files_only=True).eval()
```

`training_args.bin` from the original folder is **not** included on purpose: it is a PyTorch pickle, and loading one can execute code. It is not needed to run the model.

## In this repo

The weights are split into `model.safetensors.part-*` (GitHub refuses files over 100 MB). Run `./join.sh` once after pulling: it rebuilds `model.safetensors` and checks its SHA-256. Then load the folder as above, with `--classifier models/classifier-distilbert-11`.
