"""Export the text classifier to ONNX for the phone, and check it still agrees with the original.

Only the word-embedding table is int8. Measured on 735 sentences (2026-11-27): that file is 35.4 MB with no label or
>=0.9 decision changed; full int8 is 12.2 MB but changed 10 decisions, and the app's rules cut at 0.9.

Writes <out>/model.onnx, <out>/vocab.txt (the WordPiece vocabulary the app's Dart tokenizer reads) and
<out>/labels.json, then compares int8 against the PyTorch model on eval/ride_script.csv and the extra set.
The app reads input_ids / attention_mask / token_type_ids (int64, max 64 tokens) and gets logits.

Run from stt/:
  uv run --no-project --python 3.12 --with torch --with transformers --with safetensors --with onnx \
    --with onnxruntime --with onnxscript python eval/export_onnx.py models/clf-lite-5x --out models/clf-lite-5x-onnx
"""

import argparse
import csv
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from onnxruntime.quantization.shape_inference import quant_pre_process
from transformers import AutoModelForSequenceClassification, BertTokenizer

HERE = Path(__file__).resolve().parent
MAX_LEN = 64


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    tok = BertTokenizer.from_pretrained(args.model)  # see train_classifier.py: not the ALBERT tokenizer
    model = AutoModelForSequenceClassification.from_pretrained(args.model).eval()
    labels = [model.config.id2label[i] for i in range(model.config.num_labels)]

    enc = tok(["contoh kalimat"], return_tensors="pt", padding="max_length", max_length=MAX_LEN, truncation=True)
    fp32 = out / "model.fp32.onnx"
    names = ["input_ids", "attention_mask", "token_type_ids"]
    torch.onnx.export(model, tuple(enc[n] for n in names), str(fp32), input_names=names, output_names=["logits"],
                      dynamic_axes={n: {0: "batch", 1: "seq"} for n in names} | {"logits": {0: "batch"}},
                      opset_version=17, dynamo=False)
    int8 = out / "model.onnx"
    # ALBERT shares one layer's weights across all 12 layers; pre-processing keeps them shared in the output.
    prep = out / "model.prep.onnx"
    quant_pre_process(str(fp32), str(prep), skip_symbolic_shape=True)
    quantize_dynamic(str(prep), str(int8), weight_type=QuantType.QInt8, op_types_to_quantize=["Gather"])
    fp32.unlink()
    prep.unlink()
    (out / "vocab.txt").write_text("\n".join(t for t, _ in sorted(tok.vocab.items(), key=lambda kv: kv[1])) + "\n")
    (out / "labels.json").write_text(json.dumps(labels))

    texts = [r["text"] for r in csv.DictReader(open(HERE / "ride_script.csv"))]
    texts += [r["text"] for r in csv.DictReader(open(HERE.parent / "data" / "classifier_extra.csv"))]
    sess = ort.InferenceSession(str(int8))
    agree, worst = 0, 0.0
    for t in texts:
        e = tok([t], return_tensors="np", max_length=MAX_LEN, truncation=True)
        q = sess.run(None, {n: e[n].astype(np.int64) for n in names})[0][0]
        q = np.exp(q - q.max()); q /= q.sum()
        with torch.no_grad():
            p = model(**tok([t], return_tensors="pt", max_length=MAX_LEN, truncation=True)).logits.softmax(-1)[0].numpy()
        agree += q.argmax() == p.argmax()
        worst = max(worst, float(abs(q - p).max()))
    print(f"{int8.name} {int8.stat().st_size / 1e6:.1f} MB; same label on {agree}/{len(texts)}; largest score change {worst:.3f}")


if __name__ == "__main__":
    main()
