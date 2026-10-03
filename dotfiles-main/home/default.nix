{ config, home-manager, pkgs, lib, antigravity-nix, ... }:

let
  userConfig = import ../user-config.nix;
in
{
  imports = [
    # Note: sops-nix is imported at the system level in flake.nix
    (import ./programs.nix { inherit config pkgs lib; })
    (import ./platforms.nix { inherit config pkgs lib antigravity-nix; })
    ./hosts/default.nix
    ./mcp-servers.nix
  ];

  # sops-nix configuration
  sops = {
    defaultSopsFile = ./secrets/secrets.enc.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    secrets = {
      github_name = {
        key = "github/name";
      };
      github_email = {
        key = "github/email";
      };
      github_token = {
        key = "github/token";
      };
      github_mcp_token = {
        key = "github/mcp_token";
      };
      mistral_api_key = {
        key = "mistral/api_key";
      };
    };
  };

  home.username = userConfig.username;
  home.homeDirectory = userConfig.homeDirectory;
  home.stateVersion = userConfig.stateVersion;

  # allowUnfree is set by whoever constructs pkgs: nixos/configuration.nix,
  # darwin/configuration.nix, or the standalone homeConfigurations in
  # flake.nix. Setting nixpkgs.config here is ignored (and warned about)
  # under home-manager.useGlobalPkgs.

  programs.home-manager.enable = true;

  # Automatic Nix store garbage collection for standalone Linux machines
  # (e.g. the Arch builder), which the system-level nix.gc in
  # nixos/configuration.nix and darwin/configuration.nix doesn't reach.
  # On multi-user installs the collection itself runs through nix-daemon,
  # so this reclaims the whole store, not just this user's profiles.
  # Daily at a 14-day retention, matching the system-level regime.
  nix.gc = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # Platform-specific configurations are handled in platforms.nix

  # Ensure sops-nix service waits for home directory to be ready (Linux only)
  systemd.user.services = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    sops-nix = {
      Unit = {
        After = [ "graphical-session.target" ];
        # Ensure the service starts after the file system is ready
        RequiresMountsFor = [ config.home.homeDirectory ];
      };
    };
  };

}
