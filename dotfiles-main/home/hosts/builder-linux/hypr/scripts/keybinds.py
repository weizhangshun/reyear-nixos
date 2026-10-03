#!/usr/bin/env python3
"""Format `hyprctl binds -j` (on stdin) as a keybind cheatsheet, one bind per line.

Each bind's `description` flag from hyprland.lua is used as its label; binds
without one fall back to "dispatcher arg".
"""
import json
import sys

MODS = [(64, "SUPER"), (8, "ALT"), (4, "CTRL"), (1, "SHIFT")]


def combo(bind):
    parts = [name for bit, name in MODS if bind["modmask"] & bit]
    parts.append(bind["key"] or "code:%s" % bind["keycode"])
    return " + ".join(parts)


for bind in json.load(sys.stdin):
    if bind.get("submap"):
        continue
    label = bind["description"] or ("%s %s" % (bind["dispatcher"], bind["arg"])).strip()
    print("%-22s  %s" % (combo(bind), label))
