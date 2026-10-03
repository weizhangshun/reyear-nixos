#!/usr/bin/env bash
# Show a searchable cheatsheet of all keybinds, read live from the running
# compositor via `hyprctl binds -j` and formatted by keybinds.py.

hyprctl binds -j | python3 "$HOME/.config/hypr/scripts/keybinds.py" \
    | wofi --dmenu --insensitive --prompt "Keybinds" --width 720 --height 560 \
        --style "$HOME/.config/hypr/scripts/keybinds.css" > /dev/null
