# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{ config, lib, pkgs, ... }:

let
  userConfig = import ../user-config.nix;
in

{
  imports = [
    /etc/nixos/hardware-configuration.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = userConfig.username;
  wsl.interop.register = true;  # Enable Windows executable interop

  # Override problematic auto-generated mounts with nofail option
  fileSystems."/usr/lib/wsl/drivers" = lib.mkForce {
    device = "none";
    fsType = "none";
    options = [ "nofail" ];
  };

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Home Manager uses the system pkgs (useGlobalPkgs), so unfree must be
  # allowed here rather than in home/default.nix.
  nixpkgs.config.allowUnfree = true;

  # Automatic store maintenance. Without this the store only grows: every
  # rebuild leaves the previous generation's closure behind, and nothing
  # ever deletes it. Runs on the module defaults: GC daily at 03:15, optimise
  # daily at 03:45.
  nix.gc = {
    automatic = true;
    # Also drop system/home-manager generations older than this so they stop
    # pinning old closures. Anything newer stays available for rollback.
    options = "--delete-older-than 14d";
    # WSL is rarely running at a fixed wall-clock time. Persistent timers
    # record the last run and fire at the next boot if a run was missed, so
    # the schedule actually happens instead of being skipped forever.
    persistent = true;
  };
  # Hard-link identical files across store paths. Preferred over
  # nix.settings.auto-optimise-store, which optimises during every build.
  nix.optimise.automatic = true;

  # Keep a floor of free memory so the kernel can still satisfy high-order
  # allocations under heavy I/O. Each new hv_sock channel (every new WSL
  # terminal) needs a contiguous 512 KB ring buffer; once the VM has
  # fragmented under a big build the allocation fails ("page allocation
  # failure: order:7 ... hvs_probe" in `journalctl -k`) and new terminals
  # error with Wsl/Service/0x8007274c until `wsl --shutdown`. The default
  # floor is a few tens of MB; 256 MB keeps enough contiguous memory in
  # reserve. Complements autoMemoryReclaim in nixos/wslconfig, which slows
  # the fragmentation but can be outrun by a concurrent I/O burst.
  boot.kernel.sysctl."vm.min_free_kbytes" = 262144;

  networking.hostName = "wsl"; # <- must match the flake output key

  users.users.${userConfig.username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    # Pin the UID to 1000, the NixOS-WSL default, so the account stays aligned
    # with the platform default and WSLg's runtime-dir expectations.
    uid = 1000;
    # Enable lingering so user systemd services run without an active login session
    linger = true;
  };

  # WSLg mounts a root-owned tmpfs over /run/user/<uid> during early WSL init.
  # That shadows the per-user runtime directory systemd-logind expects to own
  # (0700, owned by the user), so pam_systemd refuses it, $XDG_RUNTIME_DIR is
  # never set, and `user@<uid>.service` (the systemd --user manager) fails --
  # which means lingering can't actually run any user services. Unmount WSLg's
  # shadow mount right before user-runtime-dir creates the real directory.
  # Refs: microsoft/WSL#9689, NixOS-WSL#346.
  systemd.services."user-runtime-dir@".serviceConfig.ExecStartPre = [
    "-${pkgs.util-linux}/bin/umount /run/user/%i"
  ];

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # Add some some basic system packages
  environment.systemPackages = with pkgs; [
    age
    direnv
    gh
    git
    neovim
    nix-direnv
    sops
    wget
  ];

  programs.fish.enable = true;

  # command-not-found works with flakes via the programs-sqlite database
  programs.command-not-found.enable = true;

  # Enable nix-ld to run unpatched dynamic binaries on NixOS
  programs.nix-ld.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
