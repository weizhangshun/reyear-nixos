#!/usr/bin/env bash
set -euo pipefail
# Bootstrap a fresh Arch Linux install into a builder-linux* GitHub Actions
# runner box matching the existing one. Run as the regular (wheel) user, not
# root. Every step is idempotent, so re-running after fixing something is safe.
#
# Environment overrides:
#   RUNNER_NAME    runner name to register (default: hostname)
#   RUNNER_LABELS  extra comma-separated labels (default: nix-native, matching builder-linux1)
#   RUNNER_REPO    owner/repo the runner is registered to (default: Chan-Ko-LLC/ck)
#   RUNNER_TOKEN   registration token; fetched via `gh` if unset and gh is logged in
#   RUNNER_USER    account the runner and its jobs run as (default: github-runner)
#   TIMEZONE       IANA timezone for the box (default: America/Chicago)

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_DIR="$DOTFILES/arch"
RUNNER_REPO="${RUNNER_REPO:-Chan-Ko-LLC/ck}"
RUNNER_NAME="${RUNNER_NAME:-$(hostnamectl --static)}"
RUNNER_LABELS="${RUNNER_LABELS:-nix-native}"
# Jobs run as RUNNER_USER, never as you: anyone who can land a workflow change
# can run code as that account. It is created below with no sudo, no login
# shell and a 0700 home of its own, so jobs cannot reach your keys or tokens.
RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_HOME="/home/$RUNNER_USER"
RUNNER_DIR="$RUNNER_HOME/actions-runner"
TIMEZONE="${TIMEZONE:-America/Chicago}"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your regular user, not root (it uses sudo where needed)." >&2
    exit 1
fi
if [ ! -f /etc/arch-release ]; then
    echo "This script is for Arch Linux only." >&2
    exit 1
fi

# Ask for the sudo password once and keep the session alive for the whole
# run, so a long AUR build does not end with an expired sudo prompt.
log "Checking sudo access"
sudo -v
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# Do this before pacman: a box with no timezone reports UTC, and a box with no
# time sync drifts until TLS certificate checks start failing. builder-linux2
# shipped with neither, which is why its clock read five hours off
# builder-linux1's. Both settings are host state, not package state, so
# nothing else in this repo restores them.
log "Setting the timezone and enabling time sync"
if [ "$(timedatectl show -p Timezone --value)" != "$TIMEZONE" ]; then
    sudo timedatectl set-timezone "$TIMEZONE"
fi
if [ "$(timedatectl show -p NTP --value)" != "yes" ]; then
    sudo timedatectl set-ntp true
fi

log "Checking that the package mirrors respond"
if ! timeout 90 sudo pacman -Sy >/dev/null 2>&1; then
    warn "pacman could not sync in 90s; the mirrorlist copied from the ISO is probably stale. Falling back to two known-good mirrors."
    sudo tee /etc/pacman.d/mirrorlist >/dev/null <<'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirrors.xtom.com/archlinux/$repo/os/$arch
MIRRORS
    sudo pacman -Syy
fi

log "Installing packages from the official repos"
# shellcheck disable=SC2024  # stdin is the package list, not a privileged file
sudo pacman -Syu --needed --noconfirm - < "$ARCH_DIR/pkglist-native.txt"

if ! command -v paru >/dev/null 2>&1; then
    log "Bootstrapping paru (AUR helper)"
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -s --noconfirm)
    sudo pacman -U --noconfirm "$tmp"/paru/paru-[0-9]*.pkg.tar.zst
    rm -rf "$tmp"
fi

log "Installing AUR packages"
paru -S --needed --noconfirm - < "$ARCH_DIR/pkglist-aur.txt"

log "Installing zram swap config"
sudo install -Dm644 "$ARCH_DIR/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo systemctl daemon-reload
sudo systemctl start /dev/zram0
if ! swapon --show=NAME --noheadings | grep -q '^/dev/zram0$'; then
    warn "zram0 is not active as swap; check 'systemctl status systemd-zram-setup@zram0.service'."
fi

