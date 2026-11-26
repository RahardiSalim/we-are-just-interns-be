"""Experiment: train a light Indonesian classifier on synthetic sentences, and test it honestly.

Two tests, because a model tested on sentences from the same generator looks better than it is:
  1. held-out generation rounds of the synthetic data (same generator, different batches);
  2. eval/ride_script.csv (hand-written by someone else, never trained on).

Label schemes:
  11:  the original labels.
  5:   normal | uncomfortable | sexual | threat | victim  (victim = the person being harmed: refusal, distress).

Run from stt/ (Mac: uses the GPU through MPS when available):
  uv run --no-project --python 3.12 --with torch --with transformers --with safetensors --with sentencepiece \
    python eval/train_classifier.py --data <synthetic.csv> --scheme 5 --out models/clf-lite-5
  ... --baseline models/classifier   scores an existing model on the same tests instead of training.
"""

import argparse
import csv
import json
import random
from collections import Counter
from pathlib import Path

import torch

HERE = Path(__file__).resolve().parent
FIVE = {
    "LOGISTICS": "normal", "SERVICE_CONFLICT": "normal", "NON_PARTICIPANT": "normal",
    "PERSONAL_PROBING": "uncomfortable", "CONTACT_SOLICIT": "uncomfortable", "INSULT_DEGRADING": "uncomfortable",
    "APPEARANCE_SEXUAL": "sexual", "SEXUAL_EXPLICIT": "sexual",
    "INTIMIDATION": "threat", "ROUTE_COERCION": "threat",
    "REFUSAL": "victim", "DISTRESS": "victim",
}
# ride_script.csv 'kind' -> truth in each scheme (None: not comparable in that scheme).
SCRIPT_11 = {"logistics": "LOGISTICS", "smalltalk": "LOGISTICS", "service_conflict": "SERVICE_CONFLICT",
             "friendly_swear": "LOGISTICS", "look_alike": "LOGISTICS", "near_miss": "LOGISTICS",
             "insult": "INSULT_DEGRADING", "probing": "PERSONAL_PROBING", "contact": "CONTACT_SOLICIT",
             "appearance": "APPEARANCE_SEXUAL", "explicit": "SEXUAL_EXPLICIT", "intimidation": "INTIMIDATION",
             "distress": "DISTRESS", "refusal": "REFUSAL"}


def script_rows(scheme: str):
    for r in csv.DictReader(open(HERE / "ride_script.csv")):
        lab = SCRIPT_11.get(r["kind"])
        if lab:
            yield r["text"], (lab if scheme == "11" else FIVE[lab]), r["kind"]


def device():
    return "mps" if torch.backends.mps.is_available() else "cpu"


def predict(model, tok, texts, batch=64):
    model.eval()
    out = []
    with torch.no_grad():
        for i in range(0, len(texts), batch):
            enc = tok(texts[i:i + batch], return_tensors="pt", padding=True, truncation=True, max_length=64).to(device())
            out += model(**enc).logits.softmax(-1).cpu().tolist()
    return out


