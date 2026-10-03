{ config, pkgs, lib, antigravity-nix, ... }:

let
  # Base platform detection
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  
  # WSL detection (independent of OS distribution)
  wslInteropExists = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  kernelVersionContainsMicrosoft = 
    let
      versionFile = /proc/version;
    in
      if builtins.pathExists versionFile
      then builtins.match ".*microsoft.*" (builtins.readFile versionFile) != null
      else false;
  wslEnvExists = builtins.pathExists /run/WSL;
  
  isWSL = wslInteropExists || kernelVersionContainsMicrosoft || wslEnvExists;
  
  # NixOS detection (independent of WSL)
  isNixOS = builtins.pathExists /etc/nixos;
  
  # Granular system type detection
  systemType = if isDarwin then "darwin"
               else if isLinux && isWSL && isNixOS then "nixos-wsl"
               else if isLinux && isWSL then "linux-wsl"  
               else if isLinux && isNixOS then "nixos"
               else if isLinux then "linux"
               else "unknown";
               
in

{
  # Nix version check for standalone Linux (where Nix isn't managed declaratively)
  home.activation.nixVersionCheck = lib.mkIf (isLinux && !isNixOS) (config.lib.dag.entryAfter ["writeBoundary"] ''
    # Get current Nix version (full semver including patch)
    CURRENT_NIX=$(nix --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
    # Get latest Nix version available in nixpkgs
    LATEST_NIX=$(nix eval --raw nixpkgs#nixVersions.latest.version 2>/dev/null || echo "unknown")

    if [ -n "$CURRENT_NIX" ] && [ "$LATEST_NIX" != "unknown" ] && [ "$CURRENT_NIX" != "$LATEST_NIX" ]; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "ℹ️  Nix upgrade available: $CURRENT_NIX → $LATEST_NIX"
      echo ""
      echo "Run 'nix-upgrade' to update Nix on this system."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
  '');

  # Font installation note for macOS
  home.activation.fontNote = lib.mkIf isDarwin (config.lib.dag.entryAfter ["writeBoundary"] ''
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Note: Nerd Fonts need to be installed separately on macOS"
    echo ""
    echo "Install via Homebrew:"
    echo "  brew tap homebrew/cask-fonts"
    echo "  brew install --cask font-0xproto-nerd-font"
    echo "  brew install --cask font-droid-sans-mono-nerd-font"
    echo "  brew install --cask font-fira-code-nerd-font"
    echo "  brew install --cask font-jetbrains-mono-nerd-font"
    echo "  brew install --cask font-hack-nerd-font"
    echo ""
    echo "Or download manually from: https://www.nerdfonts.com/font-downloads"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '');

  # Platform-specific package sets
  home.packages = with pkgs; (
    # Common packages for all platforms
    [
      antigravity-nix.packages.${pkgs.stdenv.hostPlatform.system}.google-antigravity-cli
      age        # Required for sops-nix secret decryption
      bun        # Fast JavaScript runtime, bundler, and package manager
      curl
      fish
      htop
      jq
      nodejs_24  # LTS version - better binary cache coverage
      # npm is included with nodejs, no need for separate package
      ollama
      opencode   # AI coding agent for the terminal
      sops       # Required for sops-nix secret management
      vim
    ]
    # Linux-specific packages (fonts that require fontconfig)
    ++ lib.optionals isLinux [
      bubblewrap   # Sandbox runtime used by OpenAI Codex CLI for shell exec
      nerd-fonts._0xproto
      nerd-fonts.droid-sans-mono
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.hack
    ]
    # macOS-specific packages  
    ++ lib.optionals isDarwin [
      # Ollama might work on Darwin, but if it doesn't, remove this line
      # ollama
    ]
    # NixOS-specific packages (handles NixOS quirks)
    ++ lib.optionals isNixOS [
      # Add NixOS-specific packages here
      # e.g., packages that work better on NixOS
      patchelf
      gcc
    ]
    # Traditional Linux packages (Ubuntu, Fedora, etc. + Nix)
    ++ lib.optionals (isLinux && !isNixOS) [
      # Add traditional Linux-specific packages here
      # e.g., packages that work better on traditional distros
    ]
    # WSL-specific packages (regardless of underlying distro)
    ++ lib.optionals isWSL [
      # Add WSL-specific packages here
      # e.g., wslu for WSL utilities
    ]
  );

  # Platform-specific environment variables
  # Note: WSL and SYSTEM_TYPE are set dynamically in shell init for Linux systems
  home.sessionVariables = {
    # Expose detection flags for scripts and applications
    IS_NIXOS = if isNixOS then "true" else "false";
  } // lib.optionalAttrs isDarwin {
    # Darwin-specific environment variables
    HOMEBREW_PREFIX = "/opt/homebrew";
    SYSTEM_TYPE = "darwin";
    IS_WSL = "false";
  } // lib.optionalAttrs isNixOS {
    # NixOS-specific environment variables
    # These help scripts know they're on NixOS with its unique filesystem
    NIXOS_SYSTEM = "true";
  } // lib.optionalAttrs (isLinux && !isNixOS) {
    # Traditional Linux environment variables
    NIXOS_SYSTEM = "false";
  };

  # Platform-specific configurations
  home.file = lib.mkMerge [
    # Common configurations
    {
      ".npmrc".text = ''
        prefix=~/.npm-global
        update-notifier=false
      '';
    }
    
    # macOS-specific configurations
    (lib.mkIf isDarwin {
      # Add macOS-specific file configurations here
    })
    
    # NixOS-specific configurations (handles NixOS filesystem quirks)
    (lib.mkIf (isNixOS && !isWSL) {
      # Add native NixOS-specific file configurations here
      # e.g., shell scripts with proper Nix store paths
    })
    
    # Traditional Linux-specific configurations 
    (lib.mkIf (isLinux && !isNixOS && !isWSL) {
      # Add native traditional Linux-specific file configurations here
      # e.g., shell scripts with traditional paths like /bin/bash
    })
    
    # WSL configurations (regardless of underlying distro)
    (lib.mkIf isWSL {
      # Add WSL-specific file configurations here
      # e.g., interop configurations, Windows path integrations
    })
    
    # NixOS on WSL specific configurations
    (lib.mkIf (isNixOS && isWSL) {
      # Add NixOS-WSL specific configurations here
      # Combination of NixOS quirks + WSL requirements
    })
    
    # Traditional Linux on WSL configurations
    (lib.mkIf (isLinux && !isNixOS && isWSL) {
      # Add traditional Linux-WSL specific configurations here
      # e.g., Ubuntu/Fedora on WSL with traditional paths
    })
  ];
}
