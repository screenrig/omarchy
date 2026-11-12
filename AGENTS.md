# screenRIG for Omarchy

Omarchy shell plugin `screenrig.omarchy`. `Service.qml` runs
`bin/screenrig-omarchy follow --notify` (project snapshot, event stream,
notifications), the agent chat and live-cast state, and runs
`bin/screenrig-omarchy setup` on load. `bin/screenrig-omarchy` owns every API
call, the menu block in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, live
casts and setup.

Rules:

- Auth: the helper reads the screenRIG CLI config and never refreshes tokens
  itself; a free CLI call lets the CLI rotate the refresh token.
- No symlinks inside the plugin folder (`omarchy plugin validate`).
- Never print fleet links.
- A window cast goes through the desktop's screen-share picker. Never answer
  the portal for the person or set `custom_picker_binary`: a picker cannot
  tell which app is asking.
- Gate: `python3 -m unittest discover -s tests` and `omarchy plugin validate .`.

UI:

- Check every change from a screenshot of the real panel, not the QML.
- Size each view to its content; one primary action per view; no ellipses on
  buttons; hide tabs that are not ready.
- While a cast runs, its status and Stop replace the picker, and Stop stays on
  every tab. Remember the last tab, source and screens.
- Theme tokens only (`Color`, `Style`); motion through `root.d()` with
  ease-out; pulse only for attention states.
