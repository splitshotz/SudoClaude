"""Train the "Claude" wake word model locally.

openWakeWord models are a small classifier on top of a frozen speech embedding,
so only the classifier gets trained and it takes a few minutes on the CPU.
Positives come from Kokoro's voices (and Chatterbox if it's installed) plus any
real recordings in ~/.local/share/sudoclaude/wake/. Negatives are near-misses,
everyday commands, and recordings of the room itself.

The model only has to be good at not missing the word. Every trigger is
checked against the transcript before anything happens, so a false fire costs
a fraction of a second of CPU and nothing else.
"""

import argparse
import os
import sys
import time

import numpy as np

from .listen import MODELS

RATE = 16000
CLIP = int(RATE * 2.0)
DATA = os.path.join(os.path.dirname(MODELS), "wake")

POSITIVE = ["Claude", "Claude.", "Claude,", "Claude?", "Claude!", "hey Claude", "hey, Claude",
            "okay Claude", "yo Claude", "Claude..."]
NEAR = ["cloud", "cloudy", "clod", "claw", "claws", "clause", "called", "cold", "crowd",
        "loud", "allowed", "applaud", "Claudia", "close", "clothes", "glad", "flawed",
        "Maude", "lord", "card", "code", "laud", "fraud", "plod", "cloth", "Clyde",
        "Claire", "clown", "clock", "clue", "bald", "stalled", "hey cloud", "a cloud",
        "it's cold", "I called", "the crowd"]
SPARING = ["clawed", "Claude's"]
GENERAL = ["open discord", "what time is it", "close this window", "move it to workspace two",
           "can you find the file", "play some music", "turn the volume down", "that's all thanks",
           "hello there", "no thank you", "let me think about it", "the weather is nice",
           "I need to finish this first", "send it over when you can", "nice shot",
           "push left", "he's one shot", "rotate rotate", "did you see that", "what's up",
           "okay so basically", "I'll be right back", "can you hear me", "good game"]