log "Configuring the Nix daemon"
features="$(grep -E '^experimental-features' /etc/nix/nix.conf 2>/dev/null || true)"
if [ -z "$features" ]; then
    echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf >/dev/null
elif ! { grep -qw nix-command <<<"$features" && grep -qw flakes <<<"$features"; }; then
    sudo sed -i -E 's/^(experimental-features *=.*)$/\1 nix-command flakes/' /etc/nix/nix.conf
fi
# Arch's nix package has no nix-users group; the daemon socket is world-writable,
# so any user can talk to it once nix-daemon is running.

log "Enabling system services"
sudo systemctl enable --now NetworkManager.service sshd.service nix-daemon.service
sudo systemctl enable sddm.service

# Every box installs both `linux` and `linux-lts` and boots LTS. grub-mkconfig
# otherwise picks the top-level entry by sorting the vmlinuz-* filenames, so
# which kernel boots depends on which kernels existed when grub.cfg was last
# generated -- that is how builder-linux1 ended up on mainline and
# builder-linux2 on LTS from an identical package set.
log "Pinning the default boot kernel to linux-lts"
if [ ! -f /boot/vmlinuz-linux-lts ]; then
    warn "/boot/vmlinuz-linux-lts is missing; skipping the kernel pin. Install linux-lts and re-run this script."
else
    pin='GRUB_TOP_LEVEL="/boot/vmlinuz-linux-lts"'
    if ! grep -qxF "$pin" /etc/default/grub; then
        sudo sed -i '/^GRUB_TOP_LEVEL=/d' /etc/default/grub
        echo "$pin" | sudo tee -a /etc/default/grub >/dev/null
    fi
    default_entry="$(grep -E '^GRUB_DEFAULT=' /etc/default/grub | cut -d= -f2- | tr -d '\"')"
    if [ -n "$default_entry" ] && [ "$default_entry" != 0 ]; then
        warn "GRUB_DEFAULT is '$default_entry', not 0; the kernel pin only controls the first menu entry."
    fi
    # The pin only takes effect through grub-mkconfig, and a grub.cfg written
    # before linux-lts was installed keeps booting the old default forever, so
    # regenerate whenever the top-level entry is not already the LTS kernel.
    if [ "$(grep -m1 -oE '/vmlinuz-linux(-lts)?' /boot/grub/grub.cfg || true)" != /vmlinuz-linux-lts ]; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    case "$(uname -r)" in
        *-lts) ;;
        *) warn "Running $(uname -r); reboot to switch this box to the LTS kernel." ;;
    esac
fi

# Arch's nix package ships no /nix/store; the daemon creates it lazily, and a
# client that races it fails with 'opening file "/nix/store": No such file'.
if [ ! -d /nix/store ]; then
    log "Initialising the Nix store"
    sudo install -d -o root -g nixbld -m 1775 /nix/store
    sudo install -d -m 755 /nix/var/nix/db /nix/var/nix/profiles /nix/var/nix/gcroots /nix/var/nix/temproots
    sudo systemctl restart nix-daemon.service
fi
if ! nix store info >/dev/null 2>&1 && ! nix store ping >/dev/null 2>&1; then
    warn "Cannot talk to the Nix daemon. Check 'systemctl status nix-daemon.service' and re-run this script."
    exit 1
fi

