import collections
import json
import os
import queue
import re
import signal
import sys
import threading
import time

import numpy as np

from .audio import CHUNK, OUT_RATE, RATE, Ducker, Mic, Speaker, pick_input
from .listen import (CHUNK_S, MODELS, Endpointer, Transcriber, Vad, Wake, has_wake,
                     strip_wake)

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
LOGFILE = os.path.join(RUNTIME, "sudoclaude-voice.log")
TYPE_FLAG = os.path.join(RUNTIME, "sudoclaude-type")
CONFIG = os.path.expanduser("~/.config/sudoclaude/config.json")

DEFAULTS = {
    "enabled": True,
    "input": None,
    "wake_models": ["claude.onnx", "hey_claude.onnx"],
    "wake_threshold": 0.55,
    "wake_soft": 0.2,
    "followup_seconds": 6.0,
    "barge_in_seconds": 0.8,
    # Interrupting Claude by voice (its name, or talking over it). Off for now:
    # it was too easy to trigger. Super+Space always cuts in.
    "voice_interrupt": False,
    "duck": 0.2,
    "chime": True,
    "tts": "chatterbox",
    "tts_kokoro": {"voice": "af_heart", "speed": 1.05},
    "tts_chatterbox": {},
    "model": None,
    "memory_minutes": 10,
}

STOP = re.compile(r"^\W*(stop|cancel|never ?mind|shut up|quiet|be quiet|that's enough|enough|"
                  r"hold on|wait)\W*$", re.I)
MUSIC = [
    (re.compile(r"^(pause|pause (the )?(music|song)|pause it|stop the (music|song))$"), "pause", None),
    (re.compile(r"^(resume|unpause|keep playing|resume (the )?music|play the music|play music)$"),
     "resume", None),
    (re.compile(r"^(next|skip|skip it|skip (this|this song|this one)|next (song|track|one))$"),
     "next", None),
    (re.compile(r"^(previous|go back|last song|previous (song|track)|play the last song)$"),
     "previous", None),
    (re.compile(r"^(what'?s playing|what is playing|what song is this|what'?s this song|"
                r"who is this|who'?s this)$"), "now_playing", None),
    (re.compile(r"^(turn (it|the music|this) up|volume up|louder|turn up the music)$"),
     "volume", 15),
    (re.compile(r"^(turn (it|the music|this) down|volume down|quieter|turn down the music)$"),
     "volume", -15),
]
OTHER_PLAYERS = re.compile(r"\b(youtube|netflix|spotify|twitch|video|episode|movie|browser|"
                           r"game|steam|podcast)\b", re.I)

BYE = re.compile(r"\b(that'?s all|that is all|i'?m good|i'?m done|we'?re done|thanks?,? "
                 r"(that'?s it|bye)|goodbye|bye|nothing else)\W*$", re.I)


def log(*a):
    line = time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a)
    print(line, flush=True)
    try:
        with open(LOGFILE, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_config():
    cfg = dict(DEFAULTS)
    try:
        with open(CONFIG) as f:
            cfg.update(json.load(f).get("voice", {}))
    except (OSError, ValueError):
        pass
    return cfg


SOUNDS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sounds")
_sounds = {}


def chime(kind="wake"):
    path = os.path.join(SOUNDS, f"{kind}.wav")
    if os.path.exists(path):
        if kind not in _sounds:
            import soundfile as sf
            a, sr = sf.read(path, dtype="float32")
            if a.ndim > 1:
                a = a.mean(axis=1)
            if sr != OUT_RATE:
                a = np.interp(np.arange(0, len(a), sr / OUT_RATE), np.arange(len(a)), a).astype(np.float32)
            _sounds[kind] = a
        return _sounds[kind]
    return _synth_chime(kind)


def _synth_chime(kind):
    t = np.arange(int(OUT_RATE * 0.16)) / OUT_RATE
    notes = (660, 990) if kind == "wake" else (880, 587)
    out = []
    for i, f in enumerate(notes):
        env = np.minimum(1, t / 0.008) * np.exp(-t * 18)
        tone = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)
        out.append(tone * env * 0.12)
        if i == 0:
            out.append(np.zeros(int(OUT_RATE * 0.03)))
    return np.concatenate(out).astype(np.float32)


