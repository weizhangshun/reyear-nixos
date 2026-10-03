#!/usr/bin/env bash
#
# One-time migration of user `kourtni` from UID 1001 to UID 1000.
#
# Why: WSLg hardcodes /mnt/wslg/runtime-dir to UID 1000 and bind-mounts it over
# /run/user/<default-uid>. When the default user is not 1000 (we were 1001), that
# root-owned mount shadows the per-user runtime dir systemd-logind tries to
# create, so $XDG_RUNTIME_DIR is never set and `user@<uid>.service` fails --
# which means lingering can't actually run any user services. Aligning the
# account to 1000 (the NixOS-WSL + WSLg default) fixes this cleanly.
#
# NixOS refuses to change the UID of an existing account on rebuild (it only
# warns "not applying UID change"), so this must be done manually, as root, with
# no `kourtni` processes running. Run it from a root WSL session:
#
#   # From Windows PowerShell / cmd:
#   wsl --shutdown
#   wsl -d <your-distro-name> -u root        # e.g. `wsl -l` to list names
#   bash /home/kourtni/dotfiles/nixos/migrate-uid-1000.sh
#   exit
#   wsl --shutdown                            # then reopen WSL normally
#
# After reopening as kourtni, apply the (already-updated) config and verify:
#   sudo nixos-rebuild switch --flake ~/dotfiles#wsl
#   loginctl show-user kourtni --property=Linger      # -> Linger=yes
#   ls -la /run/user/$(id -u)/systemd/                # -> exists, owned by you
#
set -euo pipefail

OLD_UID=1001
NEW_UID=1000
USER_NAME=kourtni

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: must run as root (use 'wsl -u root')." >&2
  exit 1
fi

current=$(id -u "$USER_NAME")
if [[ "$current" == "$NEW_UID" ]]; then
  echo "$USER_NAME is already UID $NEW_UID; nothing to do."
  exit 0
fi
if [[ "$current" != "$OLD_UID" ]]; then
  echo "ERROR: expected $USER_NAME to be UID $OLD_UID but it is $current. Aborting." >&2
  exit 1
fi
if getent passwd "$NEW_UID" >/dev/null; then
  echo "ERROR: UID $NEW_UID is already taken: $(getent passwd "$NEW_UID"). Aborting." >&2
  exit 1
fi

echo ">> Terminating any '$USER_NAME' sessions/processes so the UID can change..."
loginctl terminate-user "$USER_NAME" 2>/dev/null || true
pkill -KILL -u "$OLD_UID" 2>/dev/null || true
sleep 1

echo ">> Changing UID: $OLD_UID -> $NEW_UID for '$USER_NAME'..."
usermod -u "$NEW_UID" "$USER_NAME"

# Re-own every file still owned by the old UID. -xdev keeps us on the root
# filesystem, which avoids descending into Windows drives under /mnt and into
# tmpfs mounts like /run; in WSL /, /home, and /nix share one ext4 filesystem.
# Nix store files are root-owned, so they never match -uid "$OLD_UID".
echo ">> Re-owning files from UID $OLD_UID to $NEW_UID (root filesystem only)..."
find / -xdev -uid "$OLD_UID" -print0 2>/dev/null | xargs -0 -r chown -h "$NEW_UID"

echo ">> Done. '$USER_NAME' is now UID $(id -u "$USER_NAME")."
echo ">> Next: exit this shell, run 'wsl --shutdown' from Windows, reopen WSL, then:"
echo "     sudo nixos-rebuild switch --flake ~/dotfiles#wsl"
