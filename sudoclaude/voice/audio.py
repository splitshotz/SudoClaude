import json
import queue
import shutil
import subprocess
import threading
import time

import numpy as np

RATE = 16000
CHUNK = 1280          # 80 ms, what openWakeWord expects
OUT_RATE = 24000


def pick_input(preferred=None):
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"], capture_output=True,
                             text=True, timeout=3).stdout
    except Exception:
        return preferred
    names = [line.split("\t")[1] for line in out.splitlines() if "\t" in line]
    for cand in (preferred, "sudoclaude_mic", "relay_mic"):
        if cand and cand in names:
            return cand
    try:
        return subprocess.run(["pactl", "get-default-source"], capture_output=True,
                              text=True, timeout=3).stdout.strip() or None
    except Exception:
        return None


class Mic:
    """16 kHz mono float32 microphone stream in 80 ms chunks, via pw-record."""

    def __init__(self, target=None):
        self.target = target
        self.q = queue.Queue(maxsize=400)
        self.proc = None
        self.level = 0.0
        self.running = False

    def start(self):
        if self.target and self.target.startswith("file:"):
            threading.Thread(target=self._file, args=(self.target[5:],), daemon=True).start()
            return
        self.running = True
        threading.Thread(target=self._keep, daemon=True).start()

    def _keep(self):
        """Keeps a recorder running; PipeWire restarts and device changes kill it."""
        while self.running:
            target = self.target
            if target and target != "default":
                for _ in range(20):
                    names = subprocess.run(["pactl", "list", "short", "sources"],
                                           capture_output=True, text=True).stdout
                    if f"\t{target}\t" in names:
                        break
                    time.sleep(0.5)
                else:
                    target = pick_input(None)
            cmd = ["parec", "--raw", "--format=float32le", f"--rate={RATE}", "--channels=1",
                   "--latency-msec=40", "--client-name=sudoclaude",
                   "--stream-name=sudoclaude-listen"]
            if target:
                cmd.append(f"--device={target}")
            self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self._pump()
            if self.running:
                time.sleep(1.0)

    def _pump(self):
        need = CHUNK * 4
        buf = b""
        while self.proc and self.proc.poll() is None:
            d = self.proc.stdout.read(need - len(buf) if len(buf) < need else need)
            if not d:
                break
            buf += d
            while len(buf) >= need:
                chunk = np.nan_to_num(np.frombuffer(buf[:need], dtype="<f4"), nan=0.0,
                                      posinf=0.0, neginf=0.0).clip(-1, 1).astype(np.float32)
                buf = buf[need:]
                self.level = float(np.sqrt(np.mean(chunk * chunk)))
                try:
                    self.q.put_nowait(chunk)
                except queue.Full:
                    try:
                        self.q.get_nowait()
                    except queue.Empty:
                        pass
                    self.q.put_nowait(chunk)

    def _file(self, path):
        """Test input: plays WAV files through the pipeline in real time, then silence."""
        import soundfile as sf
        silence = np.zeros(CHUNK, dtype=np.float32)
        for p in path.split(","):
            if p.startswith("pause"):
                for _ in range(int(float(p[5:] or 3) / (CHUNK / RATE))):
                    self.q.put(silence)
                    time.sleep(CHUNK / RATE)
                continue
            audio, sr = sf.read(p, dtype="float32")
            if audio.ndim > 1:
                audio = audio.mean(axis=1)
            if sr != RATE:
                audio = np.interp(np.arange(0, len(audio), sr / RATE), np.arange(len(audio)),
                                  audio).astype(np.float32)
            audio = np.concatenate([np.zeros(RATE, np.float32), audio])
            for i in range(0, len(audio) - CHUNK + 1, CHUNK):
                chunk = audio[i:i + CHUNK]
                self.level = float(np.sqrt(np.mean(chunk * chunk)))
                self.q.put(chunk)
                time.sleep(CHUNK / RATE)
        while True:
            self.q.put(silence)
            time.sleep(CHUNK / RATE)

    def read(self, timeout=1.0):
        return self.q.get(timeout=timeout)

    def drain(self):
        while not self.q.empty():
            try:
                self.q.get_nowait()
            except queue.Empty:
                break

    def stop(self):
        self.running = False
        if self.proc:
            self.proc.terminate()
            self.proc = None


