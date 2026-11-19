import collections
import os
import re
import time

import numpy as np

from .audio import CHUNK, RATE

MODELS = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                      "sudoclaude", "models")
CHUNK_S = CHUNK / RATE

WAKE_RE = re.compile(r"^\W*(?:(?:hey|okay|ok|yo|hi)\W+)?(?:claude|claud|clod|klaud)\b\W*",
                     re.IGNORECASE)
CONTINUES = re.compile(r"\b(and|but|so|or|then|because|uh|um|the|a|to|with|of|for|like|"
                       r"that|if|when|my|your|this)\W*$", re.IGNORECASE)


def to_int16(x):
    return np.clip(x * 32767, -32768, 32767).astype(np.int16)


class Vad:
    def __init__(self):
        from openwakeword.vad import VAD
        self.vad = VAD()

    def __call__(self, chunk):
        return float(self.vad.predict(to_int16(chunk), frame_size=480))


class Wake:
    """openWakeWord detector plus a start-of-utterance check: an assistant gets
    addressed at the start of a sentence, not mid-sentence ("I asked Claude...")."""

    def __init__(self, model_path, threshold=0.6, max_lead=1.5):
        from openwakeword.model import Model
        self.model = Model(wakeword_models=[model_path], inference_framework="onnx")
        self.name = next(iter(self.model.models))
        self.threshold = threshold
        self.max_lead = max_lead
        self.utt_start = None
        self.silence = 0.0
        self.cooldown_until = 0.0

    def reset(self):
        self.model.reset()
        self.utt_start = None
        self.silence = 0.0

    def feed(self, chunk, speech_prob, now):
        if speech_prob > 0.5:
            if self.utt_start is None or self.silence >= 0.3:
                self.utt_start = now
            self.silence = 0.0
        else:
            self.silence += CHUNK_S
        score = float(self.model.predict(to_int16(chunk))[self.name])
        if score < self.threshold or now < self.cooldown_until:
            return score, False
        lead = now - (self.utt_start or now)
        if lead > self.max_lead:
            return score, False
        self.cooldown_until = now + 1.5
        return score, True


class Transcriber:
    def __init__(self, model="nemo-parakeet-tdt-0.6b-v2"):
        import onnx_asr
        self.model = onnx_asr.load_model(model, quantization="int8")

    def __call__(self, audio):
        audio = np.asarray(audio, dtype=np.float32)
        if len(audio) < RATE * 0.25:
            return ""
        peak = float(np.abs(audio).max() or 0)
        if 0 < peak < 0.35:
            audio = audio * min(8.0, 0.7 / peak)
        text = self.model.recognize(audio, sample_rate=RATE)
        return (text or "").strip()


def strip_wake(text):
    return WAKE_RE.sub("", text, count=1).strip()


def has_wake(text):
    return bool(WAKE_RE.match(text))


class Endpointer:
    """Collects speech until the speaker is done. Waits longer when the words
    so far trail off mid-thought ("open discord and...")."""

    def __init__(self, vad, stt, silence=0.5, long_silence=1.4, max_len=25.0,
                 start_timeout=None):
        self.vad, self.stt = vad, stt
        self.silence_s, self.long_s, self.max_len = silence, long_silence, max_len
        self.start_timeout = start_timeout

    def capture(self, read, prefix=None, on_chunk=None, abort=None):
        buf = list(prefix or [])
        heard = bool(prefix)
        silent = 0.0
        waited = 0.0
        pre = collections.deque(maxlen=4)
        checked_at = None
        while True:
            if abort and abort():
                return None
            chunk = read()
            p = self.vad(chunk)
            if on_chunk:
                on_chunk(chunk, p)
            if not heard:
                pre.append(chunk)
                if p > 0.5:
                    heard = True
                    buf.extend(pre)
                    continue
                waited += CHUNK_S
                if self.start_timeout is not None and waited >= self.start_timeout:
                    return None
                continue
            buf.append(chunk)
            silent = silent + CHUNK_S if p < 0.35 else 0.0
            dur = len(buf) * CHUNK_S
            if dur >= self.max_len:
                break
            if silent >= self.silence_s:
                if checked_at is None:
                    checked_at = len(buf)
                    partial = self.stt(np.concatenate(buf))
                    if not CONTINUES.search(partial or ""):
                        return np.concatenate(buf), partial
                if silent >= self.long_s:
                    break
            elif checked_at is not None and p > 0.5:
                checked_at = None
        audio = np.concatenate(buf)
        return audio, self.stt(audio)
