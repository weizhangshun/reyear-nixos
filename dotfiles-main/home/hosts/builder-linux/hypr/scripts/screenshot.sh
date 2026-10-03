#!/usr/bin/env bash

set -u

screenshot_dir="$HOME/Pictures/Screenshots"
mkdir -p "$screenshot_dir"
screenshot_file="$screenshot_dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

case "${1:-}" in
    full)
        grim "$screenshot_file" || exit 1
        ;;
    region)
        geometry="$(slurp)" || exit 0
        grim -g "$geometry" "$screenshot_file" || exit 1
        ;;
    *)
        echo "Usage: $0 {full|region}" >&2
        exit 2
        ;;
esac

wl-copy < "$screenshot_file"
