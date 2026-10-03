{
  description = "NixOS WSL + Home Manager Config";

  inputs = {

    # Input for the system foundation - using unstable for compatibility
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keep unstable alias for consistency
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Use master branch to match nixpkgs
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    flake-programs-sqlite.url = "github:wamserma/flake-programs-sqlite";
    flake-programs-sqlite.inputs.nixpkgs.follows = "nixpkgs";

    antigravity-nix.url = "github:jacopone/antigravity-nix";
    antigravity-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Intel Mac (x86_64-darwin) stack. Nixpkgs 26.11 dropped x86_64-darwin
    # entirely; the 26.05 branch still carries it and receives security
    # fixes until the end of 2026. Anything that instantiates nixpkgs for
    # that system has to go through this input, so the module frameworks and
    # antigravity get pinned 26.05 twins that follow it. Every other system
    # keeps tracking unstable via the inputs above.
    nixpkgs-intel.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    home-manager-intel.url = "github:nix-community/home-manager/release-26.05";
    home-manager-intel.inputs.nixpkgs.follows = "nixpkgs-intel";

    nix-darwin-intel.url = "github:LnL7/nix-darwin/nix-darwin-26.05";
    nix-darwin-intel.inputs.nixpkgs.follows = "nixpkgs-intel";

    antigravity-nix-intel.url = "github:jacopone/antigravity-nix";
    antigravity-nix-intel.inputs.nixpkgs.follows = "nixpkgs-intel";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-wsl, nix-darwin, sops-nix, flake-programs-sqlite, antigravity-nix, ... }:
    let
      userConfig = import ./user-config.nix;
      username = userConfig.username;

      # Supported systems
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # Helper function to generate outputs for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Default system for NixOS configurations
      defaultSystem = userConfig.system;

      # The set of inputs a given system builds from. Only the Intel Mac
      # diverges from unstable (see the *-intel inputs above).
      stackFor = system:
        if system == "x86_64-darwin" then {
          nixpkgs = inputs.nixpkgs-intel;
          home-manager = inputs.home-manager-intel;
          nix-darwin = inputs.nix-darwin-intel;
          antigravity-nix = inputs.antigravity-nix-intel;
        } else {
          inherit nixpkgs home-manager nix-darwin antigravity-nix;
        };

      # Home Manager settings shared by the NixOS and nix-darwin modules.
      homeManagerSettings = stack: {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit (stack) antigravity-nix; };
        home-manager.users.${username} = import ./home/default.nix;
        home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];
      };
    in {
      # Used by `sudo nixos-rebuild switch --flake`
      nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
        system = defaultSystem;
        modules = [

          ({ pkgs, ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                # This adds an 'unstable' attribute to your packages set
                # so you can access unstable packages via 'pkgs.unstable'
                unstable = import nixpkgs-unstable {
                  system = prev.system;
                  # You may need to pass config here if you use unfree packages
                  config.allowUnfree = true;
                };
              })
            ];
          })

          nixos-wsl.nixosModules.default
          flake-programs-sqlite.nixosModules.programs-sqlite
          ./nixos/configuration.nix
          home-manager.nixosModules.home-manager
          (homeManagerSettings (stackFor defaultSystem))
        ];
      };

      # Make home-manager accessible via nix run and nix shell for all systems
      packages = forAllSystems (system:
        let hm = (stackFor system).home-manager;
        in {
          home-manager = hm.packages.${system}.home-manager;
          default = hm.packages.${system}.home-manager;
        });

      # Standalone home-manager configurations
      homeConfigurations =
        let
          mkHomeConfig = system:
            let stack = stackFor system;
            in stack.home-manager.lib.homeManagerConfiguration {
              pkgs = import stack.nixpkgs { inherit system; config.allowUnfree = true; };
              extraSpecialArgs = { inherit (stack) antigravity-nix; };
              modules = [ ./home/default.nix sops-nix.homeManagerModules.sops ];
            };
        in {
          "${username}@x86_64-linux" = mkHomeConfig "x86_64-linux";
          "${username}@aarch64-linux" = mkHomeConfig "aarch64-linux";
          "${username}@x86_64-darwin" = mkHomeConfig "x86_64-darwin";
          "${username}@aarch64-darwin" = mkHomeConfig "aarch64-darwin";
        };

      # nix-darwin configurations for macOS
      darwinConfigurations =
        let
          mkDarwinConfig = system:
            let stack = stackFor system;
            in stack.nix-darwin.lib.darwinSystem {
              inherit system;
              modules = [
                ./darwin/configuration.nix
                stack.home-manager.darwinModules.home-manager
                (homeManagerSettings stack)
              ];
            };
        in {
          "x86_64-darwin" = mkDarwinConfig "x86_64-darwin";
          "aarch64-darwin" = mkDarwinConfig "aarch64-darwin";
        };
    };
}
