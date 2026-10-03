{ config, pkgs, lib, ... }:

let
  userConfig = import ../user-config.nix;
  npmUtils = import ./npm-utils.nix { inherit pkgs; };
  
  # Platform detection
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  
  # Platform-specific VS Code paths
  vscodeWSLPath = "/mnt/c/Users/${userConfig.windowsUsername}/AppData/Local/Programs/Microsoft VS Code/bin";
  vscodeDarwinPath = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin";
  
  # Determine VS Code path based on platform
  vscodePath = if isWSL then vscodeWSLPath
               else if isDarwin then vscodeDarwinPath
               else null; # No default path for native Linux
in

{
  
  programs.git = {
    enable = true;
    # Git config managed by home-manager
    settings = {
      credential.helper = "store";
      # Include local config for secrets (written by activation script)
      # This comes after user settings, so secrets override fallbacks
      include.path = "~/.config/git/config.local";
      # Fallback user config (overridden by sops secrets in config.local)
      user.name = userConfig.git.name;
      user.email = userConfig.git.email;
    };
  };

  # Set up git credentials and config via activation script that can read sops secrets
  home.activation.setupGitSecrets = config.lib.dag.entryAfter ["writeBoundary"] ''
    # Write git user config to local file from sops secrets (overrides default config)
    if [ -f "${config.sops.secrets.github_name.path}" ] && [ -f "${config.sops.secrets.github_email.path}" ]; then
      mkdir -p ~/.config/git
      cat > ~/.config/git/config.local << EOF
    [user]
    	name = $(cat ${config.sops.secrets.github_name.path})
    	email = $(cat ${config.sops.secrets.github_email.path})
    EOF
      echo "✅ Git user config updated from sops secrets"
    else
      # Remove local config if no secrets, fall back to home-manager managed config
      rm -f ~/.config/git/config.local
      echo "ℹ️  Using git config from user-config.nix (no sops secrets found)"
    fi

    # Set up git credentials from sops secrets
    if [ -f "${config.sops.secrets.github_token.path}" ]; then
      echo "https://$(cat ${config.sops.secrets.github_token.path}):x-oauth-basic@github.com" > ~/.git-credentials
      echo "✅ Git credentials updated from sops secrets"
    else
      echo "ℹ️  No GitHub token found in sops secrets"
    fi
  '';

  programs.fish = {
    enable = true;

    shellInit = ''
      # Ensure npm global bin is in PATH (explicit for standalone home-manager compatibility)
      fish_add_path --path $HOME/.npm-global/bin

      set -gx EDITOR nvim
      fish_vi_key_bindings

      # Runtime platform detection for Linux systems
      if test (uname) = "Linux"
        # Detect WSL environment
        set -l is_wsl "false"
        if test -e /proc/sys/fs/binfmt_misc/WSLInterop; or test -e /run/WSL; or string match -q "*microsoft*" (uname -r)
          set is_wsl "true"
        end
        
        # Detect NixOS
        set -l is_nixos "false"
        if test -d /etc/nixos
          set is_nixos "true"
        end
        
        # Set granular system type
        if test "$is_wsl" = "true"; and test "$is_nixos" = "true"
          set -gx SYSTEM_TYPE "nixos-wsl"
        else if test "$is_wsl" = "true"
          set -gx SYSTEM_TYPE "linux-wsl"
        else if test "$is_nixos" = "true"
          set -gx SYSTEM_TYPE "nixos"
        else
          set -gx SYSTEM_TYPE "linux"
        end
        
        # Set detection variables
        set -gx IS_WSL "$is_wsl"
        set -gx IS_NIXOS "$is_nixos"
      end

      # GitHub PAT for Claude Code's user-level `github` MCP server, which
      # expands this variable into its Authorization header and resolves it
      # from its own process environment. The shadcn wrapper in
      # mcp-servers.nix exports the same secret, but only for itself: an
      # export inside a script reaches that process and its children, never
      # the surrounding shell. Setting it session-wide is what lets anything
      # launched from a shell, Claude Code included, see it.
      #
      # Interpolate the secret's path and read it at runtime. Baking the
      # value in (home.sessionVariables) would place the token in the
      # world-readable Nix store.
      if test -r ${config.sops.secrets.github_mcp_token.path}
        set -l github_mcp_token (cat ${config.sops.secrets.github_mcp_token.path})
        # Only export a non-empty value. An empty bearer token is worse than
        # an absent one: GitHub rejects it with 400 "Authorization header is
        # badly formatted" rather than a 401 that reads as an auth problem.
        if test -n "$github_mcp_token"
          set -gx GITHUB_PERSONAL_ACCESS_TOKEN $github_mcp_token
        end
      end

      # Mistral API key for the DeepSeek Harness (dsh). Its settings.yaml
      # names apiKeyEnv: MISTRAL_API_KEY; resolution prefers the process
      # environment over the key store, so once this is set the web UI's
      # Models page shows the credential as read-only env — that is expected.
      # Same read-at-runtime pattern as the GitHub token above: interpolating
      # only the sops *path* keeps the value out of the Nix store.
      if test -r ${config.sops.secrets.mistral_api_key.path}
        set -l mistral_api_key (cat ${config.sops.secrets.mistral_api_key.path})
        # Skip empty values: the placeholder in secrets.enc.yaml stays empty
        # until a real key is added, and an empty env var would shadow a key
        # stored through the web UI in ~/.dsh/.credentials.yaml.
        if test -n "$mistral_api_key"
          set -gx MISTRAL_API_KEY $mistral_api_key
        end
      end
    '' + lib.optionalString (vscodePath != null) ''

      # Add VS Code CLI to PATH (Platform-specific)
      set -l code_bin "${vscodePath}"
      if test -d "$code_bin"
        set -gx PATH $code_bin $PATH
      end
    '';

    functions = {
      # DeepSeek Harness launcher. Two reasons for the wrapper:
      #  - HMR needs Node's internal ESM loader; dsh's native fallback
      #    (node-addon-require-builtin) does not recognize the nixpkgs Node
      #    build, so the --expose-internals flag is required here.
      #  - A fish function wins over PATH lookup, so this shadows the plain
      #    ~/.npm-global/bin/dsh shim without touching npm's install.
      dsh = "node --expose-internals $HOME/.npm-global/bin/dsh $argv";
      ll = "ls -l";
      gs = "git status";
      # Portable Nix upgrade command
      nix-upgrade = ''
        set -l system_type "$SYSTEM_TYPE"

        # Fallback detection if SYSTEM_TYPE isn't set
        if test -z "$system_type"
          if test (uname) = "Darwin"
            set system_type "darwin"
          else if test -d /etc/nixos
            set system_type "nixos"
          else
            set system_type "linux"
          end
        end

        switch $system_type
          case "darwin"
            echo "Nix is managed by nix-darwin."
            echo "Run: darwin-rebuild switch --flake ~/dotfiles"
            echo ""
            echo "To update nixpkgs (which includes Nix), first run:"
            echo "  cd ~/dotfiles && nix flake update"
          case "nixos" "nixos-wsl"
            echo "Nix is managed by NixOS."
            echo "Run: sudo nixos-rebuild switch --flake ~/dotfiles"
            echo ""
            echo "To update nixpkgs (which includes Nix), first run:"
            echo "  cd ~/dotfiles && nix flake update"
          case "*"
            echo "Upgrading Nix on standalone Linux..."
            echo "Current version: "(nix --version)
            sudo nix upgrade-nix
            echo "New version: "(nix --version)
        end
      '';
    } // (if isDarwin then {
      # On macOS, use darwin-rebuild which manages both system and home-manager
      hm-rebuild = "darwin-rebuild switch --flake ~/dotfiles#${pkgs.stdenv.hostPlatform.system}";
    } else {
      # On Linux, use standalone home-manager
      hm-rebuild = "nix run ~/dotfiles#home-manager -- switch --flake ~/dotfiles#${userConfig.username}@${pkgs.stdenv.hostPlatform.system}";
    }) // lib.optionalAttrs isLinux {
      # Portable VS Code launcher that works on any WSL system (Linux only)
      code = ''
        # Check if we're in WSL first
        if not test -f /proc/sys/fs/binfmt_misc/WSLInterop
            # Not in WSL, try native code command
            command code $argv
            return
        end
        
        # Try to find VS Code in common Windows locations
        set -l vscode_paths \
            "/mnt/c/Program Files/Microsoft VS Code/bin/code" \
            "/mnt/c/Program Files (x86)/Microsoft VS Code/bin/code" \
            "/mnt/c/Users/$USER/AppData/Local/Programs/Microsoft VS Code/bin/code"
        
        # Also check with Windows username from Nix config
        set -l win_user "${userConfig.windowsUsername}"
        if test -n "$win_user"
            set vscode_paths $vscode_paths "/mnt/c/Users/$win_user/AppData/Local/Programs/Microsoft VS Code/bin/code"
        end
        
        # Try each path until we find one that exists
        for vscode_path in $vscode_paths
            if test -f "$vscode_path"
                # Check if it starts with a shebang (shell script)
                if head -n 1 "$vscode_path" 2>/dev/null | grep -q "^#!"
                    "$vscode_path" $argv
                    return
                end
            end
        end
        
        echo "VS Code not found. Please ensure it's installed on Windows." >&2
        return 1
      '';
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;  # Better caching for nix-shell/flakes
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = if isDarwin then {
      # Minimal Darwin config without Nerd Font symbols to avoid fontconfig dependencies
      format = "$all$character";
      character = {
        success_symbol = "[>](bold green)";
        error_symbol = "[>](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      git_branch = {
        symbol = "";
        format = "[$symbol$branch]($style) ";
      };
      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
      };
      # Add other essential modules without Nerd Font icons
    } else import ./starship-settings-from-toml.nix;
  };

  fonts.fontconfig.enable = pkgs.stdenv.hostPlatform.isLinux;

  # Add npm global bin and ~/.local/bin (codex, user scripts) to PATH
  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin"
  ];

  # Bash stays the login shell (no chsh needed for sddm/kitty on the Arch
  # runner boxes); Home Manager's .bashrc wires up the Nix profile and PATH,
  # then interactive shells hand off to fish. Previously this lived in a
  # hand-edited ~/.bashrc on builder-linux1 only.
  programs.bash = {
    enable = true;
    # Runs for non-interactive shells too (ssh remote commands, scripts), so
    # they can find nix and the Home Manager profile.
    bashrcExtra = ''
      if [[ -f ~/.nix-profile/etc/profile.d/hm-session-vars.sh ]]; then
        . ~/.nix-profile/etc/profile.d/hm-session-vars.sh
      fi
    '';
    initExtra = ''
      # Hand interactive shells to fish from the Nix profile, unless bash was
      # started deliberately from inside fish.
      if [[ -x ~/.nix-profile/bin/fish && "$(ps -o comm= -p $PPID 2>/dev/null)" != fish ]]; then
        exec ~/.nix-profile/bin/fish
      fi
    '';
  };

  # REPRODUCIBLE: Auto-install Claude Code via Home Manager activation
  home.activation.claudeCode = config.lib.dag.entryAfter ["writeBoundary"] (
    npmUtils.mkNpmPackageActivation {
      packageName = "@anthropic-ai/claude-code";
      binaryName = "claude";
      displayName = "Claude Code";
    }
  );

  # REPRODUCIBLE: Auto-install OpenAI Codex CLI via Home Manager activation
  home.activation.codexCLI = config.lib.dag.entryAfter ["writeBoundary"] (
    npmUtils.mkNpmPackageActivation {
      packageName = "@openai/codex";
      binaryName = "codex";
      displayName = "OpenAI Codex CLI";
    }
  );

  # REPRODUCIBLE: Auto-install DeepSeek Harness (dsh) via Home Manager activation.
  # Two install-time quirks, discovered empirically:
  #  - npm needs a larger heap than its ~2 GB default to resolve dsh's
  #    dependency graph (plain `npx @deepseek-ai/dsh` OOMs after minutes of GC);
  #  - several dependencies carry install scripts (native builds for node-pty
  #    and koffi, dsh's own spawn helper) that npm's allow-scripts policy
  #    blocks unless named explicitly.
  home.activation.deepseekHarness = config.lib.dag.entryAfter ["writeBoundary"] (
    npmUtils.mkNpmPackageActivation {
      packageName = "@deepseek-ai/dsh";
      binaryName = "dsh";
      displayName = "DeepSeek Harness";
      extraEnv = ''export NODE_OPTIONS="--max-old-space-size=8192"'';
      npmFlags = "--allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs";
    }
  );

  # Seed the harness's user config ($DSH_HOME, default ~/.dsh). dsh writes to
  # settings.yaml and the patch layers itself (the Models page stores keys,
  # the console edits entries), so nothing here may be a read-only symlink and
  # user-editable files are seeded only when absent.
  home.activation.deepseekHarnessConfig = config.lib.dag.entryAfter ["deepseekHarness"] ''
    DSH_HOME="$HOME/.dsh"
    mkdir -p "$DSH_HOME"

    # Mock keyless adapter (owned by dotfiles; safe to overwrite). Lets the
    # full agent loop run with zero API keys: shows up in the model picker as
    # "Mock (keyless) / Mock Echo".
    cp -f ${./dsh/mock-llm.mjs} "$DSH_HOME/mock-llm.mjs"

    # The mock imports @deepseek-ai/dsh-llm; resolve it from the dsh install.
    mkdir -p "$DSH_HOME/node_modules/@deepseek-ai"
    ln -sfn "$HOME/.npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm" \
      "$DSH_HOME/node_modules/@deepseek-ai/dsh-llm"

    # Home-level patch layer: composes after every profile's own layer, so one
    # file covers web and headless alike. Seed-if-absent: entries here may be
    # adjusted by hand later.
    if [ ! -f "$DSH_HOME/cordis.patch.yml" ]; then
      cat > "$DSH_HOME/cordis.patch.yml" <<EOF
    # Home-level dsh patch layer (managed seed from dotfiles; edits are yours).
    - insert:
        - id: mock-llm
          name: '$DSH_HOME/mock-llm.mjs'
    - id: agent-default-model
      config:
        provider: mistral
        model: devstral-medium-latest
    EOF
      echo "✅ Seeded $DSH_HOME/cordis.patch.yml"
    fi

    # Mistral provider route (catalog provider: endpoint/protocol/models come
    # from the built-in pi-ai catalog; only the credential reference is ours).
    # Append-if-absent: dsh owns this document and writes other sections.
    if ! grep -q "^llm-pi-ai:" "$DSH_HOME/settings.yaml" 2>/dev/null; then
      cat >> "$DSH_HOME/settings.yaml" <<EOF

    # Mistral route. The key is a reference; the secret resolves from
    # \$MISTRAL_API_KEY (sops, exported in fish), ~/.dsh/.credentials.yaml
    # (written by the web UI's Models page), or ~/.dsh/.env.
    llm-pi-ai:
      providers:
        mistral:
          apiKeyEnv: MISTRAL_API_KEY
          displayName: Mistral
    EOF
      echo "✅ Seeded llm-pi-ai settings section"
    fi
  '';

}
