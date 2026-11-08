# screenRIG for Omarchy

Your [screenRIG](https://screenrig.ai) screens on the Omarchy desktop.

- **Bar chip**: the screenRIG mark; a red dot when a screen drops, credits run
  low or a cast is live. Click for the panel, right-click to cast a capture,
  middle-click to stop a live cast.
- **Screens**: every screen with its latest screenshot, what it plays and when
  it was last seen; reload, switch playlist, turn the display off, override
  for a while, take a fresh screenshot, restart, open in the dashboard.
- **Cast**: a live cast of your desktop or one app window to Android and Linux
  Players on the same network, picked from live thumbnails with the arrow keys
  and Return; or a region capture, the clipboard (an https link or an image) or
  a file, for 5 to 60 minutes. Files also open with "Cast to a screenRIG
  screen" from the file manager.
- **Agent**: a chat with your default coding agent (Claude Code or Codex) using
  the screenRIG skill, resumed across messages.
- **Project switcher** in the panel header, and a screenRIG section in the
  Omarchy menu with every screen and playlist searchable.
- **Notifications**: a screen goes offline or comes back, a publish reaches
  its screens, credits run low, an ad booking needs your review, a live cast
  starts or stops.

## Install

```sh
omarchy plugin add https://github.com/screenrig/omarchy --enable
```

or from a checkout, `./install.sh` (`./install.sh --uninstall` removes it).

It uses the screenRIG CLI's sign-in (`~/.config/screenrig/config.json`): sign
in with `screenrig login` after installing the
[screenRIG plugin](https://github.com/screenrig/plugin) for your agent.

Live casts need `gpu-screen-recorder` and `ffmpeg`; the plugin downloads a
checksummed `mediamtx` on the first cast and serves RTSP over TCP on port 8554.
With ufw on, the first cast adds a rule for that port from your LAN. Window
casts answer xdg-desktop-portal-hyprland's picker for the window picked in the
panel and run your own picker for every other screen share.

## Keybindings

```lua
o.bind("SUPER + ALT + D", "screenRIG screens", [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"screens"}']])
o.bind("SUPER + ALT + C", "screenRIG cast",    [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"cast"}']])
o.bind("SUPER + ALT + A", "screenRIG agent",   [[omarchy-shell shell toggle screenrig.omarchy '{"mode":"agent"}']])
o.bind("SUPER + ALT + X", "Stop casting",      [[omarchy-shell shell call screenrig.omarchy stopCast ""]])
```

## License

MIT, see [LICENSE](LICENSE).
