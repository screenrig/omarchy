#!/usr/bin/env bash
# Install or update the screenRIG Omarchy plugin from this checkout.
# `omarchy plugin add https://github.com/screenrig/omarchy` does the same from
# GitHub; the plugin sets up its helper, menus and desktop entries on first load.
#   ./install.sh               copy the plugin, set it up, enable the bar chip
#   ./install.sh --uninstall   undo its setup (teardown) and remove it
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
id=screenrig.omarchy
dest="$HOME/.config/omarchy/plugins/$id"

# The shell reloads a changed plugin at once, which strands a locked screen's
# lock: refuse while any graphical session of this user is locked.
for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -un)" '$3 == u {print $1}'); do
  if [[ $(loginctl show-session "$s" -p Type --value 2>/dev/null) =~ ^(wayland|x11)$ &&
        $(loginctl show-session "$s" -p LockedHint --value 2>/dev/null) == yes ]]; then
    echo "The screen is locked (session $s): unlock it, then run this again" >&2
    exit 1
  fi
done

if [[ ${1:-} == --uninstall ]]; then
  "$dest/bin/screenrig-omarchy" teardown || true
  omarchy plugin disable "$id" >/dev/null 2>&1 || true
  rm -rf "$dest"
  echo "Removed $id"
  exit 0
fi

mkdir -p "$dest"
tar -C "$src" --exclude=.git --exclude=__pycache__ --exclude=tests --exclude=listing --exclude=preview.png -cf - . | tar -C "$dest" -xf -
chmod 755 "$dest/bin/"*
omarchy plugin validate "$dest"
"$dest/bin/screenrig-omarchy" setup >/dev/null

enabled() { omarchy plugin list --json 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if any(p["id"] == sys.argv[1] and p["enabled"] for p in json.load(sys.stdin)) else 1)' "$id"; }
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if ! enabled; then
  for _ in 1 2 3 4 5; do omarchy plugin enable "$id" right >/dev/null 2>&1 && break; sleep 1; done
  enabled || { echo "Enable failed: run omarchy plugin enable $id right" >&2; exit 1; }
fi
echo "Installed $id"
