import os
import queue
import re
import threading

import numpy as np

from .audio import OUT_RATE
from .listen import MODELS


def resample(audio, sr, target=OUT_RATE):
    if sr == target or not len(audio):
        return audio
    n = int(len(audio) * target / sr)
    return np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio).astype(np.float32)


def speakable(text):
    text = text.replace("&", " and ").replace("%", " percent")
    text = re.sub(r"\bSudoClaude\b", "sudo Claude", text)
    return text


class Kokoro:
    sr = 24000

    def __init__(self, voice="af_heart", speed=1.05):
        import espeakng_loader
        from kokoro_onnx import Kokoro as K
        espeakng_loader.make_library_available()
        here = MODELS
        relay = os.path.expanduser("~/.local/share/relay/models")
        for d in (here, relay):
            if os.path.exists(os.path.join(d, "kokoro-v1.0.onnx")):
                here = d
                break
        self.k = K(os.path.join(here, "kokoro-v1.0.onnx"), os.path.join(here, "voices-v1.0.bin"))
        self.voice, self.speed = voice, speed

    def __call__(self, text):
        audio, sr = self.k.create(text, voice=self.voice, speed=self.speed,
                                  lang="en-gb" if self.voice[:1] == "b" else "en-us")
        return resample(np.asarray(audio, dtype=np.float32), sr)


class Chatterbox:
    """Chatterbox Turbo on the GPU. Expressive, handles [chuckle]-style tags, and can
    clone any voice from a 10 second clip."""

    def __init__(self, voice=None, device=None, exaggeration=None):
        import torch
        from chatterbox.tts_turbo import ChatterboxTurboTTS
        device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.torch = torch
        self.m = ChatterboxTurboTTS.from_pretrained(device=device)
        self.sr = self.m.sr
        self.prompt = None
        if voice:
            path = voice if os.path.isabs(voice) else os.path.join(MODELS, "voices", voice)
            if os.path.exists(path):
                self.prompt = path
                self.m.prepare_conditionals(path)

    def __call__(self, text):
        with self.torch.inference_mode():
            wav = self.m.generate(text)
        audio = wav.squeeze().detach().cpu().numpy().astype(np.float32)
        return resample(audio, self.sr)


ENGINES = {"kokoro": Kokoro, "chatterbox": Chatterbox}


def load(cfg, log=print):
    name = cfg.get("tts", "chatterbox")
    order = [name] + [n for n in ("chatterbox", "kokoro") if n != name]
    for n in order:
        try:
            opts = dict(cfg.get(f"tts_{n}", {}))
            eng = ENGINES[n](**opts)
            log(f"tts: {n}")
            return eng
        except Exception as e:
            log(f"tts {n} unavailable: {e!r}")
    raise RuntimeError("no TTS engine could load")


class Mouth:
    """Turns sentences into audio on a worker thread so the next sentence is ready
    before the current one finishes playing."""

    def __init__(self, engine, speaker, on_text=None):
        self.engine, self.speaker = engine, speaker
        self.on_text = on_text or (lambda t: None)
        self.q = queue.Queue()
        self.gen = 0
        self.pending = 0
        threading.Thread(target=self._run, daemon=True).start()

    def say(self, text):
        self.pending += 1
        self.q.put((self.gen, text))

    def _run(self):
        while True:
            gen, text = self.q.get()
            try:
                if gen != self.gen:
                    continue
                audio = self.engine(speakable(text))
                if gen != self.gen:
                    continue
                self.on_text(text)
                tail = np.zeros(int(OUT_RATE * 0.12), dtype=np.float32)
                self.speaker.say(np.concatenate([audio, tail]))
            except Exception:
                pass
            finally:
                self.pending -= 1

    @property
    def busy(self):
        return self.pending > 0 or self.speaker.speaking

    def stop(self):
        self.gen += 1
        while not self.q.empty():
            try:
                self.q.get_nowait()
                self.pending -= 1
            except queue.Empty:
                break
        self.speaker.stop()
