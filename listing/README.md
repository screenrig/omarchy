# Marketplace listing

Copy and images for the Omarchy plugin marketplace
([plugins.omarchy.org](https://plugins.omarchy.org), submitted through
[omacom/omarchy-plugin-marketplace](https://github.com/omacom/omarchy-plugin-marketplace)).
The marketplace reads the root `manifest.json`, `README.md`, `LICENSE` and
`preview.png`; this folder keeps the listing copy, the submission and the
screenshots together.

## Listing

| Field | Value |
|---|---|
| Name | screenRIG |
| Plugin ID | `screenrig.omarchy` |
| Repository | https://github.com/screenrig/omarchy |
| Category | Productivity |
| Tags | `ai`, `media`, `quickshell` |
| Preview | `../preview.png` (the Screens panel) |

**Summary** (manifest `description`): Your screenRIG screens on the Omarchy
desktop: bar chip, screens panel, live cast and cast to screens, agent chat and
notifications.

**Description**

screenRIG puts the signage screens around you on your Omarchy desktop. A bar
chip shows when a screen drops; the panel shows every screen with its latest
screenshot and what it plays, and reloads, switches, overrides or blanks any of
them. Cast streams your desktop or one app window live to the Android and Linux
Players on your network, picked from live thumbnails with the arrow keys, or
sends a capture, a link or a file for a few minutes. The Agent tab is a chat
with your default coding agent and the screenRIG skill: tell it what to put
on which screen. A project switcher, menu rows for every screen and playlist,
and notifications round it out.

## Screenshots

| File | Shows |
|---|---|
| `images/screens.png` | Screens: every screen with its screenshot, status and actions |
| `images/cast.png` | Cast: live thumbnails of the desktop and app windows, local screens |
| `images/casting.png` | A live cast running, with its timer and Stop |
| `images/agent.png` | Agent: a chat that puts sales numbers on a lobby screen |

The screenshots show demo content (project "Acme HQ").

## Submission

`submission.md` is the issue body for
`gh issue create --repo omacom/omarchy-plugin-marketplace --title "[Plugin]: screenRIG" --body-file listing/submission.md`.
Every checklist item is the owner's confirmation: tick them only after the
owner has confirmed each one.
