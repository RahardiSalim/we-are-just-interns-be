"""Make noisy, phone-like test audio from clean speech.

Why: we have no real in-ride recordings. This script simulates a motorbike
ride by mixing noise into clean speech at several SNR levels (SNR = signal to
noise ratio in dB; lower means noisier) and by imitating a phone microphone.

Usage:
  python make_noisy_eval.py --speech_dir clean/ --out_dir noisy/ \
      --snrs 20 10 5 0 --modes handlebar pocket
  (add --noise_dir noise/ to use real noise files; otherwise synthetic
   motorbike-like noise is generated)

Expects clean/ to hold wav/flac files, and optionally clean/manifest.csv with
columns: file,text  (the reference transcript). The output manifest.csv keeps
the text and adds snr and mode, so benchmark_stt.py can group results.
"""
import argparse
import csv
import glob
import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 16000


def load_mono_16k(path):
    x, sr = sf.read(path, dtype="float32", always_2d=False)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        g = np.gcd(sr, SR)
        x = signal.resample_poly(x, SR // g, sr // g).astype("float32")
    return x


def synthetic_motor_noise(n, rng):
    """Engine hum (low harmonics) + wind (slowly changing filtered noise) + road hiss."""
    t = np.arange(n) / SR
    f0 = rng.uniform(35, 70)  # engine base frequency in Hz
    rpm_wobble = 1 + 0.05 * np.sin(2 * np.pi * rng.uniform(0.2, 0.8) * t)
    engine = sum(
        (1.0 / k) * np.sin(2 * np.pi * f0 * k * np.cumsum(rpm_wobble) / SR)
        for k in range(1, 9)
    )
    wind = rng.standard_normal(n)
    b, a = signal.butter(2, [80, 1500], btype="band", fs=SR)
    wind = signal.lfilter(b, a, wind)
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(0.1, 0.4) * t + rng.uniform(0, 6))
    hiss = rng.standard_normal(n)
    b, a = signal.butter(2, 3000, btype="low", fs=SR)
    hiss = signal.lfilter(b, a, hiss) * 0.3
    noise = engine / np.std(engine) + wind / np.std(wind) + hiss / np.std(hiss)
    return noise.astype("float32")


def crop_or_loop(noise, n, rng):
    if len(noise) < n:
        noise = np.tile(noise, int(np.ceil(n / len(noise))))
    start = rng.integers(0, len(noise) - n + 1)
    return noise[start:start + n]


def mix_at_snr(speech, noise, snr_db):
    p_s = np.mean(speech ** 2) + 1e-12
    p_n = np.mean(noise ** 2) + 1e-12
    scale = np.sqrt(p_s / (p_n * 10 ** (snr_db / 10)))
    return speech + scale * noise


def phone_mic(x, mode, rng):
    """Rough phone microphone effects.
    handlebar: phone on the handlebar, wind and a bit of clipping.
    pocket: phone in a pocket or bag, voice is muffled (low-pass) and quieter.
    """
    if mode == "pocket":
        b, a = signal.butter(4, 2500, btype="low", fs=SR)
        x = signal.lfilter(b, a, x) * rng.uniform(0.3, 0.6)
    else:
        b, a = signal.butter(2, 100, btype="high", fs=SR)
        x = signal.lfilter(b, a, x)
        x = np.clip(x * rng.uniform(1.0, 1.8), -0.95, 0.95)
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speech_dir", required=True)
    ap.add_argument("--out_dir", required=True)
    ap.add_argument("--noise_dir", default=None)
    ap.add_argument("--snrs", type=float, nargs="+", default=[20, 10, 5, 0])
    ap.add_argument("--modes", nargs="+", default=["handlebar", "pocket"])
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    os.makedirs(args.out_dir, exist_ok=True)

    texts = {}
    mpath = os.path.join(args.speech_dir, "manifest.csv")
    if os.path.exists(mpath):
        with open(mpath, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                texts[row["file"]] = row["text"]

    speech_files = sorted(
        glob.glob(os.path.join(args.speech_dir, "*.wav"))
        + glob.glob(os.path.join(args.speech_dir, "*.flac"))
    )
    noise_files = []
    if args.noise_dir:
        noise_files = sorted(
            glob.glob(os.path.join(args.noise_dir, "*.wav"))
            + glob.glob(os.path.join(args.noise_dir, "*.flac"))
        )

    rows = []
    for sp in speech_files:
        base = os.path.basename(sp)
        speech = load_mono_16k(sp)
        speech = speech / (np.max(np.abs(speech)) + 1e-9) * 0.7
        for snr in args.snrs:
            for mode in args.modes:
                if noise_files:
                    noise = crop_or_loop(load_mono_16k(noise_files[rng.integers(len(noise_files))]), len(speech), rng)
                else:
                    noise = synthetic_motor_noise(len(speech), rng)
                noisy = mix_at_snr(speech, noise, snr)
                noisy = phone_mic(noisy, mode, rng)
                noisy = noisy / (np.max(np.abs(noisy)) + 1e-9) * 0.9
                name = f"{os.path.splitext(base)[0]}__snr{int(snr)}__{mode}.wav"
                sf.write(os.path.join(args.out_dir, name), noisy, SR)
                rows.append({"file": name, "text": texts.get(base, ""), "snr": snr, "mode": mode})

    with open(os.path.join(args.out_dir, "manifest.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["file", "text", "snr", "mode"])
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {len(rows)} files to {args.out_dir}")


if __name__ == "__main__":
    main()
