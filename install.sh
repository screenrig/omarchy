#!/usr/bin/env bash
# Install or update the screenRIG Omarchy plugin from this checkout.
# `omarchy plugin add https://github.com/screenrig/omarchy` does the same from
# GitHub; the plugin sets up its helper, menus and picker on first load.
#   ./install.sh               copy the plugin, set it up, enable the bar chip
#   ./install.sh --uninstall   remove it and restore the screen-share picker
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
id=screenrig.omarchy
dest="$HOME/.config/omarchy/plugins/$id"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
state="${XDG_STATE_HOME:-$HOME/.local/state}/screenrig-omarchy"
xdph="$HOME/.config/hypr/xdph.conf"

if [[ ${1:-} == --uninstall ]]; then
  if [[ -f $state/xdph-original-picker ]] && grep -q "screenrig-share-picker" "$xdph" 2>/dev/null; then
    original=$(<"$state/xdph-original-picker")
    sed -i "s#^\(\s*custom_picker_binary\s*=\s*\).*#\1$original#" "$xdph"
    systemctl --user try-restart xdg-desktop-portal-hyprland >/dev/null 2>&1 || true
  fi
  "$dest/bin/screenrig-omarchy" live-stop >/dev/null 2>&1 || true
  "$dest/bin/screenrig-omarchy" menu-remove >/dev/null 2>&1 || true
  omarchy plugin disable "$id" >/dev/null 2>&1 || true
  for link in "$HOME/.local/bin/screenrig-omarchy" "$HOME/.local/bin/screenrig-share-picker"; do
    [[ -L $link ]] && rm "$link"
  done
  rm -rf "$dest" "$HOME/.config/omarchy/hooks/theme-set.d/50-screenrig" \
    "$apps/screenrig-omarchy.desktop" "$apps/screenrig-send.desktop"
  echo "Removed $id"
  exit 0
fi

mkdir -p "$dest"
tar -C "$src" --exclude=.git --exclude=__pycache__ --exclude=tests -cf - . | tar -C "$dest" -xf -
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
