{ config, pkgs, lib, ... }:

let
  # Platform detection
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  
  # Import shared npm utilities
  npmUtils = import ./npm-utils.nix { inherit pkgs; };
in
lib.mkMerge [
  # Linux-specific configuration
  (lib.mkIf isLinux {
    # Linux: Install npm packages AND create wrapper scripts
    home.activation.shadcnUiMcpServer = config.lib.dag.entryAfter ["writeBoundary"] (
      npmUtils.mkNpmPackageActivation {
        packageName = "@jpisnice/shadcn-ui-mcp-server";
        binaryName = "shadcn-mcp";
        displayName = "shadcn-ui-mcp-server";
      }
    );

    home.activation.context7McpServer = config.lib.dag.entryAfter ["writeBoundary"] (
      npmUtils.mkNpmPackageActivation {
        packageName = "@upstash/context7-mcp";
        binaryName = "context7-mcp";
        displayName = "context7-mcp-server";
      }
    );

    # Linux: Wrapper scripts for systemd services
    home.packages = let
      shadcnUiMcpServerWrapper = pkgs.writeShellScriptBin "shadcn-ui-mcp-server" ''
        # Load GitHub token from sops if available
        if [ -f "${config.sops.secrets.github_mcp_token.path}" ]; then
          export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${config.sops.secrets.github_mcp_token.path})"
          echo "✅ Using GitHub MCP token from sops"
        else
          echo "ℹ️  No GitHub MCP token found, running with default rate limits"
        fi
        
        # Run the MCP server
        exec ${pkgs.nodejs_24}/bin/npx @jpisnice/shadcn-ui-mcp-server "$@"
      '';
      
      context7McpServerWrapper = pkgs.writeShellScriptBin "context7-mcp-server" ''
        # Run the context7 MCP server
        exec ${pkgs.nodejs_24}/bin/npx -y @upstash/context7-mcp "$@"
      '';
      
      # Define the mcp-testing-sensei for Linux
      mcpTestingSenseiBinary = pkgs.fetchurl {
        url = "https://github.com/kourtni/mcp-testing-sensei/releases/download/v0.2.1/mcp-testing-sensei-linux";
        sha256 = "sha256-aguZR8/wFlM3aChWIIRXzpu/QvYgDrRkaq3rrESscNs=";
        executable = true;
      };
      
      mcpTestingSenseiFHS = pkgs.buildFHSEnv {
        name = "mcp-testing-sensei-fhs";
        targetPkgs = pkgs: with pkgs; [
          glibc
          gcc-unwrapped.lib
          zlib
          expat
          libffi
          openssl
          ncurses6
          readline
          bzip2
          sqlite
          xz
        ];
        runScript = "${mcpTestingSenseiBinary}";
      };
      
      mcpTestingSensei = pkgs.writeShellScriptBin "mcp-testing-sensei" ''
        exec ${mcpTestingSenseiFHS}/bin/mcp-testing-sensei-fhs "$@"
      '';
    in [
      shadcnUiMcpServerWrapper
      context7McpServerWrapper
      mcpTestingSensei
    ];

    # Linux: systemd services
    systemd.user.services = {
      shadcn-ui-mcp-server = {
        Unit = {
          Description = "shadcn/ui MCP Server";
          Documentation = "https://github.com/Jpisnice/shadcn-ui-mcp-server";
        };
        Service = {
          Type = "simple";
          ExecStart = "${config.home.profileDirectory}/bin/shadcn-ui-mcp-server";
          Environment = [
            "NPM_CONFIG_PREFIX=%h/.npm-global"
            "PATH=${pkgs.nodejs_24}/bin:%h/.npm-global/bin:/usr/bin:/bin"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            "%h/.npm-global"
            "%h/.npm"
          ];
          NoNewPrivileges = true;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      context7-mcp-server = {
        Unit = {
          Description = "Context7 MCP Server";
          Documentation = "https://github.com/upstash/context7";
        };
        Service = {
          Type = "simple";
          ExecStart = "${config.home.profileDirectory}/bin/context7-mcp-server";
          Environment = [
            "NPM_CONFIG_PREFIX=%h/.npm-global"
            "PATH=${pkgs.nodejs_24}/bin:%h/.npm-global/bin:/usr/bin:/bin"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            "%h/.npm-global"
            "%h/.npm"
          ];
          NoNewPrivileges = true;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      mcp-testing-sensei = {
        Unit = {
          Description = "MCP Testing Sensei Server";
          Documentation = "https://github.com/kourtni/mcp-testing-sensei";
        };
        Service = {
          Type = "simple";
          ExecStart = "${config.home.profileDirectory}/bin/mcp-testing-sensei";
          Environment = [
            "PATH=/usr/bin:/bin"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          NoNewPrivileges = true;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };

    # Linux: Fish shell functions for systemd management
    programs.fish.shellInit = ''
      # MCP server management functions for Linux
      function mcp-shadcn-status
        systemctl --user status shadcn-ui-mcp-server
      end
      
      function mcp-shadcn-start
        systemctl --user start shadcn-ui-mcp-server
      end
      
      function mcp-shadcn-stop
        systemctl --user stop shadcn-ui-mcp-server
      end
      
      function mcp-context7-status
        systemctl --user status context7-mcp-server
      end
      
      function mcp-context7-start
        systemctl --user start context7-mcp-server
      end
      
      function mcp-context7-stop
        systemctl --user stop context7-mcp-server
      end
      
      function mcp-testing-sensei-status
        systemctl --user status mcp-testing-sensei
      end
      
      function mcp-testing-sensei-start
        systemctl --user start mcp-testing-sensei
      end
      
      function mcp-testing-sensei-stop
        systemctl --user stop mcp-testing-sensei
      end
    '';
  })

  # Darwin-specific configuration
  (lib.mkIf isDarwin {
    # Darwin: Only install npm packages (no wrapper scripts)
    home.activation.shadcnUiMcpServerDarwin = config.lib.dag.entryAfter ["writeBoundary"] (
      npmUtils.mkNpmPackageActivation {
        packageName = "@jpisnice/shadcn-ui-mcp-server";
        binaryName = "shadcn-mcp";
        displayName = "shadcn-ui-mcp-server";
      }
    );

    home.activation.context7McpServerDarwin = config.lib.dag.entryAfter ["writeBoundary"] (
      npmUtils.mkNpmPackageActivation {
        packageName = "@upstash/context7-mcp";
        binaryName = "context7-mcp";
        displayName = "context7-mcp-server";
      }
    );

    # Darwin: Only install the mcp-testing-sensei binary
    home.packages = let
      mcpTestingSenseiBinary = pkgs.fetchurl {
        url = "https://github.com/kourtni/mcp-testing-sensei/releases/download/v0.2.1/mcp-testing-sensei-macos";
        sha256 = "sha256-mBuMO4IcZsX6awRq7RYQpBr7bxNxItPRDdSXBd+W2EM=";
        executable = true;
      };
      
      mcpTestingSensei = pkgs.runCommand "mcp-testing-sensei" {} ''
        mkdir -p $out/bin
        cp ${mcpTestingSenseiBinary} $out/bin/mcp-testing-sensei
        chmod +x $out/bin/mcp-testing-sensei
      '';
    in [ mcpTestingSensei ];

    # Darwin: Fish shell functions for MCP info
    programs.fish.shellInit = ''
      # MCP server info for macOS
      # On macOS, MCP servers are invoked on-demand by Claude Code
      
      function mcp-status
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📝 MCP Servers on macOS"
        echo ""
        echo "MCP servers are invoked on-demand by Claude Code."
        echo "No manual start/stop is needed."
        echo ""
        echo "Installed servers:"
        if test -f ~/.npm-global/bin/shadcn-mcp
          echo "  ✅ shadcn-ui-mcp-server"
        else
          echo "  ❌ shadcn-ui-mcp-server (not installed)"
        end
        if test -f ~/.npm-global/bin/context7-mcp
          echo "  ✅ context7-mcp-server"
        else
          echo "  ❌ context7-mcp-server (not installed)"
        end
        if command -v mcp-testing-sensei >/dev/null 2>&1
          echo "  ✅ mcp-testing-sensei"
        else
          echo "  ❌ mcp-testing-sensei (not installed)"
        end
        echo ""
        echo "Configure in your project with:"
        echo "  ~/dotfiles/scripts/setup-mcp.sh"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      end
      
      # Provide helpful aliases that inform the user
      function mcp-shadcn-start
        echo "ℹ️  On macOS, MCP servers start automatically when Claude Code needs them."
        echo "Make sure you've configured your project with: ~/dotfiles/scripts/setup-mcp.sh"
      end
      
      function mcp-context7-start
        echo "ℹ️  On macOS, MCP servers start automatically when Claude Code needs them."
        echo "Make sure you've configured your project with: ~/dotfiles/scripts/setup-mcp.sh"
      end
      
      function mcp-testing-sensei-start
        echo "ℹ️  On macOS, MCP servers start automatically when Claude Code needs them."
        echo "Make sure you've configured your project with: ~/dotfiles/scripts/setup-mcp.sh"
      end
    '';
  })
]