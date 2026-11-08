# screenRIG for Omarchy

Omarchy shell plugin `screenrig.omarchy`:

- `Service.qml` runs `bin/screenrig-omarchy follow --notify` (project snapshot,
  event stream, notifications), the agent chat and live-cast state, and runs
  `bin/screenrig-omarchy setup` on load.
- `BarWidget.qml` is the bar chip (`Logomark.qml`); `Panel.qml` is the panel
  (Screens, Cast, Agent); `LogoCharacter.qml` is the animated logomark.
- `bin/screenrig-omarchy` owns every API call, the menu block in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`, live casts and setup;
  `bin/screenrig-share-picker` is the xdg-desktop-portal-hyprland picker.

Rules:

- Auth: the helper reads the screenRIG CLI config and never refreshes tokens
  itself; a free CLI call lets the CLI rotate the refresh token.
- No symlinks inside the plugin folder (`omarchy plugin validate`).
- Never print tokens, fleet links, pairing codes or `Authorization` headers.
- Gate: `python3 -m unittest discover -s tests` and `omarchy plugin validate .`.
