# SudoClaude

Computer use for Linux. It lets Claude see the screen, move its own cursor, type, open apps and actually work inside them, like the computer use Claude already has on macOS and Windows. Right now it's built around my own setup (Garuda with Hyprland and the end-4 dots), so I haven't tried it on anything else yet.

It runs as a local MCP server, so the Claude desktop app and Claude Code can both use it.

## Install

```sh
git clone https://github.com/splitshotz/SudoClaude ~/Projects/SudoClaude
cd ~/Projects/SudoClaude
./install.sh
```

The script installs what's missing with pacman, adds the server to `~/.config/Claude/claude_desktop_config.json` (it backs that file up first), registers it with Claude Code if you have it, and runs a quick self-test. Quit Claude from the tray icon and open it again so it loads.

## What it can do

Anything you'd do with a mouse and keyboard. That includes every kind of click, click and hold, pressing and releasing any mouse button, drags, smooth paths through several points, relative mouse movement for games, scrolling in any direction, typing any unicode, any key combo (raw keycodes too), and holding keys down across other actions, like holding W while moving the mouse.

There are five tools:

- `computer` covers the screen, mouse and keyboard. It uses the same action names as Claude's own computer use, and it takes a whole list of actions at once, so Claude can plan a sequence of moves and run it in one go instead of checking after every step.
- `open_application` opens anything with a .desktop entry by name, or focuses it if it's already running, and waits for the window.
- `desktop` handles Hyprland: workspaces (special ones too), windows, monitors, launching commands, the clipboard, and my keybinds with the same labels the Super+/ cheatsheet shows. Those come from the live config, so if I change a bind it picks that up.
- `ui` reads an app's real interface through AT-SPI (buttons, fields, menus, tabs with their labels and positions) and can press, fill in or toggle things without touching the mouse. It also has OCR for apps that don't expose anything.
- `access` is for the few sensitive apps that need a yes from me first.

Screenshots can also grab a single window, even one on another workspace or under other windows, and shortcuts can go to a window in the background.

## Keeping usage down

Screenshots are what eat into usage, so Claude only looks at what it needs. It can screenshot just a region or one window, and it can switch its view to the focused window or a fixed area so every check after that only covers that part. A dialog-sized region costs around 200 tokens, while the whole ultrawide is roughly 500, 900 or 1,400 depending on the detail level. It can switch back to the full screen whenever it needs the bigger picture. After an action Claude can ask for a `diff` instead of an image, which is a line of text saying whether the screen changed and where, and then zoom into just that part if it needs to. The accessibility tree and window lists are plain text and usually cheaper than looking. The tool definitions themselves come to about 1,700 tokens.

## How it works

Input goes through the Wayland virtual pointer and virtual keyboard protocols over one socket the server keeps open, which means no ydotool, no root and no extra daemon, and each action takes well under a millisecond. Screenshots come from wlr-screencopy in the same process (about 10 ms) and get scaled to a size Claude reads well. A 3440x1440 monitor comes out at 1568x656. Coordinates map back exactly, HiDPI and mixed scaling included. Window captures use Hyprland's toplevel export, and windows, workspaces and binds come from the Hyprland IPC socket.

## Permissions

Ask it to do something and it does it. Opening apps, clicking around, typing in a terminal and switching workspaces all happen without a confirmation dialog.

It only stops to ask for things that are actually sensitive: password managers, software installers and package managers, disk and partition tools, system settings, and reading the clipboard (which tends to have passwords in it). You get one dialog with allow for this session, always allow, or deny, and windows from those apps stay blacked out in Claude's screenshots until you allow them. Claude can never control itself, its own approval dialogs or polkit prompts.

If you want the stricter rules Claude uses on macOS (browsers view only, terminals and IDEs click only, a dialog for every new app), set `"approvals": "strict"`.

Only one Claude session can drive the desktop at a time.

To stop it, press Esc or click Stop on the pill at the bottom of the screen. The Esc part is a temporary bind that only exists while Claude is working. It doesn't swallow the key and it doesn't change any of your own binds.

## The overlay

While Claude is working there's a soft orange glow around the edge of the screen, a small cursor of its own with a "Claude" tag that glides to wherever it's clicking, and a glass pill that says what it's doing. It runs on Quickshell as its own layer. Your mouse goes right through it, and it disappears for the instant Claude takes a screenshot so it never confuses itself. The pill gets Hyprland's blur through a layer rule the server adds at runtime, so nothing in your config changes. When Claude goes idle the whole thing fades out and unmaps, so it doesn't get in the way of fullscreen games.

## Config

Settings live in `~/.config/sudoclaude/config.json`:

```json
{
  "approvals": "smart",
  "session_minutes": 60,
  "always_allow": [],
  "denied": [],
  "sensitive": ["signal"],
  "tier_overrides": {},
  "mask_unapproved": true,
  "esc_to_stop": true,
  "notifications": true,
  "overlay": true,
  "idle_seconds": 25
}
```

`sensitive` adds your own window classes to the ask-first list, and `denied` blocks apps completely. `approvals` can be `smart` (the default), `strict`, or `off`, which never asks about anything. `tier_overrides` takes `view`, `click` or `full` per window class and mostly matters in strict mode.

## If something's off

Run the `doctor` tool, or ask Claude to. It reports the compositor, which protocols are there, the overlay and accessibility status, and how long a screenshot takes.

If Hyprland has `ecosystem:enforce_permissions` on, Python needs screen capture permission:

```
permission = /usr/bin/python3.*, screencopy, allow
```

Electron apps like VS Code and Discord only expose their accessibility tree if they start after it's turned on, which SudoClaude does the first time you use `accessibility_tree`. Restart them once after that.

The overlay logs to `$XDG_RUNTIME_DIR/sudoclaude-overlay.log`.

## License

GPL-3.0