class Assistant:
    def __init__(self, cfg):
        self.cfg = cfg
        self.stopped = threading.Event()
        self.cancel = threading.Event()
        self.ring = collections.deque(maxlen=int(3.0 / CHUNK_S))
        self.shown = False
        self.t_ask = 0.0
        self.phase = ""
        # Typical mic level of the room when nobody's talking to it, so talking
        # over Claude has to stand out from music, TV or a fan to count.
        self.noise = 0.003
        self.said = []
        self.text_mode = False
        self.last_typed = False
        self.reply_parts = []
        self.manual = threading.Event()
        self.barge = threading.Event()
        self.typing = threading.Event()
        self.typed = queue.Queue()
        self.space_hook = False

        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        from sudoclaude.compositor import detect
        from sudoclaude.overlay import Overlay
        try:
            self.comp = detect()
        except Exception:
            self.comp = None
        self.overlay = Overlay(on_stop=self.on_overlay_stop, comp=self.comp,
                               on_event=self.on_overlay_event)

        log("loading models")
        self.vad = Vad()
        self.stt = Transcriber()
        paths = [os.path.join(MODELS, m) for m in cfg["wake_models"]]
        paths = [p for p in paths if os.path.exists(p)]
        if not paths:
            raise SystemExit(f"no wake word model in {MODELS}; run bin/sudoclaude-voice setup")
        self.wakes = [Wake(p, threshold=cfg["wake_threshold"]) for p in paths]
        log("wake models:", ", ".join(os.path.basename(p) for p in paths))
        self.endpoint = Endpointer(self.vad, self.stt)

        from .tts import Mouth, load
        self.speaker = Speaker()
        self.mouth = Mouth(load(cfg, log), self.speaker, on_text=self.on_spoken)
        self.ducker = Ducker(cfg["duck"])

        from .agent import Agent
        self.agent = Agent(cfg, on_sentence=self.on_sentence, on_tool=self.on_tool, log=log)
        self.agent.on_auth = self.on_auth
        self.auth_prompted = 0.0
        self.voice_main = self.mouth.engine
        self.voice_light = None
        test = os.environ.get("SUDOCLAUDE_VOICE_INPUT")
        self.mic = Mic(test if test else pick_input(cfg.get("input")))
        log("input:", self.mic.target or "default")

    # overlay -----------------------------------------------------------------

    def ui(self, **msg):
        if "voice" in msg:
            self.phase = msg["voice"]
        try:
            self.overlay.send(**msg)
        except Exception:
            pass

    def placement(self):
        c = self.comp
        if not c or getattr(c, "name", "") != "hyprland":
            return {"mode": "full"}
        try:
            a = c.j("activewindow") or {}
            mons = {m.get("id"): m["name"] for m in c.j("monitors")}
        except Exception:
            return {"mode": "full"}
        flow = bool(a.get("fullscreen")) or a.get("contentType") in ("game", "video") \
            or bool(a.get("tearingHint"))
        return {"mode": "corner" if flow else "full", "screen": mons.get(a.get("monitor"), ""),
                "content": a.get("contentType") or ("game" if a.get("tearingHint") else "")}

    def on_overlay_event(self, m):
        if m.get("event") == "typed":
            self.typed.put(m.get("text") or "")

    def on_key(self, *_):
        """Super+Space: start talking, end the turn while it's listening, or cut
        in while Claude is answering."""
        if self.phase == "listening":
            log("key: done listening")
            self.cancel.set()
        elif self.phase in ("thinking", "speaking"):
            log("key: interrupt")
            self.barge.set()
        else:
            log("key: listen")
            self.manual.set()

    def on_overlay_stop(self):
        log("stop pressed")
        self.cancel.set()
        self.mouth.stop()
        self.agent.interrupt()

    def on_sentence(self, text):
        """A sentence of the reply: spoken, or, when they typed, added to the text
        bubble by the pill."""
        if not self.text_mode:
            self.mouth.say(text)
            return
        from .tts import TAGS
        if self.t_ask:
            log(f"first text {time.time() - self.t_ask:.2f}s after the request")
            self.t_ask = 0.0
        self.reply_parts.append(TAGS.sub("", text).strip())
        self.ui(voice="speaking", status="Claude", transcript="", bubble=True,
                reply=" ".join(p for p in self.reply_parts if p))

    def on_spoken(self, text, at=None, secs=0.0, gen=None):
        """Caption a sentence in step with the voice: wait until it's actually
        heard, then reveal it word by word over its length."""
        threading.Thread(target=self._caption, args=(text, at, secs, gen), daemon=True).start()

    def _caption(self, text, at, secs, gen):
        from .tts import TAGS
        words = TAGS.sub("", text).split()
        if at:
            time.sleep(max(0.0, at - time.time()))
        if gen is not None and gen != self.mouth.gen:
            return
        if self.t_ask:
            log(f"first audio {time.time() - self.t_ask:.2f}s after the request")
            self.t_ask = 0.0
        before = " ".join(self.said)
        total = max(1, sum(len(w) + 1 for w in words))
        span = max(0.2, secs * 0.92)
        t0, shown = time.time(), -1
        while True:
            if gen is not None and gen != self.mouth.gen:
                return
            frac = min(1.0, (time.time() - t0) / span)
            n, acc = 0, 0
            for w in words:
                if acc >= frac * total:
                    break
                acc += len(w) + 1
                n += 1
            if n != shown:
                shown = n
                self.ui(voice="speaking", status="Claude", who="claude",
                        transcript=(before + " " + " ".join(words[:n])).strip())
            if frac >= 1.0:
                break
            time.sleep(0.06)
        self.said.append(" ".join(words))

    def on_auth(self):
        log("claude login expired")
        self.mouth.say("My Claude login expired, so I can't do that yet.")
        if time.time() - self.auth_prompted > 3600:
            self.auth_prompted = time.time()
            self.mouth.say("I opened a terminal where you can log back in.")
            try:
                rules = {"no_initial_focus": True} if self.placement().get("mode") == "corner" else {}
                self.comp.launch("kitty --title 'Claude login' sh -c 'claude /login; exec $SHELL'",
                                 rules)
            except Exception as e:
                log("could not open login terminal:", repr(e))

    def pick_voice(self, place):
        """While a game has the GPU, talk with the CPU voice so frames don't drop."""
        gaming = place.get("mode") == "corner" and place.get("content") == "game"
        if gaming and self.cfg.get("tts") == "chatterbox":
            if self.voice_light is None:
                from .tts import Kokoro
                try:
                    self.voice_light = Kokoro(**self.cfg.get("tts_kokoro", {}))
                except Exception:
                    self.voice_light = False
            if self.voice_light:
                self.mouth.engine = self.voice_light
                return
        self.mouth.engine = self.voice_main

    def on_tool(self, name):
        short = name.split("__")[-1].replace("_", " ")
        self.ui(voice="thinking", status="Working", transcript=short, who="tool")

    # listening ---------------------------------------------------------------

    def read(self):
        while not self.stopped.is_set():
            try:
                return self.mic.read(timeout=0.5)
            except Exception:
                continue
        raise SystemExit

    def score(self, chunk, p, now):
        best, hit = 0.0, False
        for w in self.wakes:
            s, h = w.feed(chunk, p, now)
            best, hit = max(best, s), hit or h
        return best, hit

    def utterance_prefix(self):
        starts = [w.utt_start for w in self.wakes if w.utt_start]
        if not starts:
            return list(self.ring)[-int(1.5 / CHUNK_S):]
        back = time.time() - min(starts) + 0.25
        n = min(len(self.ring), int(back / CHUNK_S) + 1)
        return list(self.ring)[-n:]

    def capture(self, prefix=None, start_timeout=None, live=True):
        ep = Endpointer(self.vad, self.stt, start_timeout=start_timeout)
        buf, state = [], {"last": 0.0, "busy": False, "talking": False, "quiet": 0.0}

        def on_chunk(chunk, p):
            self.ring.append(chunk)
            buf.append(chunk)
            lvl = min(1.0, self.mic.level * 9)
            if live:
                self.ui(level=round(lvl, 3))
            now = time.time()
            # Once they start talking, keep re-transcribing a few times a second
            # (and once more after they pause) so the words keep up with them.
            if p > 0.5:
                state["talking"], state["quiet"] = True, now
            fresh = now - state["quiet"] < 0.6
            if live and state["talking"] and fresh and not state["busy"] and now - state["last"] > 0.3:
                state["busy"], state["last"] = True, now
                snap = np.concatenate((prefix or []) + buf)

                def partial():
                    try:
                        t = strip_wake(self.stt(snap))
                        if t:
                            self.ui(transcript=t, who="you")
                    finally:
                        state["busy"] = False
                threading.Thread(target=partial, daemon=True).start()

        return ep.capture(self.read, prefix=prefix, on_chunk=on_chunk,
                          abort=lambda: self.cancel.is_set() or self.typing.is_set()
                          or self.check_typing())

    # typing ------------------------------------------------------------------

    def check_typing(self):
        if not self.space_hook or not os.path.exists(TYPE_FLAG):
            return False
        try:
            os.unlink(TYPE_FLAG)
        except OSError:
            pass
        log("typing instead of talking")
        self.typing.set()
        self.ui(typing=True, status="Ask Claude", transcript="", level=0)
        return True

    def listen(self, **kw):
        """Capture speech, or if a double-tap of Space switched to typing, wait
        for what gets typed. Returns (audio, text) or None."""
        try:
            os.unlink(TYPE_FLAG)
        except OSError:
            pass
        t0 = time.time()
        self.last_typed = False
        got = self.capture(**kw)
        if not self.typing.is_set():
            why = ("cancelled" if self.cancel.is_set() else "nothing said" if got is None
                   else "got speech")
            log(f"listen ended after {time.time() - t0:.1f}s: {why}")
            return got
        return self.wait_typed()

    def wait_typed(self, timeout=300):
        """Wait for what they type into the pill. Returns (None, text) or None
        if they cancel or leave it."""
        self.typing.set()
        self.ducker.restore()
        while not self.typed.empty():
            self.typed.get_nowait()
        text = None
        deadline = time.time() + timeout
        while text is None and time.time() < deadline and not self.cancel.is_set() \
                and not self.stopped.is_set():
            try:
                text = self.typed.get(timeout=0.2)
            except queue.Empty:
                pass
        self.typing.clear()
        self.ui(typing=False)
        self.mic.drain()
        text = (text or "").strip()
        self.last_typed = bool(text)
        return (None, text) if text else None

    def hook_space(self, on):
        c = self.comp
        if not c or getattr(c, "name", "") != "hyprland" or on == self.space_hook:
            return
        try:
            if on:
                c.space_listen(TYPE_FLAG)
            else:
                c.space_unlisten()
            self.space_hook = on
        except Exception as e:
            log("space hook:", repr(e))

    def idle(self):
        for w in self.wakes:
            w.reset()
        self.mic.drain()
        while not self.stopped.is_set():
            if self.manual.is_set():
                self.manual.clear()
                return "manual"
            chunk = self.read()
            self.ring.append(chunk)
            now = time.time()
            p = self.vad(chunk)
            if p < 0.3:
                self.noise += (self.mic.level - self.noise) * 0.02
            score, hit = self.score(chunk, p, now)
            if hit or score >= self.cfg["wake_soft"]:
                log(f"wake candidate {score:.2f}" + (" strong" if hit else ""))
                return hit

    def engage(self, strong):
        self.cancel.clear()
        if strong == "manual":
            self.wake_ui()
            got = self.listen(start_timeout=6.0)
            cmd = strip_wake(got[1]) if got and got[1] else ""
            if not cmd:
                if got:
                    log("speech but no words:", repr((got[1] or "")[:40]))
                return self.finish()
            log("heard:", repr(cmd))
            return self.converse(cmd, typed=self.last_typed)
        prefix = self.utterance_prefix()
        strong_hit, heard = bool(strong), ""
        if strong:
            # Check the words so far before lighting anything up: one quick pass
            # over a second or two of audio, so a false fire stays invisible.
            heard = self.stt(np.concatenate(prefix)) if prefix else ""
            strong = has_wake(heard) or bool(re.search(r"\b(claude|claud)\W*$", heard, re.I))
            if strong:
                self.wake_ui()
        got = self.capture(prefix=prefix, live=strong)
        if got is None:
            return self.finish(quiet=True)
        audio, text = got
        if not has_wake(text):
            # Don't keep what people in the room say when it wasn't meant for Claude,
            # except a short note for confident hits so a deaf spot can be found.
            if strong_hit:
                log("strong wake rejected, heard:", repr((text or "")[:40]),
                    "| prefix:", repr((heard or "")[:40]))
            else:
                log("not addressed to Claude, ignored")
            return self.finish(quiet=True)
        log("heard:", repr(text))
        if not strong:
            self.wake_ui()
        cmd = strip_wake(text)
        if not cmd or len(cmd) < 2:
            self.ui(voice="listening", status="Listening", transcript="", who="you")
            got = self.listen(start_timeout=5.0)
            if not got or not got[1]:
                return self.finish()
            cmd = strip_wake(got[1])
        self.converse(cmd, typed=self.last_typed)

    def wake_ui(self):
        self.shown = True
        if self.cfg.get("chime"):
            self.speaker.say(chime())
        threading.Thread(target=self.ducker.duck, daemon=True).start()
        place = self.placement()
        self.pick_voice(place)
        # stopped/idle belong to computer use; a voice turn always starts fresh.
        self.ui(voice="listening", status="Listening", transcript="", level=0,
                stopped=False, idle=False, who="you",
                **{k: v for k, v in place.items() if k != "content"})
        # Double-tap Space to type instead, except over fullscreen apps and games.
        self.hook_space(place.get("mode") != "corner")

    # talking -----------------------------------------------------------------

    def fast_music(self, text):
        """Plain music commands skip the round trip to Claude, like any speaker would."""
        t = re.sub(r"[^\w' ]", "", text.lower()).strip()
        t = re.sub(r"^(please |can you |could you )", "", t)
        t = re.sub(r" please$", "", t)
        action, delta, query = None, None, None
        for rx, act, d in MUSIC:
            if rx.match(t):
                action, delta = act, d
                break
        m = re.match(r"^play (.+?)( on (apple music|cider))?$", t)
        if not action and m and not OTHER_PLAYERS.search(t) and m.group(1) not in ("it", "that"):
            action, query = "play", m.group(1)
        if not action:
            return False
        from sudoclaude import music

        def launch(cmd):
            if self.comp:
                self.comp.launch(cmd, {"workspace": "special:music silent", "no_initial_focus": True})
        log("music fast path:", action, query or "")
        try:
            said = music.run(action, query=query, delta=delta, launch=launch)
        except music.MusicError as e:
            log("music failed:", e)
            return False
        if action in ("play", "now_playing"):
            self.mouth.say(said)
        else:
            self.speaker.say(chime("done"))
        return True

    def converse(self, text, followup=False, interrupting=False, typed=False):
        self.text_mode = typed
        if not interrupting and self.fast_music(text):
            return self.finish()
        while text and not self.stopped.is_set():
            if STOP.match(text):
                log("stop phrase")
                return self.finish()
            tag = ("(interrupting) " if interrupting else "(follow-up) " if followup else "")
            if self.text_mode:
                tag = "(typed) " + tag
            log("ask:", tag + text)
            self.t_ask = self.t_ask or time.time()
            self.said = []
            self.reply_parts = []
            if self.text_mode:
                self.ui(voice="thinking", status="Thinking", transcript="", bubble=False)
            else:
                self.ui(voice="thinking", status="Thinking", transcript=text, who="you")
            result = {}
            worker = threading.Thread(target=lambda: result.update(r=self.agent.ask(tag + text)),
                                      daemon=True)
            worker.start()
            barged = self.watch(worker)
            if barged is not None:
                text, followup, interrupting = barged, False, True
                continue
            reply = (result.get("r") or "").strip()
            log("reply:", repr(reply[:200]))
            if reply.lower().startswith("[ignore]"):
                return self.finish(quiet=True)
            if "[end]" in reply.lower() or BYE.search(text):
                if self.text_mode:
                    # Leave a typed answer up long enough to read.
                    self.reading_pause(reply)
                return self.finish()
            if self.text_mode:
                # Typed conversations continue by typing; the reply stays up.
                self.ui(voice="listening", status="Ask Claude", transcript="", level=0,
                        typing=True, who="you")
                got = self.wait_typed(timeout=90)
                if not got:
                    return self.finish()
                text, followup, interrupting = got[1], True, False
                continue
            self.ui(voice="listening", status="Listening", transcript="", level=0, who="you")
            got = self.listen(start_timeout=self.cfg["followup_seconds"])
            if not got or not got[1].strip():
                return self.finish()
            text, followup, interrupting = got[1].strip(), not has_wake(got[1]), False
            text = strip_wake(text) if has_wake(got[1]) else text
        self.finish()

    def watch(self, worker):
        """While Claude thinks or talks: saying its name always interrupts, and
        while it's speaking, a sustained stretch of speech does too."""
        for w in self.wakes:
            w.reset()
        self.mic.drain()
        self.barge.clear()
        talk = 0.0
        while worker.is_alive() or self.mouth.busy:
            if self.cancel.is_set():
                self.mouth.stop()
                self.agent.interrupt()
                worker.join(5)
                return None
            chunk = self.read()
            self.ring.append(chunk)
            now = time.time()
            p = self.vad(chunk)
            _, hit = self.score(chunk, p, now)
            if not self.cfg.get("voice_interrupt"):
                hit = False
            if self.barge.is_set():
                self.barge.clear()
                self.mouth.stop()
                self.agent.interrupt()
                self.ui(voice="listening", status="Listening", transcript="", level=0, who="you")
                got = self.listen(start_timeout=6.0)
                worker.join(10)
                return (got[1] if got else "") or "stop"
            speaking = self.speaker.speaking
            loud = self.mic.level > max(0.006, self.noise * 3.0)
            talk = (talk + CHUNK_S if (p > 0.85 and loud and speaking
                                       and self.cfg.get("voice_interrupt"))
                    else max(0.0, talk - CHUNK_S))
            if hit:
                log("barge-in: wake")
                self.mouth.stop()
                self.agent.interrupt()
                self.ui(voice="listening", status="Listening", transcript="", who="you")
                got = self.capture(prefix=self.utterance_prefix())
                said = strip_wake(got[1]) if got else ""
                worker.join(10)
                if not said:
                    got = self.listen(start_timeout=5.0)
                    said = strip_wake(got[1]) if got else ""
                return said or "stop"
            if talk >= self.cfg["barge_in_seconds"]:
                # Soften rather than cut: a cough or someone else in the room
                # shouldn't kill the answer. Real words stop it.
                self.speaker.volume(0.25)
                got = self.capture(prefix=self.utterance_prefix(), live=False)
                said = (got[1] if got else "").strip()
                if len(said.split()) >= 3 or STOP.match(said) or has_wake(said):
                    log("barge-in: speech", repr(said))
                    self.mouth.stop()
                    self.agent.interrupt()
                    worker.join(10)
                    return strip_wake(said)
                self.speaker.volume(1.0)
                talk = 0.0
        return None

    def reading_pause(self, reply):
        words = len(re.sub(r"\[[^\]]+\]", "", reply).split())
        deadline = time.time() + min(12.0, 2.0 + words * 0.28)
        while time.time() < deadline and not self.cancel.is_set():
            time.sleep(0.1)

    def finish(self, quiet=False):
        self.mouth.speaker.wait(abort=self.cancel.is_set)
        self.hook_space(False)
        self.typing.clear()
        self.text_mode = False
        if self.shown:
            self.ui(voice="", transcript="", level=0, typing=False, bubble=False)
            self.shown = False
        self.phase = ""
        self.ducker.restore()
        self.cancel.clear()

    # main --------------------------------------------------------------------

    def run(self):
        self.mic.start()
        threading.Thread(target=self.agent.warm, daemon=True).start()
        threading.Thread(target=self.agent.keep_warm, daemon=True).start()
        log("ready")
        while not self.stopped.is_set():
            try:
                strong = self.idle()
                self.engage(strong)
            except SystemExit:
                break
            except Exception as e:
                log("error:", repr(e))
                self.mouth.stop()
                self.finish(quiet=True)
                time.sleep(0.5)

    def shutdown(self, *_):
        self.hook_space(False)
        self.stopped.set()
        self.mic.stop()
        self.mouth.stop()
        self.ducker.restore()
        self.ui(voice="")


def fix_env():
    import glob
    os.environ.setdefault("XDG_RUNTIME_DIR", RUNTIME)
    if not os.environ.get("WAYLAND_DISPLAY"):
        socks = sorted(p for p in glob.glob(os.path.join(RUNTIME, "wayland-*")) if not p.endswith(".lock"))
        if socks:
            os.environ["WAYLAND_DISPLAY"] = os.path.basename(socks[0])
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        sigs = sorted(glob.glob(os.path.join(RUNTIME, "hypr", "*", ".socket.sock")), key=os.path.getmtime)
        if sigs:
            os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(os.path.dirname(sigs[-1]))
    os.environ["QT_QPA_PLATFORM"] = "wayland"


def main():
    fix_env()
    cfg = load_config()
    if not cfg.get("enabled", True):
        log("voice disabled in config")
        return
    a = Assistant(cfg)
    signal.signal(signal.SIGTERM, lambda *x: (a.shutdown(), os._exit(0)))
    signal.signal(signal.SIGINT, lambda *x: (a.shutdown(), os._exit(0)))
    signal.signal(signal.SIGUSR1, a.on_key)
    signal.signal(signal.SIGUSR2, lambda *x: a.on_overlay_stop())
    a.run()
