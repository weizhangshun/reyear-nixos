{ config, pkgs, lib, ... }:

let
  # Create a file with hostname detection
  hostnameFile = pkgs.runCommand "hostname" {} ''
    ${pkgs.hostname}/bin/hostname | cut -d. -f1 > $out
  '';
  hostname = builtins.readFile hostnameFile;
  isCxGawd = lib.strings.hasPrefix "CxGawd" hostname;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  # Hostname detection above runs inside the build sandbox on Linux, where the
  # hostname is always "localhost", so the Arch desktop boxes are matched by
  # platform instead: native Linux that is neither NixOS nor WSL.
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isNixOS = builtins.pathExists /etc/nixos;
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  isArchDesktop = isLinux && !isNixOS && !isWSL;
in
{
  # Host-specific packages
  # Note: bazelisk is installed system-wide via nix-darwin on macOS
  home.packages = lib.optionals (isCxGawd && !isDarwin) [
    pkgs.bazelisk
  ];

  # Hyprland desktop for the Arch runner boxes (builder-linux*). The packages
  # (hyprland, waybar, wofi, awww, grim, slurp, wl-clipboard, kitty) come from
  # arch/pkglist-native.txt; only the config lives here. Harmless on a Linux
  # box without Hyprland: nothing reads these files.
  xdg.configFile = lib.mkIf isArchDesktop {
    "hypr" = { source = ./builder-linux/hypr; recursive = true; };
    "waybar" = { source = ./builder-linux/waybar; recursive = true; };
    "wofi" = { source = ./builder-linux/wofi; recursive = true; };
  };
}
