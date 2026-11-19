import argparse
import os
import sys
import time

import numpy as np

from .listen import MODELS

SAMPLE_TEXT = ("Hey. Discord's open on workspace three, and I muted the general channel "
               "like you asked. Anything else?")


def setup():
    os.makedirs(MODELS, exist_ok=True)
    import openwakeword.utils as owu
    print("openWakeWord feature models")
    owu.download_models(model_names=["__none__"])

    dest = os.path.join(MODELS, "hey_claude.onnx")
    if not os.path.exists(dest):
        print("hey-claude wake model")
        try:
            from huggingface_hub import hf_hub_download, list_repo_files
            files = [f for f in list_repo_files("gdiamos/hey-claude") if f.endswith(".onnx")]
            if files:
                src = hf_hub_download("gdiamos/hey-claude", files[0])
                import shutil
                shutil.copy(src, dest)
        except Exception as e:
            print("  skipped:", e)

    for name, url in (("kokoro-v1.0.onnx", "https://github.com/thewh1teagle/kokoro-onnx/releases/"
                       "download/model-files-v1.0/kokoro-v1.0.onnx"),
                      ("voices-v1.0.bin", "https://github.com/thewh1teagle/kokoro-onnx/releases/"
                       "download/model-files-v1.0/voices-v1.0.bin")):
        path = os.path.join(MODELS, name)
        relay = os.path.expanduser(f"~/.local/share/relay/models/{name}")
        if os.path.exists(path):
            continue
        if os.path.exists(relay):
            import shutil
            shutil.copy(relay, path)
            continue
        print("downloading", name)
        import urllib.request
        urllib.request.urlretrieve(url, path + ".part")
        os.rename(path + ".part", path)

    print("speech recognition model")
    from .listen import Transcriber
    Transcriber()
    print("voice activity model")
    from .listen import Vad
    Vad()
    try:
        from .tts import Chatterbox
        print("chatterbox voice")
        Chatterbox()
    except Exception as e:
        print("  chatterbox not available:", e)
    print("done")


def record(count):
    from .audio import Mic, pick_input
    from .train import DATA
    import soundfile as sf
    os.makedirs(DATA, exist_ok=True)
    mic = Mic(pick_input(None))
    mic.start()
    time.sleep(0.5)
    have = len([n for n in os.listdir(DATA) if n.endswith(".wav")])
    for i in range(count):
        input(f"[{i + 1}/{count}] press Enter, then say \"Claude\" once")
        mic.drain()
        chunks = [mic.read() for _ in range(int(1.6 / 0.08))]
        audio = np.concatenate(chunks)
        path = os.path.join(DATA, f"claude-{have + i:03d}.wav")
        sf.write(path, audio, 16000)
        print("  saved", path)
    mic.stop()


def room(seconds):
    from .audio import Mic, pick_input
    from .train import DATA
    import soundfile as sf
    folder = os.path.join(DATA, "room")
    os.makedirs(folder, exist_ok=True)
    mic = Mic(pick_input(None))
    mic.start()
    chunks = [mic.read(timeout=2) for _ in range(int(seconds / 0.08))]
    mic.stop()
    path = os.path.join(folder, time.strftime("room-%Y%m%d-%H%M%S.wav"))
    sf.write(path, np.concatenate(chunks), 16000)
    print("saved", path)


def samples(out):
    """Renders the same line in every candidate voice so they can be compared by ear."""
    import soundfile as sf
    from .tts import Chatterbox, Kokoro
    os.makedirs(out, exist_ok=True)
    try:
        cb = Chatterbox()
        sf.write(os.path.join(out, "chatterbox-default.wav"), cb(SAMPLE_TEXT), 24000)
        for name in sorted(os.listdir(os.path.join(MODELS, "voices"))) if os.path.isdir(
                os.path.join(MODELS, "voices")) else []:
            cb = Chatterbox(voice=name)
            sf.write(os.path.join(out, f"chatterbox-{os.path.splitext(name)[0]}.wav"),
                     cb(SAMPLE_TEXT), 24000)
    except Exception as e:
        print("chatterbox:", e)
    for v in ("af_heart", "af_bella", "af_nicole", "am_michael", "am_puck", "bf_emma",
              "bf_isabella", "bm_george", "bm_fable"):
        try:
            sf.write(os.path.join(out, f"kokoro-{v}.wav"), Kokoro(voice=v)(SAMPLE_TEXT), 24000)
        except Exception as e:
            print(v, e)
    print("wrote samples to", out)


def say(text):
    from .assistant import load_config
    from .audio import Speaker
    from .tts import load
    eng = load(load_config())
    sp = Speaker()
    t = time.time()
    audio = eng(text)
    print(f"synth {time.time() - t:.2f}s for {len(audio) / 24000:.1f}s of audio")
    sp.say(audio)
    time.sleep(0.2)
    sp.wait()


def main():
    ap = argparse.ArgumentParser(prog="sudoclaude-voice")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("run")
    sub.add_parser("setup")
    sub.add_parser("train")
    r = sub.add_parser("record")
    r.add_argument("count", type=int, nargs="?", default=12)
    rm = sub.add_parser("room")
    rm.add_argument("seconds", type=int, nargs="?", default=120)
    s = sub.add_parser("samples")
    s.add_argument("out", nargs="?", default=os.path.expanduser("~/Music/sudoclaude-voices"))
    sy = sub.add_parser("say")
    sy.add_argument("text", nargs="+")
    a, rest = ap.parse_known_args()
    if a.cmd in (None, "run"):
        from .assistant import main as run
        run()
    elif a.cmd == "setup":
        setup()
    elif a.cmd == "train":
        from .train import main as train
        train(rest)
    elif a.cmd == "record":
        record(a.count)
    elif a.cmd == "room":
        room(a.seconds)
    elif a.cmd == "samples":
        samples(a.out)
    elif a.cmd == "say":
        say(" ".join(a.text))


if __name__ == "__main__":
    sys.exit(main())
