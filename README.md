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

The basics are all here: screenshots, clicking, dragging, scrolling, typing (any unicode), key combos, holding keys, and zooming in on part of the screen at full resolution. On top of that:

- `open_application` opens anything with a .desktop entry by name, or focuses it if it's already running, and waits for the window
- `accessibility_tree` and `a11y_action` read an app's real UI through AT-SPI (buttons, fields, menus, tabs, with their labels and positions) and can press, fill in or toggle things without touching the mouse
- `screenshot` with a window grabs just that window, even if it's on another workspace or covered up
- `key` with a window sends shortcuts to a window in the background
- `desktop_state`, `workspace` and `focus_window` know about workspaces, special workspaces and the bar
- `keybinds` lists my live Hyprland binds with the same descriptions and sections the Super+/ cheatsheet shows, read straight from the config comments, so if I change a bind it picks that up
- `batch` runs a whole sequence of actions and comes back with one screenshot
- `find_text` uses OCR to find a label on screen when an app has no accessibility tree

## How it works

Input goes through the Wayland virtual pointer and virtual keyboard protocols over one socket the server keeps open, which means no ydotool, no root and no extra daemon, and each action takes well under a millisecond. Screenshots come from wlr-screencopy in the same process (about 10 ms) and get scaled to a size Claude reads well. A 3440x1440 monitor comes out at 1568x656. Coordinates map back exactly, HiDPI and mixed scaling included. Window captures use Hyprland's toplevel export, and windows, workspaces and binds come from the Hyprland IPC socket.

## Permissions

The first time Claude needs an app you get a dialog with three choices: allow for this session (an hour by default), always allow, or deny. It follows the same rules as Claude's own computer use. Browsers are view only and terminals and IDEs are click only, and apps that are basically shell access, like terminals, file managers and settings, come with a warning in the dialog. Password managers start out denied. Claude can never control itself, its own approval dialogs or polkit prompts. Windows you haven't approved show up blacked out in its screenshots.

Only one Claude session can drive the desktop at a time.

To stop it, press Esc or click Stop on the pill at the bottom of the screen. The Esc part is a temporary bind that only exists while Claude is working. It doesn't swallow the key and it doesn't change any of your own binds.

## The overlay

While Claude is working there's a soft orange glow around the edge of the screen, a small cursor of its own with a "Claude" tag that glides to wherever it's clicking, and a glass pill that says what it's doing. It runs on Quickshell as its own layer. Your mouse goes right through it, and it disappears for the instant Claude takes a screenshot so it never confuses itself. The pill gets Hyprland's blur through a layer rule the server adds at runtime, so nothing in your config changes. When Claude goes idle the whole thing fades out and unmaps, so it doesn't get in the way of fullscreen games.

## Config

Settings live in `~/.config/sudoclaude/config.json`:

```json
{
  "approvals": "prompt",
  "session_minutes": 60,
  "always_allow": [],
  "denied": ["bitwarden", "keepassxc", "1password"],
  "tier_overrides": {"zen": "full"},
  "mask_unapproved": true,
  "esc_to_stop": true,
  "notifications": true,
  "overlay": true,
  "idle_seconds": 25
}
```

`tier_overrides` takes `view`, `click` or `full` per window class, so you can give a browser full control if you want. Setting `approvals` to `off` skips the dialogs entirely, which I wouldn't do.

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
