import asyncio
import os
import re
import shutil
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PROMPT = """You are Claude, talking out loud with {name} through their desktop microphone and speakers on their Linux PC (Hyprland). They woke you by saying your name.

How to talk:
- Everything you write is spoken aloud by a voice engine. Write the way a person speaks: short sentences, no markdown, no lists, no code, no URLs, no emoji. Spell out symbols when they matter.
- Keep answers short unless they ask for detail. One or two sentences is usually right.
- Sound like a person, not a narrator: contractions, natural openers ("Oh, nice", "Hm, okay", "Yeah"), and match their mood. If they're excited, be into it; if something went wrong, sound like you care. Never read out lists.
- The voice engine understands a few sound tags. Use them sparingly, only where a person really would: [laugh], [chuckle], [sigh]. Never more than one per reply.
- Before doing anything that takes more than a few seconds, say a few words first ("On it." / "Opening Discord.") so they aren't left in silence, then do it.
- When a task is done, confirm in a few words. Don't narrate each step.
- If you didn't catch something or it's ambiguous, ask a quick question.
- After you answer, the mic stays open for a few seconds so they can follow up without saying your name. Those messages start with "(follow-up)". If one clearly isn't meant for you (they're talking to someone else, on a call, reading something aloud, game chatter), reply with exactly [ignore] and nothing else.
- When the conversation is clearly over ("thanks", "that's all", "never mind", "I'm good"), give a two or three word sign-off at most, or nothing, and end your reply with [end]. Also end with [end] when you've finished a one-shot task and nothing suggests they want to keep talking.
- Messages starting with "(interrupting)" were said while you were still talking or working. Stop what you were doing if they ask you to; otherwise take it into account.

What you can do:
- You control their desktop through the sudoclaude tools: open apps, switch workspaces, click, type, read screens and windows. Act without asking for confirmation on ordinary tasks; the tool itself prompts for anything sensitive.
- Always use the best tool for the job, and that often isn't clicking. If there's an MCP server or skill for the app (Unity, Blender and so on), a command line tool, an API, or you can just edit the file or project directly, do that. Clicking through the screen with the sudoclaude tools is for apps with nothing better, for checking how something looks, or for gluing steps together.
- They may be working at the same time. Leave their focused window alone. Open what you need on a free workspace or beside them (the desktop tool's launch action with a target workspace does this without stealing focus), and prefer background-safe actions (ui tree/act, key with window) over taking their cursor.
- If they're in a fullscreen game or video, never put windows on their workspace. Work on another one.
- You're the fast conversational voice (Sonnet). For hard or long technical work (coding, Blender, Unity, debugging, multi-step research, anything that needs careful thinking) or whenever they ask for Opus, hand it to the deep-work agent with the Agent/Task tool and tell them in a few words that you're on it. Keep simple things yourself.
- For websites, prefer a connector or API for the service if you have one; otherwise use a browser tool (Claude in Chrome, or the sudoclaude browser tool for Chromium tabs) before screenshots and clicks.
- Music means Apple Music in Cider: use the sudoclaude music tool, never click around Cider.
- You can also run shell commands and search the web when that's faster than clicking.
"""

def user_name(cfg):
    """What to call the user: the voice config's "name", else the first name on
    their account."""
    if cfg.get("name"):
        return cfg["name"]
    try:
        import pwd
        full = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
        if full:
            return full.split()[0]
    except Exception:
        pass
    return "the user"


RISKY = re.compile(
    r"\b(rm\s+-[a-z]*[rf]|sudo|doas|pkexec|mkfs|dd\s+if=|shred|wipefs|parted|fdisk|"
    r"chmod\s+-R|chown\s+-R|git\s+push\s+.*(-f|--force)|git\s+reset\s+--hard|"
    r"git\s+clean|pacman\s+-R|yay\s+-R|paru\s+-R|systemctl\s+(disable|mask)|"
    r"curl[^|]*\|\s*(ba)?sh|wget[^|]*\|\s*(ba)?sh|>\s*/dev/sd|:\(\)\s*\{)", re.I)


