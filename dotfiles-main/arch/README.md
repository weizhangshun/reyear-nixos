# Arch Linux host layer

Home Manager covers the user environment, but the OS underneath the
`builder-linux*` GitHub Actions runners is plain Arch Linux. This directory
captures the parts of that layer that are not derivable from the flake, so a
second (or third) identical box can be stood up from a fresh Arch install.

| File | Purpose |
|---|---|
| `pkglist-native.txt` | Explicitly installed packages from the official repos (`pacman -Qqen`) |
| `pkglist-aur.txt` | Explicitly installed AUR packages (`pacman -Qqem`, debug packages dropped) |
| `zram-generator.conf` | Copied to `/etc/systemd/zram-generator.conf` for zram swap |

## Standing up a new runner box

1. Install Arch by following [INSTALL.md](INSTALL.md). It walks through the
   partitioning (EFI plus LVM with `lv_root` and `lv_home`), the base
   packages, the `kourtni` user in the `wheel` group, and networking.
2. Log in as that user and run (`git` is not part of a minimal Arch install,
   so install it first):

   ```bash
   sudo pacman -Syu --needed git
   git clone https://github.com/kourtni/dotfiles.git ~/dotfiles
   ~/dotfiles/scripts/bootstrap-arch-runner.sh
   ```

3. Copy `user-config.nix` and `~/.config/sops/age/keys.txt` over from the
   existing box (neither is in git), then re-run the script. It picks up where
   it left off: every step is idempotent.
4. Register the runner. The script does this automatically when `gh` is
   authenticated or `RUNNER_TOKEN` is exported; otherwise it prints the exact
   `config.sh` command to run.

## The runner account

The runner, and every job it picks up, runs as a dedicated `github-runner`
account (override with `RUNNER_USER`), not as you. Anyone who can land a
workflow change in the runner's repository can make a job run anything that
account can, so the script creates it with:

- no `wheel` membership, so no sudo. The script stops if it finds the account
  in `wheel`.
- a locked password and a `nologin` shell. Use `sudo -u github-runner` to act
  as it.
- its own `0700` home holding only the runner, its temp directory and its
  caches. Your home is `0700` too, so jobs cannot read your SSH keys, `gh`
  token or age keys.
- no Nix trust. The script never adds it to `trusted-users`; trust is
  effectively root on the Nix daemon, and jobs build without it.

Because that home is closed to you, commands in the runner directory need
`sudo`, e.g. `sudo -u github-runner -H env -C /home/github-runner/actions-runner ./config.sh --version`.
Always run them *as* `github-runner`, never as root. Jobs can rewrite any file
in that home, including the runner's own `svc.sh`, so `sudo ./svc.sh` there
would run whatever a job left behind as root. The script follows the same
rule: it writes the systemd unit itself and manages the service with
`systemctl`.

### Moving a runner off your account

Earlier versions of the bootstrap script registered the runner in
`~/actions-runner` as your own user. The script now refuses to continue while
that runner exists, since a second registration under the same name would
fail. To move it, on the box, as your user (outside any Nix dev shell, whose
`libstdc++` breaks the runner's bundled .NET):

```bash
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove --token "$(gh api -X POST \
  repos/<owner>/<repo>/actions/runners/remove-token --jq .token)"
cd ~ && ~/dotfiles/scripts/bootstrap-arch-runner.sh
```

`config.sh remove` deletes the registration on GitHub and the local
`.runner`, so the script registers the new runner under the same name. The
service keeps its name too, so the restart drop-in carries over. Check that it
now runs as the new account:

```bash
systemctl show -p User,ActiveState 'actions.runner.*'
```

The first jobs start with cold Bazel and other caches under the new home.
Once one has finished, reclaim the old runner's space. Its Bazel output base
sits in your `~/.cache/bazel`, marked by a `DO_NOT_BUILD_HERE` file that names
the runner's workspace, with read-only files:

```bash
for f in $(grep -l actions-runner ~/.cache/bazel/_bazel_$USER/*/DO_NOT_BUILD_HERE); do
  chmod -R u+w "$(dirname "$f")" && rm -rf "$(dirname "$f")"
done
rm -rf ~/actions-runner ~/.runner-tmp
```

## Networking

The wired connection is plain DHCP with no static address, DNS, or firewall
rules, so a new box needs nothing beyond NetworkManager being enabled (the
script does that). Two things are not carried over:

- **Wi-Fi profiles.** Saved networks and their passwords live in root-only
  files that are deliberately kept out of git. To copy them from the existing
  box (run on the *new* box, as your user):

  ```bash
  sudo scp -p 'root@builder-linux1:/etc/NetworkManager/system-connections/*.nmconnection' \
      /etc/NetworkManager/system-connections/
  sudo chmod 600 /etc/NetworkManager/system-connections/*.nmconnection
  sudo nmcli connection reload
  ```

  If root SSH is not enabled on the existing box, `sudo cat` the files there
  and paste them into place instead, or simply join the Wi-Fi once from the
  new box with `nmcli device wifi connect <SSID> --ask`.

- **Router-side settings.** If the existing box has a DHCP reservation or a
  DNS name on the `ck-runners.lan` network, add a matching entry for the new
  box on the router. Nothing on the host controls this.

## Refreshing the package lists

Run this on the reference box after installing or removing packages:

```bash
pacman -Qqen > ~/dotfiles/arch/pkglist-native.txt
pacman -Qqem | grep -v -- '-debug$' > ~/dotfiles/arch/pkglist-aur.txt
```