def report(name, labels, pred_probs, truth):
    pred = [labels[max(range(len(p)), key=p.__getitem__)] for p in pred_probs]
    acc = sum(p == t for p, t in zip(pred, truth)) / len(truth)
    per = {}
    for lab in sorted(set(truth)):
        tp = sum(p == t == lab for p, t in zip(pred, truth))
        fp = sum(p == lab != t for p, t in zip(pred, truth))
        fn = sum(t == lab != p for p, t in zip(pred, truth))
        prec, rec = tp / max(1, tp + fp), tp / max(1, tp + fn)
        per[lab] = round(2 * prec * rec / max(1e-9, prec + rec), 2)
    benign = [i for i, t in enumerate(truth) if t in ("normal", "LOGISTICS", "SERVICE_CONFLICT")]
    false_harm = sum(pred[i] not in ("normal", "LOGISTICS", "SERVICE_CONFLICT", "NON_PARTICIPANT") for i in benign)
    line = (f"{name}: accuracy {acc:.0%}, macro-F1 {sum(per.values()) / len(per):.2f}, "
            f"harmless flagged harmful {false_harm}/{len(benign)}")
    print(line)
    print("   per-class F1:", per)
    return {"accuracy": acc, "per_class_f1": per, "false_harm": false_harm, "benign": len(benign), "pred": pred}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--scheme", choices=["11", "5"], default="5")
    ap.add_argument("--base", default="indobenchmark/indobert-lite-base-p1")
    ap.add_argument("--baseline", help="score this existing model folder (11 labels) instead of training")
    ap.add_argument("--out", default="models/clf-lite")
    ap.add_argument("--extra", action="append", default=[],
                    help="extra training CSV with columns text,label5 (5-label scheme only; never used for testing)")
    ap.add_argument("--extra-repeat", type=int, default=3, help="how many times each extra row is seen per epoch")
    ap.add_argument("--epochs", type=int, default=6)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    rows = [r for r in csv.DictReader(open(args.data)) if r["verified_label"] in FIVE]
    label_of = (lambda r: r["verified_label"]) if args.scheme == "11" else (
        lambda r: r.get("label5") or FIVE[r["verified_label"]])
    rounds = sorted({r["round"] for r in rows})
    random.shuffle(rounds)
    test_rounds = set(rounds[: max(1, len(rounds) // 6)])  # whole generation batches held out
    train = [r for r in rows if r["round"] not in test_rounds]
    test = [r for r in rows if r["round"] in test_rounds]
    labels = sorted({label_of(r) for r in rows})
    for path in args.extra:
        assert args.scheme == "5", "--extra rows are in the 5-label scheme"
        more = [{"text": r["text"], "verified_label": None, "label5": r["label5"]} for r in csv.DictReader(open(path))]
        train += more * args.extra_repeat
        print(f"+ {len(more)} extra training rows from {path}")
    print(f"scheme {args.scheme}: {len(train)} train / {len(test)} held-out ({len(test_rounds)} rounds), labels {labels}")
    script = list(script_rows(args.scheme))

    if args.baseline:  # an existing 11-label model, mapped onto the scheme
        tok = AutoTokenizer.from_pretrained(args.baseline)
        model = AutoModelForSequenceClassification.from_pretrained(args.baseline).to(device())
        names = [model.config.id2label[i] for i in range(model.config.num_labels)]

        def as_scheme(probs):
            out = []
            for p in probs:
                agg = Counter()
                for n, v in zip(names, p):
                    agg[n if args.scheme == "11" else FIVE[n]] += v
                out.append([agg[l] for l in labels])
            return out

        report("baseline, held-out synthetic", labels, as_scheme(predict(model, tok, [r["text"] for r in test])),
               [label_of(r) for r in test])
        res = report("baseline, hand-written ride script", labels,
                     as_scheme(predict(model, tok, [t for t, _, _ in script])), [l for _, l, _ in script])
        for (t, truth, kind), p in zip(script, res["pred"]):
            if p != truth:
                print(f"   ✗ {kind:15} want {truth:14} got {p:14} {t}")
        return

    # IndoBERT-lite ships a WordPiece vocab.txt: its authors (IndoNLU) load it with BertTokenizer. The ALBERT
    # tokenizer its config names maps every word to unknown pieces, so all sentences look the same.
    if "indobert-lite" in args.base:
        from transformers import BertTokenizer

        tok = BertTokenizer.from_pretrained(args.base)
    else:
        tok = AutoTokenizer.from_pretrained(args.base)
    model = AutoModelForSequenceClassification.from_pretrained(
        args.base, num_labels=len(labels), id2label=dict(enumerate(labels)),
        label2id={l: i for i, l in enumerate(labels)}).to(device())
    counts = Counter(label_of(r) for r in train)
    weight = torch.tensor([len(train) / (len(labels) * counts[l]) for l in labels], dtype=torch.float).to(device())
    opt = torch.optim.AdamW(model.parameters(), lr=4e-5, weight_decay=0.01)
    lossf = torch.nn.CrossEntropyLoss(weight=weight)
    data = [(r["text"], labels.index(label_of(r))) for r in train]
    for epoch in range(args.epochs):
        model.train()
        random.shuffle(data)
        total = 0.0
        for i in range(0, len(data), 32):
            texts, ys = zip(*data[i:i + 32])
            enc = tok(list(texts), return_tensors="pt", padding=True, truncation=True, max_length=64).to(device())
            loss = lossf(model(**enc).logits, torch.tensor(ys).to(device()))
            opt.zero_grad()
            loss.backward()
            opt.step()
            total += loss.item()
        print(f"epoch {epoch + 1}: loss {total / (len(data) / 32):.3f}", flush=True)

    report("held-out synthetic", labels, predict(model, tok, [r["text"] for r in test]), [label_of(r) for r in test])
    res = report("hand-written ride script", labels, predict(model, tok, [t for t, _, _ in script]),
                 [l for _, l, _ in script])
    for (t, truth, kind), p in zip(script, res["pred"]):
        if p != truth:
            print(f"   ✗ {kind:15} want {truth:14} got {p:14} {t}")
    Path(args.out).mkdir(parents=True, exist_ok=True)
    model.save_pretrained(args.out)
    tok.save_pretrained(args.out)
    (Path(args.out) / "experiment.json").write_text(json.dumps(
        {"base": args.base, "scheme": args.scheme, "extra": args.extra, "labels": labels, "train": len(train), "test": len(test),
         "test_rounds": sorted(test_rounds), "epochs": args.epochs, "seed": args.seed}, indent=1))
    print(f"saved to {args.out}")


if __name__ == "__main__":
    main()
