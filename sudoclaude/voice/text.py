"""Claude by typing only, for when the voice is switched off in settings or
paused to save memory.

The guard stops the voice service during games and when memory is low, since
the speech models are what's heavy. Super+Space then starts this instead: the
same pill and typed replies, with nothing loaded but the agent. It stays around
for follow-ups and quits after a while idle or once the voice is back.
"""
import os
import signal
import threading
import time

from .assistant import RUNTIME, TYPE_FLAG, Assistant, load_config, log

PIDFILE = os.path.join(RUNTIME, "sudoclaude-text.pid")
PAUSED = os.path.join(RUNTIME, "sudoclaude-voice-paused")
IDLE_EXIT = 600  # quits after 10 min unused (the overlay is already gone by then)


class _Quiet:
    """Stands in for the speaker, voice and media ducking, none of which exist here."""
    busy = False
    speaking = False
    gen = 0

    def __getattr__(self, _):
        return lambda *a, **k: None

    @property
    def speaker(self):
        return self


class TextAssistant(Assistant):
    def __init__(self, cfg):
        import collections
        import queue
        self.cfg = cfg
        self.stopped = threading.Event()
        self.cancel = threading.Event()
        self.manual = threading.Event()
        self.barge = threading.Event()
        self.typing = threading.Event()
        self.typed = queue.Queue()
        self.ring = collections.deque(maxlen=1)
        self.shown = False
        self.t_ask = 0.0
        self.phase = ""
        self.said = []
        self.text_mode = True
        self.last_typed = True
        self.reply_parts = []
        self.space_hook = False
        self.esc_hook = False
        self.wakes = []
        self.mouth = self.speaker = self.ducker = self.mic = _Quiet()
        self.auth_prompted = 0.0

        from sudoclaude.compositor import detect
        from sudoclaude.overlay import Overlay
        try:
            self.comp = detect()
        except Exception:
            self.comp = None
        self.overlay = Overlay(on_stop=self.on_overlay_stop, comp=self.comp,
                               on_event=self.on_overlay_event)
        from .agent import Agent
        self.agent = Agent(cfg, on_sentence=self.on_sentence, on_tool=self.on_tool, log=log)
        self.agent.on_auth = self.on_auth

    def pick_voice(self, place):
        pass

    def fast_music(self, text):
        return False  # the shortcut answers out loud; let Claude reply in text instead

    def on_auth(self):
        log("claude login expired")
        self.reply_parts = ["My Claude login expired. Run claude in a terminal and use /login."]
        self.ui(voice="speaking", status="Claude", bubble=True, reply=self.reply_parts[0])

    def on_key(self, *_):
        if self.phase in ("thinking", "speaking"):
            self.barge.set()
        elif not self.phase:
            self.manual.set()

    def watch(self, worker):
        """While Claude works: Esc cancels, Super+Space cuts in to type something new."""
        self.barge.clear()
        while worker.is_alive():
            if self.cancel.is_set():
                self.agent.interrupt()
                worker.join(5)
                return None
            if self.barge.is_set():
                self.barge.clear()
                self.agent.interrupt()
                worker.join(10)
                self.ui(voice="listening", status="Ask Claude", transcript="", typing=True,
                        bubble=False, who="you")
                got = self.wait_typed(timeout=90)
                return (got[1] if got else "") or "stop"
            time.sleep(0.05)
        return None

    def session(self):
        self.cancel.clear()
        self.shown = True
        place = self.placement()
        log("typed session")
        self.ui(voice="listening", status="Ask Claude", transcript="", level=0, typing=True,
                stopped=False, idle=False, bubble=False, who="you",
                **{k: v for k, v in place.items() if k != "content"})
        self.hook_esc(True)
        got = self.wait_typed(timeout=120)
        if not got:
            return self.finish()
        self.converse(got[1], typed=True)

    def run(self):
        threading.Thread(target=self.agent.warm, daemon=True).start()
        threading.Thread(target=self.watch_stop, daemon=True).start()
        log("text mode ready")
        self.manual.set()
        last = time.time()
        while not self.stopped.is_set():
            if self.manual.wait(1.0):
                self.manual.clear()
                try:
                    self.session()
                except Exception as e:
                    log("text error:", repr(e))
                    self.finish(quiet=True)
                last = time.time()
                continue
            if time.time() - last > IDLE_EXIT:
                break
            # Typing is the mode while the voice is switched off or a game runs;
            # otherwise this steps aside once the voice is available again.
            voice_on = load_config().get("enabled", True) is not False
            try:
                from sudoclaude import gamemode
                in_game = bool(gamemode.running())
            except Exception:
                in_game = False
            if voice_on and not in_game and not os.path.exists(PAUSED):
                break
        self.shutdown()

    def shutdown(self, *_):
        self.hook_esc(False)
        self.stopped.set()
        self.ui(voice="", typing=False, bubble=False, transcript="")


def running():
    try:
        pid = int(open(PIDFILE).read())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"sudoclaude.voice" in f.read():
                return pid
    except (OSError, ValueError):
        pass
    return None


def main():
    from .assistant import fix_env
    fix_env()
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    try:
        os.unlink(TYPE_FLAG)
    except OSError:
        pass
    a = TextAssistant(load_config())
    signal.signal(signal.SIGTERM, lambda *x: (a.shutdown(), os._exit(0)))
    signal.signal(signal.SIGUSR1, a.on_key)
    try:
        a.run()
    finally:
        try:
            if running() == os.getpid():
                os.unlink(PIDFILE)
        except OSError:
            pass