class Speaker:
    """Streams float32 audio to PipeWire. stop() cuts it off immediately."""

    def __init__(self, rate=OUT_RATE):
        self.rate = rate
        self.proc = None
        self.level = 0.0
        self._lock = threading.Lock()
        self._busy_until = 0.0
        self.q = queue.Queue()
        self._gen = 0
        threading.Thread(target=self._worker, daemon=True).start()

    def _open(self):
        if self.proc and self.proc.poll() is None:
            return
        self.proc = subprocess.Popen(
            ["pacat", "--playback", "--raw", "--format=float32le", f"--rate={self.rate}",
             "--channels=1", "--latency-msec=60", "--client-name=sudoclaude",
             "--stream-name=sudoclaude-voice"],
            stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def say(self, audio):
        self.q.put((self._gen, np.asarray(audio, dtype=np.float32)))

    def _worker(self):
        while True:
            gen, audio = self.q.get()
            if gen != self._gen:
                continue
            with self._lock:
                self._open()
            step = self.rate // 25
            for i in range(0, len(audio), step):
                if gen != self._gen:
                    break
                part = audio[i:i + step]
                self.level = float(np.sqrt(np.mean(part * part))) if len(part) else 0.0
                try:
                    self.proc.stdin.write(part.tobytes())
                    self.proc.stdin.flush()
                except Exception:
                    with self._lock:
                        self.proc = None
                    break
                self._busy_until = max(self._busy_until, time.time()) + len(part) / self.rate
                ahead = self._busy_until - time.time()
                if ahead > 0.25:
                    time.sleep(ahead - 0.2)
            self.level = 0.0

    def volume(self, factor):
        """Softens our own stream (1.0 = normal) without stopping it."""
        try:
            r = subprocess.run(["pactl", "-f", "json", "list", "sink-inputs"],
                               capture_output=True, text=True, timeout=2)
            for si in json.loads(r.stdout or "[]"):
                if si.get("properties", {}).get("media.name") == "sudoclaude-voice":
                    subprocess.run(["pactl", "set-sink-input-volume", str(si["index"]),
                                    f"{int(factor * 100)}%"], timeout=2)
        except Exception:
            pass

    @property
    def speaking(self):
        return not self.q.empty() or time.time() < self._busy_until + 0.05

    def stop(self):
        self._gen += 1
        while not self.q.empty():
            try:
                self.q.get_nowait()
            except queue.Empty:
                break
        with self._lock:
            if self.proc:
                try:
                    self.proc.kill()
                except Exception:
                    pass
                self.proc = None
        self._busy_until = 0.0
        self.level = 0.0

    def wait(self, poll=0.05, abort=None):
        while self.speaking:
            if abort and abort():
                return False
            time.sleep(poll)
        return True


class Ducker:
    """Lowers every other playing stream while the assistant is engaged."""

    def __init__(self, factor=0.25):
        self.factor = factor
        self.saved = {}
        self.pactl = shutil.which("pactl")

    def _inputs(self):
        r = subprocess.run([self.pactl, "-f", "json", "list", "sink-inputs"],
                           capture_output=True, text=True, timeout=3)
        return json.loads(r.stdout or "[]")

    def duck(self):
        if not self.pactl or self.saved:
            return
        try:
            for si in self._inputs():
                props = si.get("properties", {})
                if "sudoclaude" in (props.get("media.name", "") + props.get("application.name", "")):
                    continue
                vols = [int(str(c.get("value_percent", "100%")).rstrip("%"))
                        for c in (si.get("volume") or {}).values()]
                if not vols:
                    continue
                idx = si["index"]
                self.saved[idx] = vols
                low = [max(1, int(v * self.factor)) for v in vols]
                subprocess.run([self.pactl, "set-sink-input-volume", str(idx)] +
                               [f"{v}%" for v in low], timeout=3)
        except Exception:
            pass

    def restore(self):
        if not self.pactl:
            return
        for idx, vols in list(self.saved.items()):
            try:
                subprocess.run([self.pactl, "set-sink-input-volume", str(idx)] +
                               [f"{v}%" for v in vols], timeout=3, capture_output=True)
            except Exception:
                pass
        self.saved.clear()