# The runner is only registered once the host is fully configured, so a
# half-built box never starts picking up jobs.
HOST_READY=
if [ -f "$DOTFILES/user-config.nix" ]; then
    log "Applying Home Manager configuration"
    # -b backup moves aside files Home Manager wants to own (e.g. the .bashrc from /etc/skel).
    (cd "$DOTFILES" && nix run .#home-manager -- switch -b backup --flake ".#$USER@x86_64-linux")
    HOST_READY=1
else
    warn "$DOTFILES/user-config.nix is missing. Copy it (and ~/.config/sops/age/keys.txt) from the existing box, then re-run this script."
fi

# A runner registered by an earlier version of this script lives in your own
# home and runs as you. Registering a second one under the same name fails, so
# stop and point at the one-time migration instead of guessing.
if [ -f "$HOME/actions-runner/.runner" ] && [ "$HOME/actions-runner" != "$RUNNER_DIR" ]; then
    warn "A runner is still registered as $USER in $HOME/actions-runner. Move it to $RUNNER_USER first: see \"Moving a runner off your account\" in $ARCH_DIR/README.md."
    exit 1
fi

if [ "$RUNNER_USER" = "$USER" ]; then
    warn "RUNNER_USER is your own account; jobs would run with your sudo and keys. Pick a dedicated account."
    exit 1
fi

# Workflow jobs run as RUNNER_USER and control every file in its home: any of
# them can become a symlink or a script of the job's choosing. So nothing below
# lets root touch that home. Commands there run as RUNNER_USER, and root only
# writes the systemd unit and drop-in, named from RUNNER_REPO and RUNNER_NAME,
# never from anything read out of the runner directory. In particular root
# never runs the runner's svc.sh, which a job could have rewritten.
as_runner() { sudo -u "$RUNNER_USER" -H env -C "$RUNNER_DIR" "$@"; }
runner_has() { sudo -u "$RUNNER_USER" test -e "$RUNNER_DIR/$1"; }

log "Creating the $RUNNER_USER account"
if ! id "$RUNNER_USER" >/dev/null 2>&1; then
    # useradd leaves the password locked; nologin keeps SSH and the console out.
    sudo useradd --create-home --home-dir "$RUNNER_HOME" --gid users \
        --shell /usr/bin/nologin "$RUNNER_USER"
fi
if id -nG "$RUNNER_USER" | grep -qw wheel; then
    warn "$RUNNER_USER is in wheel, so every job could sudo. Remove it with: sudo gpasswd -d $RUNNER_USER wheel"
    exit 1
fi

log "Installing the GitHub Actions runner"
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
if ! runner_has config.sh; then
    # Capture first, then parse: piping curl into grep -m1 makes grep close the
    # pipe early and curl fail with "(23) Failure writing output".
    release_json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
    version="$(grep -o '"tag_name": *"[^"]*"' <<<"$release_json" | cut -d'"' -f4 | sed 's/^v//')"
    [ -n "$version" ] || { warn "Could not determine the latest runner version from the GitHub API."; exit 1; }
    tarball="actions-runner-linux-x64-${version}.tar.gz"
    as_runner curl -fsSL -o "$tarball" "https://github.com/actions/runner/releases/download/v${version}/${tarball}"
    as_runner tar -xzf "$tarball"
fi

if runner_has .runner; then
    log "Runner already registered as $(as_runner grep -o '"agentName": *"[^"]*"' .runner | cut -d'"' -f4); skipping registration"
elif [ -z "$HOST_READY" ]; then
    warn "Host configuration is not complete yet; skipping runner registration until the next run."
else
    token="${RUNNER_TOKEN:-}"
    if [ -z "$token" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        token="$(gh api -X POST "repos/$RUNNER_REPO/actions/runners/registration-token" --jq .token)"
    fi
    if [ -n "$token" ]; then
        log "Registering runner $RUNNER_NAME with $RUNNER_REPO as $RUNNER_USER"
        # The token goes in the environment, not argv: sudo logs each command
        # line to the journal. config.sh reads ACTIONS_RUNNER_INPUT_<option>.
        ACTIONS_RUNNER_INPUT_TOKEN="$token" \
            sudo --preserve-env=ACTIONS_RUNNER_INPUT_TOKEN -u "$RUNNER_USER" -H \
            env -C "$RUNNER_DIR" ./config.sh --unattended \
            --url "https://github.com/$RUNNER_REPO" \
            --name "$RUNNER_NAME" \
            ${RUNNER_LABELS:+--labels "$RUNNER_LABELS"}
    else
        warn "No registration token. Get one from https://github.com/$RUNNER_REPO/settings/actions/runners/new, then re-run this script with it:"
        echo "  RUNNER_TOKEN=<TOKEN> $0"
    fi
fi

# Ensure the service exists and is running whenever the runner is registered,
# including when registration was done by hand or a previous run stopped early.
if runner_has .runner; then
    # config.sh's own naming, so a unit svc.sh installed earlier is the same unit.
    service_name="actions.runner.${RUNNER_REPO//\//-}.${RUNNER_NAME}.service"
    unit="/etc/systemd/system/$service_name"

    # The name comes from this run's RUNNER_NAME and RUNNER_REPO, which need not
    # match the ones the runner was registered with: register with an override,
    # re-run without it, and a second unit would start a second listener on the
    # same registration. Refuse instead. The units are root's, so they are the
    # record to trust; .runner catches a runner registered without a unit yet.
    # Neither is used to build a path.
    for other in /etc/systemd/system/actions.runner.*.service; do
        [ -f "$other" ] && [ "$other" != "$unit" ] || continue
        if grep -qxF "WorkingDirectory=$RUNNER_DIR" "$other"; then
            warn "$(basename "$other") already runs $RUNNER_DIR, but this run would install $service_name. Re-run with the RUNNER_NAME and RUNNER_REPO it was registered with."
            exit 1
        fi
    done
    registered_name="$(as_runner grep -o '"agentName": *"[^"]*"' .runner | cut -d'"' -f4)"
    registered_url="$(as_runner grep -o '"gitHubUrl": *"[^"]*"' .runner | cut -d'"' -f4)"
    if [ "$registered_name" != "$RUNNER_NAME" ] || [ "${registered_url%/}" != "https://github.com/$RUNNER_REPO" ]; then
        warn "The runner in $RUNNER_DIR is registered as $registered_name for $registered_url, not $RUNNER_NAME for https://github.com/$RUNNER_REPO. Re-run with RUNNER_NAME=$registered_name and the matching RUNNER_REPO."
        exit 1
    fi
    restart=

    # Keep job temp files out of the 5.8G /tmp tmpfs, whose per-user quota
    # took builder-linux1 down with "Disk quota exceeded" (2026-09-06).
    sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_HOME/.runner-tmp"
    if ! as_runner grep -q '^TMPDIR=' .env 2>/dev/null; then
        echo "TMPDIR=$RUNNER_HOME/.runner-tmp" | as_runner tee -a .env >/dev/null
        restart=1
    fi

    log "Ensuring the runner service is installed and running"
    # What svc.sh install does, minus running svc.sh as root: runsvc.sh is
    # copied as the runner user, and the unit comes from svc.sh's own template.
    as_runner cp bin/runsvc.sh runsvc.sh
    as_runner chmod 755 runsvc.sh
    unit_content="[Unit]
Description=GitHub Actions Runner (${RUNNER_REPO//\//-}.${RUNNER_NAME})
After=network-online.target

[Service]
ExecStart=$RUNNER_DIR/runsvc.sh
User=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=5min

[Install]
WantedBy=multi-user.target"
    # svc.sh status and uninstall look the unit up in .service.
    echo "$service_name" | as_runner tee .service >/dev/null

    # svc.sh writes the unit with Restart=no, so a listener that dies (an OOM
    # kill mid-build, say) stays dead until someone notices -- no good on a box
    # running headless.
    dropin="$unit.d/restart.conf"
    dropin_content='[Service]
Restart=always
RestartSec=5s'
    if [ "$(cat "$unit" 2>/dev/null)" != "$unit_content" ] \
        || [ "$(cat "$dropin" 2>/dev/null)" != "$dropin_content" ]; then
        log "Writing the runner service unit"
        printf '%s\n' "$unit_content" | sudo tee "$unit" >/dev/null
        sudo mkdir -p "$unit.d"
        printf '%s\n' "$dropin_content" | sudo tee "$dropin" >/dev/null
        sudo systemctl daemon-reload
        restart=1
    fi

    sudo systemctl enable --quiet "$service_name"
    if [ -n "$restart" ] || ! systemctl is-active --quiet "$service_name"; then
        sudo systemctl restart "$service_name"
    fi
fi

log "Done"
