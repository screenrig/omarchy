# screenRIG for Omarchy

**[screenRIG](https://screenrig.ai) is free digital signage driven by your AI
agent.** Tell Claude Code, Codex or another agent what to show, and it puts
menus, dashboards, announcements, photos, video and live web pages on any TV,
kiosk or display, with 200+ ready-made apps and
[a Player for every screen](https://screenrig.ai/docs/players). Start at
**[screenrig.ai](https://screenrig.ai)**.

This plugin brings your screenRIG screens to the Omarchy desktop: see every
screen, cast your desktop or an app window live to the TVs around you, and ask
your coding agent to change what plays.

![The screenRIG panel on Omarchy](preview.png)

## What it does

- **Bar chip**: the screenRIG mark in your bar, with a red dot when a screen
  drops, credits run low or a cast is live. Click for the panel, right-click to
  cast a region capture, middle-click to stop a live cast.
- **Screens**: every screen with its latest screenshot, what it plays and when
  it was last seen. Reload, switch playlist, turn the display off, override
  for a while, take a fresh screenshot, restart, or open it in the dashboard.
- **Cast**: a live cast of your desktop or one app window to Android and Linux
  Players on your network, picked from live thumbnails with the arrow keys and
  Return, until you stop it or for a set time; or a region capture, the
  clipboard (an https link or an image) or a file, for 5 to 60 minutes.
- **Agent**: a chat with Claude Code, Codex or Grok and the screenRIG skill,
  resumed across messages. It uses your Omarchy default when its plugin is
  installed, then another installed integration.
- **Project switcher**, a screenRIG section in the Omarchy menu with every
  screen and playlist searchable, and notifications when a screen goes offline
  or comes back, a publish reaches its screens, credits run low, an ad booking
  needs review, or a live cast starts or stops.

| Cast live | While casting | Agent |
|---|---|---|
| ![Cast tab](listing/images/cast.png) | ![Live cast status](listing/images/casting.png) | ![Agent chat](listing/images/agent.png) |

## Install

```sh
omarchy plugin add https://github.com/screenrig/omarchy --enable
```

On first open the panel detects the official
[screenRIG plugin](https://github.com/screenrig/plugin) in Claude Code, Codex
and Grok. If it needs installing, **Install** adds its skill and CLI to the
available agent named in the panel, preferring your Omarchy default.
**Sign in** approves this laptop at screenrig.ai. Already have the plugin and
`screenrig login`? The panel uses that sign-in
(`~/.config/screenrig/config.json`) and lets the CLI renew it.

## Remove

```sh
screenrig-omarchy teardown && omarchy plugin remove screenrig.omarchy
```

`teardown` stops a live cast and undoes everything below; from a checkout,
`./install.sh --uninstall` does both steps.

## What it changes on your system

On first load it adds, and `teardown` removes:

- links `screenrig-omarchy` and `screenrig-share-picker` in `~/.local/bin`;
- a generated, marked block of screenRIG rows in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (your own rows are kept);
- two `.desktop` entries (the panel, and "Cast to a screenRIG screen" for files)
  and a theme hook in `~/.config/omarchy/hooks/theme-set.d/`.

**Install** on the first-run card runs Claude Code, Codex or Grok's own
plugin installer for github.com/screenrig/plugin; remove it with that agent's
plugin commands.

Live casting changes two more things, only after you press **Allow** in the
Cast tab:

- with ufw on, a rule letting your LAN subnet reach TCP 8554 (the stream);
- for window casts, xdg-desktop-portal-hyprland's `custom_picker_binary`
  points at `screenrig-share-picker`, which answers the portal for the window
  you picked in the panel and runs your previous picker for every other screen
  share. The previous value is kept and restored by `teardown`.

## Requirements

- Omarchy 4.5 (Quickshell shell), Python 3.
- The screenRIG agent plugin and its bundled CLI (Node.js), signed in: the first-run card installs both.
- `grim`, `slurp`, `wl-clipboard`, `zenity` for captures, the clipboard and
  files.
- Live casting: `gpu-screen-recorder` and `ffmpeg`. On the first cast the
  plugin downloads [mediamtx](https://github.com/bluenviron/mediamtx) v1.21.3,
  checks it against the release's published SHA-256 and keeps it in
  `~/.local/share/screenrig-omarchy/bin`; it serves RTSP over TCP on port 8554.
  Screens reach it on the same network: Android and Linux Players.
- Agent: Claude Code, Codex or Grok with the screenRIG plugin. The panel
  detects installed integrations and prefers your Omarchy default agent
  (`omarchy default agent`).

## Keybindings

```lua
o.bind("SUPER + ALT + D", "screenRIG screens", [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"screens"}']])
o.bind("SUPER + ALT + C", "screenRIG cast",    [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"cast"}']])
o.bind("SUPER + ALT + A", "screenRIG agent",   [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"agent"}']])
o.bind("SUPER + ALT + X", "Stop casting",      [[omarchy-shell shell call screenrig.omarchy stopCast ""]])
```

## License

MIT, see [LICENSE](LICENSE).
