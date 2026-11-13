### Repository URL

https://github.com/screenrig/omarchy

### Category

Productivity

### Tags

ai
media
quickshell

### Suggest a missing tag

signage

### Maintainer notes

On load it adds a marked block of screenRIG rows to ~/.config/omarchy/extensions/omarchy-menu.jsonc, keeping the user's own rows, plus two .desktop entries and a theme-set hook. Live casting asks before changing the system: with ufw on it adds one rule for TCP 8554 from the LAN subnet. A window cast asks which window through the desktop's own screen-share picker; the plugin does not touch the portal's configuration. `screenrig-omarchy teardown` undoes everything the plugin set up. The first live cast downloads mediamtx v1.21.3 and verifies it against a SHA-256 pinned in the plugin's source. The recorder's command line carries no login: it publishes through a loopback port of the plugin that admits only the recorder's own connection, and the plugin sends the picture and the logins to TCP 8554 only on a connection whose other end is its own mediamtx (README, "How a live cast is guarded"). One process owns a cast and its stream server and recorder die with it; it ends a timed cast itself. Chat messages are on no command line. The plugin needs the screenRIG CLI's sign-in.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
