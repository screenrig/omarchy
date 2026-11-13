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
- Never put a login, token or the person's chat message on a command line:
  every account on the machine can read it. The recorder publishes through
  `live-capture`'s loopback gate, which holds the publishing login; a chat
  message goes to the helper in the environment and to the agent on stdin.
- The agent's brief (`AGENT_BRIEF`) is constant: nothing from the project or
  the API goes into an instruction file. The `ask` IPC call writes a draft;
  the person sends it.
- A stored pid is a process only with its start time (`cast_process`).
- Nothing goes to TCP 8554 except through `server_connection`, which checks
  that the connection's other end is the cast's own mediamtx.
- Gate: `python3 -m unittest discover -s tests` and `omarchy plugin validate .`.

UI:

- Check every change from a screenshot of the real panel, not the QML.
- Size each view to its content; one primary action per view; no ellipses on
  buttons; hide tabs that are not ready.
- While a cast runs, its status and Stop replace the picker, and Stop stays on
  every tab. Remember the last tab, source and screens.
- Theme tokens only (`Color`, `Style`); motion through `root.d()` with
  ease-out; pulse only for attention states.