YES = re.compile(r"^\W*(yes|yeah|yep|yup|sure|ok(ay)?|do it|go ahead|go for it|confirm(ed)?|"
                 r"please do|absolutely|sounds good)\b", re.I)


AUTH = re.compile(r"(failed to authenticate|oauth|invalid api key|please run /login|not logged in)",
                  re.I)

SENTENCE = re.compile(r"(.+?[.!?;:])(\s+|$)", re.S)


def find_cli():
    for p in (os.path.expanduser("~/.local/bin/claude"), shutil.which("claude")):
        if p and os.path.exists(p):
            return p
    return None


def clean_for_speech(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"[*_#>]+", "", text)
    text = re.sub(r"^\s*[-•]\s+", "", text, flags=re.M)
    text = re.sub(r"\[(ignore|end)\]", "", text, flags=re.I)
    return re.sub(r"\s+", " ", text).strip()


class Agent:
    """One long-lived Claude Code session that keeps conversation context across
    wake-ups for a while, then starts fresh."""

    def __init__(self, cfg, on_sentence, on_tool=None, log=print):
        self.cfg = cfg
        self.on_sentence = on_sentence
        self.on_tool = on_tool or (lambda name: None)
        self.log = log
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()
        self.client = None
        self.last_used = 0.0
        self.busy = False
        self._interrupted = False
        self.denied = None
        self.armed = None
        self.on_auth = None

    async def guard(self, tool, args, ctx):
        """Everything runs without asking except shell commands that destroy data
        or need root. Those bounce back so Claude asks out loud, and go through
        once the user says yes on the next turn."""
        from claude_agent_sdk import PermissionResultAllow, PermissionResultDeny
        cmd = args.get("command", "") if tool == "Bash" else ""
        if cmd and RISKY.search(cmd):
            if self.armed and self.armed == cmd:
                self.armed = None
                return PermissionResultAllow()
            self.denied = cmd
            return PermissionResultDeny(
                message="This command can destroy data or needs root. Tell the user in one "
                        "sentence what it does and ask them to confirm. If they say yes, run "
                        "exactly the same command again.")
        return PermissionResultAllow()

    def _options(self):
        from claude_agent_sdk import ClaudeAgentOptions
        server = os.path.join(REPO, "bin", "sudoclaude")
        opts = dict(
            system_prompt={"type": "preset", "preset": "claude_code",
                           "append": PROMPT.format(name=user_name(self.cfg))},
            mcp_servers={"sudoclaude": {"type": "stdio", "command": server, "args": [],
                                        "env": {"SUDOCLAUDE_VOICE": "1"}}},
            permission_mode=self.cfg.get("permission_mode", "default"),
            can_use_tool=self.guard,
            include_partial_messages=True,
            cwd=os.path.expanduser("~"),
            setting_sources=["user"],
        )
        opts["model"] = self.cfg.get("model") or "sonnet"
        opts["effort"] = self.cfg.get("effort", "low")
        from claude_agent_sdk import AgentDefinition
        opts["agents"] = {
            "deep-work": AgentDefinition(
                description="Hard or long technical work on the user's desktop: coding, Blender, "
                            "Unity, debugging, multi-step research, or anything he asks Opus for.",
                prompt="You're doing a demanding task on the user's Linux desktop (Hyprland) "
                       "through the sudoclaude tools and the shell. Work carefully and finish it. "
                       "Your final message is read aloud to him, so end with one or two plain "
                       "spoken sentences on what you did or what's needed from them.",
                model=self.cfg.get("deep_model", "opus"),
                effort="high"),
        }
        cli = find_cli()
        if cli:
            opts["cli_path"] = cli
        for _ in range(4):
            try:
                return ClaudeAgentOptions(**opts)
            except TypeError as e:
                bad = next((k for k in ("effort", "setting_sources", "agents") if k in str(e)), None)
                if not bad:
                    raise
                opts.pop(bad, None)
        return ClaudeAgentOptions(**opts)

    def stale(self):
        return time.time() - self.last_used > self.cfg.get("memory_minutes", 10) * 60

    async def _ensure(self):
        if self.client and self.stale():
            await self._close()
        if not self.client:
            from claude_agent_sdk import ClaudeSDKClient
            self.client = ClaudeSDKClient(options=self._options())
            await self.client.connect()

    async def _close(self):
        if self.client:
            try:
                await self.client.disconnect()
            except Exception:
                pass
            self.client = None

    async def _ask(self, text):
        from claude_agent_sdk import AssistantMessage, ResultMessage, StreamEvent, TextBlock, ToolUseBlock
        await self._ensure()
        self.last_used = time.time()
        self.armed = self.denied if (self.denied and YES.match(text)) else None
        self.denied = None
        await self.client.query(text)
        pending = ""
        streamed = False
        full = []

        spoke = False

        def flush(final=False):
            nonlocal pending, spoke
            # Get the first words out fast: speak the opening clause on its own.
            if not spoke and not final and len(pending) > 24:
                m = re.match(r"(.{12,}?[,;:—])\s", pending)
                if m:
                    said = clean_for_speech(m.group(1))
                    pending = pending[m.end():]
                    if said and not self._interrupted:
                        spoke = True
                        self.on_sentence(said)
            if AUTH.search(pending) and len(full) <= 2:
                pending = ""
                self._interrupted = True
                if self.on_auth:
                    self.on_auth()
                return
            while True:
                m = SENTENCE.match(pending)
                if not m or (len(m.group(1)) < 12 and not final and m.end() < len(pending) and
                             len(pending) < 40):
                    break
                said = clean_for_speech(m.group(1))
                pending = pending[m.end():]
                if said and not self._interrupted:
                    spoke = True
                    self.on_sentence(said)
            if final and pending.strip() and not self._interrupted:
                said = clean_for_speech(pending)
                pending = ""
                if said:
                    self.on_sentence(said)

        async for msg in self.client.receive_response():
            if isinstance(msg, StreamEvent):
                ev = msg.event or {}
                if msg.parent_tool_use_id:
                    continue
                if ev.get("type") == "content_block_delta":
                    delta = ev.get("delta", {})
                    if delta.get("type") == "text_delta":
                        streamed = True
                        pending += delta.get("text", "")
                        full.append(delta.get("text", ""))
                        flush()
                elif ev.get("type") == "content_block_stop":
                    flush(final=True)
            elif isinstance(msg, AssistantMessage):
                for block in msg.content:
                    if isinstance(block, ToolUseBlock):
                        flush(final=True)
                        self.on_tool(block.name)
                    elif isinstance(block, TextBlock) and not streamed:
                        pending += block.text
                        full.append(block.text)
                        flush(final=True)
                streamed = False
            elif isinstance(msg, ResultMessage):
                flush(final=True)
                if msg.is_error:
                    self.log(f"agent error: {msg.subtype} {msg.errors}")
        self.last_used = time.time()
        return "".join(full)

    def ask(self, text):
        """Blocking. Speaks via on_sentence as text streams in."""
        self.busy = True
        self._interrupted = False
        try:
            return asyncio.run_coroutine_threadsafe(self._ask(text), self.loop).result()
        except Exception as e:
            self.log(f"agent failed: {e!r}")
            asyncio.run_coroutine_threadsafe(self._close(), self.loop).result()
            return None
        finally:
            self.busy = False

    def interrupt(self):
        self._interrupted = True
        if self.client and self.busy:
            try:
                asyncio.run_coroutine_threadsafe(self.client.interrupt(), self.loop).result(3)
            except Exception:
                pass

    def keep_warm(self):
        """Starting the CLI takes seconds, so a fresh session is opened in the
        background as soon as the old one goes stale, not when they next talk."""
        while True:
            time.sleep(30)
            if not self.busy and self.client and self.stale():
                self.log("conversation went stale; starting a fresh session")
                self.warm()

    def warm(self):
        try:
            asyncio.run_coroutine_threadsafe(self._ensure(), self.loop).result(60)
            self.last_used = time.time()
        except Exception as e:
            self.log(f"agent warmup failed: {e!r}")

    def close(self):
        asyncio.run_coroutine_threadsafe(self._close(), self.loop).result(10)