def to16(audio, sr):
    from scipy.signal import resample_poly
    from math import gcd
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != RATE:
        g = gcd(int(sr), RATE)
        audio = resample_poly(audio, RATE // g, int(sr) // g).astype(np.float32)
    peak = float(np.abs(audio).max() or 1.0)
    return audio / peak


def place(word, rng, noise_db=None, end_bias=True):
    clip = np.zeros(CLIP, dtype=np.float32)
    word = word[-CLIP:]
    room = CLIP - len(word)
    if room > 0:
        lo = room * 0.55 if end_bias else 0
        off = int(rng.uniform(lo, room))
    else:
        off = 0
    clip[off:off + len(word)] = word * rng.uniform(0.2, 1.0)
    if noise_db is not None:
        clip += rng.normal(0, 10 ** (noise_db / 20), CLIP).astype(np.float32)
    return np.clip(clip * 32767, -32768, 32767).astype(np.int16)


def speak_kokoro():
    import espeakng_loader
    from kokoro_onnx import Kokoro
    espeakng_loader.make_library_available()
    base = MODELS
    if not os.path.exists(os.path.join(base, "kokoro-v1.0.onnx")):
        base = os.path.expanduser("~/.local/share/relay/models")
    k = Kokoro(os.path.join(base, "kokoro-v1.0.onnx"), os.path.join(base, "voices-v1.0.bin"))
    voices = [v for v in sorted(k.get_voices()) if v[:1] in "abef"]

    def say(text, voice, speed):
        lang = "en-gb" if voice[:1] == "b" else "en-us"
        a, sr = k.create(text, voice=voice, speed=speed, lang=lang)
        return to16(a, sr)
    return say, voices


def speak_chatterbox():
    try:
        import torch
        from chatterbox.tts_turbo import ChatterboxTurboTTS
        m = ChatterboxTurboTTS.from_pretrained(device="cuda" if torch.cuda.is_available() else "cpu")
    except Exception:
        return None

    def say(text):
        with torch.inference_mode():
            w = m.generate(text)
        return to16(w.squeeze().cpu().numpy(), m.sr)
    return say


def wavs(folder):
    import soundfile as sf
    out = []
    if os.path.isdir(folder):
        for name in sorted(os.listdir(folder)):
            if name.endswith(".wav"):
                a, sr = sf.read(os.path.join(folder, name), dtype="float32")
                out.append(to16(a, sr))
    return out


def stretch(a, rng):
    from scipy.signal import resample_poly
    r = rng.uniform(0.88, 1.14)
    return resample_poly(a, 1000, int(1000 * r)).astype(np.float32) if abs(r - 1) > 0.02 else a


def dataset(rng, use_chatterbox=True):
    say, voices = speak_kokoro()
    pos, neg = [], []
    print(f"kokoro: {len(voices)} voices")
    for v in voices:
        for speed in (0.85, 1.0, 1.15):
            for text in rng.choice(POSITIVE, 2, replace=False):
                try:
                    a = say(text, v, speed)
                except Exception:
                    continue
                for _ in range(2):
                    pos.append(place(stretch(a, rng), rng, rng.uniform(-62, -32)))
        for text in rng.choice(NEAR, 10, replace=False):
            try:
                neg.append(place(say(text, v, 1.0), rng, rng.uniform(-62, -32)))
            except Exception:
                pass
        for text in rng.choice(GENERAL, 4, replace=False):
            try:
                neg.append(place(say(text, v, 1.0), rng, rng.uniform(-62, -32), end_bias=False))
            except Exception:
                pass
    for text in SPARING:
        for v in voices[::8]:
            try:
                neg.append(place(say(text, v, 1.0), rng, rng.uniform(-62, -32)))
            except Exception:
                pass

    cb = speak_chatterbox() if use_chatterbox else None
    if cb:
        print("chatterbox: adding expressive takes")
        for _ in range(40):
            try:
                a = cb(str(rng.choice(POSITIVE)))
                for _ in range(3):
                    pos.append(place(stretch(a, rng), rng, rng.uniform(-62, -32)))
            except Exception:
                pass

    real = wavs(DATA)
    for a in real:
        for _ in range(80):
            pos.append(place(stretch(a, rng), rng, rng.uniform(-60, -30)))
    print(f"real recordings: {len(real)}")

    room = wavs(os.path.join(DATA, "room"))
    for a in room:
        for i in range(0, max(1, len(a) - CLIP), CLIP // 2):
            seg = a[i:i + CLIP]
            if len(seg) == CLIP:
                neg.append(np.clip(seg * rng.uniform(0.2, 1.0) * 32767, -32768, 32767).astype(np.int16))
    for _ in range(len(pos) // 4):
        neg.append(place(np.zeros(1, np.float32), rng, rng.uniform(-75, -28)))
    return pos, neg


def features(clips):
    from openwakeword.utils import AudioFeatures
    f = AudioFeatures(inference_framework="onnx")
    out = []
    for c in clips:
        f(c)
        out.append(np.array(f.get_features(16))[0])
        f.reset()
    return np.stack(out).astype(np.float32)


def fit(x, y, epochs=60, seed=0):
    import torch
    import torch.nn as nn
    torch.manual_seed(seed)
    net = nn.Sequential(nn.Flatten(), nn.Linear(16 * 96, 128), nn.ReLU(), nn.Dropout(0.25),
                        nn.Linear(128, 64), nn.ReLU(), nn.Linear(64, 1))
    idx = np.random.default_rng(seed).permutation(len(x))
    cut = int(len(x) * 0.85)
    tr, va = idx[:cut], idx[cut:]
    xt, yt = torch.from_numpy(x[tr]), torch.from_numpy(y[tr]).unsqueeze(1)
    xv, yv = torch.from_numpy(x[va]), y[va]
    w = float((y[tr] == 0).sum() / max(1, (y[tr] == 1).sum()))
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([w]))
    opt = torch.optim.AdamW(net.parameters(), lr=1e-3, weight_decay=1e-4)
    best, best_state = -1, None
    for ep in range(epochs):
        net.train()
        order = torch.randperm(len(xt))
        for s in range(0, len(xt), 64):
            b = order[s:s + 64]
            opt.zero_grad()
            loss_fn(net(xt[b]), yt[b]).backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            p = torch.sigmoid(net(xv)).numpy().ravel() >= 0.5
        tp = float((p & (yv == 1)).sum())
        fp = float((p & (yv == 0)).sum())
        fn = float((~p & (yv == 1)).sum())
        recall = tp / max(1e-9, tp + fn)
        precision = tp / max(1e-9, tp + fp)
        # Recall weighs double: the transcript check catches false fires.
        score = 3 * precision * recall / max(1e-9, precision + 2 * recall)
        if score > best:
            best, best_state = score, {k: v.clone() for k, v in net.state_dict().items()}
        if (ep + 1) % 10 == 0:
            print(f"  epoch {ep + 1:>3}  precision {precision:.3f}  recall {recall:.3f}")
    net.load_state_dict(best_state)
    return net


def export(net, path):
    import torch
    import torch.nn as nn

    class Prob(nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, x):
            return torch.sigmoid(self.inner(x))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    torch.onnx.export(Prob(net).eval(), torch.zeros(1, 16, 96), path, input_names=["x"],
                      output_names=["y"], opset_version=17, dynamo=False)
    print(f"wrote {path}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="sudoclaude-voice train")
    ap.add_argument("--out", default=os.path.join(MODELS, "claude.onnx"))
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--no-chatterbox", action="store_true")
    a = ap.parse_args(argv)
    t = time.time()
    rng = np.random.default_rng(0)
    pos, neg = dataset(rng, not a.no_chatterbox)
    print(f"positives {len(pos)}, negatives {len(neg)}")
    x = features(pos + neg)
    y = np.concatenate([np.ones(len(pos)), np.zeros(len(neg))]).astype(np.float32)
    export(fit(x, y, a.epochs), a.out)
    print(f"done in {time.time() - t:.0f}s")


if __name__ == "__main__":
    sys.exit(main())
