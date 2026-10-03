# Kourtni's Dotfiles

A portable, reproducible development environment configuration using Nix flakes and Home Manager with secure secrets management.

## ✨ Features

- **🖥️ Multi-Platform Support**: Works on Linux, macOS, WSL, and various architectures
- **🔒 Secure Secrets Management**: Encrypted secrets using sops-nix and age encryption
- **🐚 Modern Shell**: Fish shell with Starship prompt and vi key bindings
- **🎨 Beautiful Terminal**: Gruvbox Dark theme with Nerd Fonts
- **🔧 Development Tools**: Node.js, npm, git, Claude Code CLI auto-installation
- **📦 Reproducible**: Declarative configuration with Nix flakes
- **⚡ Fast Setup**: One-command installation on any supported system

## 🚀 Quick Start

### Prerequisites

- [Nix package manager](https://nixos.org/download.html) with flakes enabled
- [Home Manager](https://github.com/nix-community/home-manager) (installed automatically)

### Setup Your Configuration

1. **Clone the repository**:
   ```bash
   git clone https://github.com/kourtni/dotfiles.git
   cd dotfiles
   ```

2. **Create your user configuration**:
   ```bash
   cp user-config.nix.template user-config.nix
   # Edit user-config.nix with your username, email, etc.
   ```

3. **Install**:
   
   **IMPORTANT**: You must specify your system architecture:
   
   **For macOS/Darwin users:**
   ```bash
   # Intel Mac:
   nix run .#home-manager -- switch --flake .#$(whoami)@x86_64-darwin
   
   # Apple Silicon (M1/M2/M3):
   nix run .#home-manager -- switch --flake .#$(whoami)@aarch64-darwin
   ```
   
   **For Linux/WSL users:**
   ```bash
   # x86_64 Linux:
   nix run .#home-manager -- switch --flake .#$(whoami)@x86_64-linux
   
   # ARM64 Linux:
   nix run .#home-manager -- switch --flake .#$(whoami)@aarch64-linux
   ```
   
   **For NixOS users:**
   ```bash
   sudo nixos-rebuild switch --impure --flake .#wsl
   ```

### Quick Install (Advanced)

If you want to try the configuration as-is, you must specify your system:
```bash
# Intel Mac:
nix run github:kourtni/dotfiles#home-manager -- switch --flake github:kourtni/dotfiles#kourtni@x86_64-darwin

# Apple Silicon Mac:
nix run github:kourtni/dotfiles#home-manager -- switch --flake github:kourtni/dotfiles#kourtni@aarch64-darwin

# x86_64 Linux:
nix run github:kourtni/dotfiles#home-manager -- switch --flake github:kourtni/dotfiles#kourtni@x86_64-linux
```

## 🖥️ Supported Platforms

The configuration automatically detects your platform and adapts accordingly:

| Platform | Architecture | Detection | Status |
|----------|-------------|-----------|--------|
| NixOS | x86_64, aarch64 | `nixos` | ✅ |
| NixOS on WSL | x86_64 | `nixos-wsl` | ✅ |
| Linux + Nix | x86_64, aarch64 | `linux` | ✅ |
| Linux + Nix on WSL | x86_64 | `linux-wsl` | ✅ |
| macOS + Nix | x86_64, aarch64 | `darwin` | ✅ |

**Platform Variables Available:**
- `SYSTEM_TYPE`: One of the detection values above
- `IS_NIXOS`: `true` on NixOS, `false` on other Linux distros
- `IS_WSL`: `true` in WSL environments, `false` on native systems

## 📁 Project Structure

```
dotfiles/
├── flake.nix                    # Main flake configuration
├── flake.lock                   # Locked dependencies
├── user-config.nix              # User-specific settings (create from template)
├── user-config.nix.template     # Template for user configuration
├── home/
│   ├── default.nix              # Main home-manager configuration
│   ├── programs.nix             # Program configurations (git, fish, etc.)
│   ├── platforms.nix            # Platform-specific settings and detection
│   ├── hosts/                   # Host-specific overrides
│   ├── secrets/                 # Encrypted secrets (sops-nix)
│   └── starship-settings-from-toml.nix  # Starship prompt config
├── nixos/
│   ├── configuration.nix        # NixOS system configuration
│   ├── hardware-configuration.nix
│   └── wslconfig                # Reference .wslconfig for the Windows host (WSL only)
├── arch/                        # Arch Linux host layer for the GitHub Actions runner boxes
│   ├── pkglist-native.txt       # Explicit pacman packages
│   ├── pkglist-aur.txt          # Explicit AUR packages
│   └── zram-generator.conf      # zram swap config
├── scripts/
│   ├── bootstrap-arch-runner.sh # Turn a fresh Arch install into a runner box
│   └── setup-mcp.sh             # Add MCP servers to a project
└── README.md
```

## 🖥️ MCP Server Management

This repository can also be used to manage Model Context Protocol (MCP) server configurations.

- **Configuration**: Server details are defined in `home/mcp-servers.nix`.
- **Setup**: The `scripts/setup-mcp.sh` script applies the configurations to the servers.

### Available MCP Servers

1. **shadcn-ui-mcp-server**: Access to shadcn/ui v4 components and blocks
2. **context7**: Upstash Context7 MCP server for context management
3. **playwright**: Browser automation and testing via Playwright
4. **nixos**: NixOS configuration and package management assistance
5. **testing-sensei**: Enforces and guides unit testing principles in code generation

**GitHub MCP servers** are not installed by this repository. A GitHub MCP server is declared in the MCP client's own configuration, and each client keeps that configuration somewhere different. The clients installed here (Claude Code, Codex, Antigravity, opencode) all read their own files, so there is no single place this repository could put it.

What this repository does supply is the credential. A server that authenticates with a bearer header resolves `GITHUB_PERSONAL_ACCESS_TOKEN` from its own process environment, and any client launched from a shell inherits the export described in Secrets Management, whichever client it is.

### Managing MCP Servers

#### On Linux/WSL:
MCP servers can be managed as systemd services:

```bash
# For managed servers (shadcn, context7, testing-sensei):
mcp-<server>-status   # Check server status via systemctl
mcp-<server>-start    # Start the server via systemctl
mcp-<server>-stop     # Stop the server via systemctl
```

#### On macOS:
MCP servers are invoked on-demand by Claude Code directly. No manual management is needed.

```bash
mcp-status           # Check which MCP servers are installed
mcp-<server>-start   # Shows info that servers auto-start on macOS
```

**Note**: The `playwright` and `nixos` servers are invoked on-demand on all platforms.

### Adding MCP Servers to Projects

Run the setup script in any project directory:
```bash
~/dotfiles/scripts/setup-mcp.sh
```

This creates a `.mcp.json` file that configures Claude Code to use the available MCP servers.

## NixOS Hardware Configuration

For NixOS systems, this repository expects a `hardware-configuration.nix` file to be present in the `nixos/` directory. This file is machine-specific and should **not** be committed to the repository.

**To set up your `hardware-configuration.nix`:**

1.  **Generate the file on your NixOS system**:
    ```bash
    sudo nixos-generate-config --show-configuration > /tmp/hardware-configuration.nix
    ```
2.  **Copy it to your dotfiles**:
    ```bash
    cp /tmp/hardware-configuration.nix nixos/hardware-configuration.nix
    ```
    (Ensure you are in the root of your dotfiles repository when running this command.)
3.  **Add it to your local `.gitignore`**:
    To prevent accidentally committing your machine-specific hardware configuration, add the following line to your `.gitignore` file:
    ```
    nixos/hardware-configuration.nix
    ```
    This step is crucial for maintaining the portability of your dotfiles.

## WSL Host Configuration

On WSL, some settings live on the **Windows** side in `%USERPROFILE%\.wslconfig` and
cannot be managed by Nix. `nixos/wslconfig` is a documented reference copy; it enables
`autoMemoryReclaim` so a long-running VM doesn't fragment its memory until new
terminals fail with `Wsl/Service/0x8007274c`, and caps VM RAM.

1.  **Copy it to your Windows user profile** (from inside WSL):
    ```bash
    cp nixos/wslconfig "$(wslpath "$(powershell.exe -NoProfile -Command '$env:USERPROFILE' | tr -d '\r')")/.wslconfig"
    ```
2.  **Adjust `memory=`** to roughly half your host's RAM.
3.  **Restart the VM** from PowerShell so it takes effect:
    ```powershell
    wsl --shutdown
    ```

## Arch Linux Runner Hosts

The `builder-linux*` GitHub Actions runners are plain Arch Linux boxes with
standalone Home Manager on top. The Arch layer (package lists, zram config)
lives in `arch/`, and `scripts/bootstrap-arch-runner.sh` turns a fresh Arch
install into a fully configured runner. See `arch/README.md` for the steps.

## 🔧 Configuration Details

### Shell Environment

- **Shell**: Fish with vi key bindings
- **Prompt**: Starship with custom Gruvbox theme
- **Editor**: Neovim (set as `$EDITOR`)
- **Aliases**: `ll`, `gs` (git status), `hm-rebuild` (auto-detects system architecture)
- **GitHub token**: `GITHUB_PERSONAL_ACCESS_TOKEN`, exported from the `github/mcp_token` secret when it is present and readable (see Secrets Management)

### Development Tools

- **Node.js**: Version 24 with npm
- **Git**: Configured with secrets management
- **Claude Code**: Auto-installed CLI tool
- **DeepSeek Harness**: Auto-installed `dsh` CLI (see below)
- **VS Code**: Platform-aware PATH integration
- **Fonts**: Multiple Nerd Fonts for terminal icons (auto-installed on Linux, manual install required on macOS)

### DeepSeek Harness (`dsh`)

The [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) agent
harness is auto-installed into `~/.npm-global` like Claude Code, with two
quirks handled by the activation script: npm needs an enlarged heap to resolve
the dependency graph, and the native install scripts (`node-pty`, `koffi`,
dsh's spawn helper) are explicitly allow-listed.

Launch it through the `dsh` fish function, not the bare npm shim — the
function adds `node --expose-internals`, which HMR requires because dsh's
native internals-probe does not recognize the nixpkgs Node build:

```sh
dsh web                  # web UI on http://127.0.0.1:3080
dsh --profile headless "run the tests"
```

Activation also seeds `~/.dsh` (seed-if-absent; dsh writes these files too):

- `cordis.patch.yml` — home-level patch layer applying to every profile:
  mounts the keyless mock adapter and defaults the agent to Mistral
  `devstral-medium-latest`
- `settings.yaml` — the `llm-pi-ai` Mistral route referencing
  `MISTRAL_API_KEY`
- `mock-llm.mjs` — a scripted offline model ("Mock (keyless)" in the model
  picker) that exercises the full agent loop with zero API keys

The Mistral key resolves from `$MISTRAL_API_KEY` (sops secret
`mistral/api_key`, exported by fish when non-empty) or from
`~/.dsh/.credentials.yaml` written by the web UI's Models page. The committed
placeholder is empty; add a real key with
`sops home/secrets/secrets.enc.yaml`.

### Platform-Specific Features

The configuration automatically detects your platform and adapts:

- **NixOS**: Handles Nix store paths and NixOS-specific filesystem layout
- **Traditional Linux**: Uses standard paths like `/bin/bash` for compatibility  
- **WSL**: Adds Windows VS Code integration, cross-platform file access
- **macOS**: Sets Homebrew prefix, uses macOS-specific paths, provides font installation instructions
- **Environment Variables**: `SYSTEM_TYPE`, `IS_NIXOS`, `IS_WSL` for platform detection

## 🔐 Secrets Management

This configuration uses [sops-nix](https://github.com/Mic92/sops-nix) for secure secrets management. Works identically on all platforms (Linux, WSL, macOS).

### For New Users

1. **Generate your age key**:
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **Get your public key**:
   ```bash
   age-keygen -y ~/.config/sops/age/keys.txt
   ```

3. **Create your secrets file**:
   ```bash
   # Copy the example and edit with your values
   cp home/secrets/secrets.yaml.example home/secrets/secrets.yaml
   
   # Encrypt with your age key
   sops -e -a $(age-keygen -y ~/.config/sops/age/keys.txt) home/secrets/secrets.yaml > home/secrets/secrets.enc.yaml
   ```

4. **Update the flake**: Replace the age recipient in `home/secrets/secrets.enc.yaml` with your public key.

### Secrets Structure

```yaml
# home/secrets/secrets.yaml (unencrypted template)
github:
  name: "Your Name"
  email: "your.email@example.com"
  token: "ghp_your_github_token"
  mcp_token: "ghp_your_github_mcp_token"
```

### GitHub Tokens

The two GitHub tokens are separate secrets with different consumers. Neither is a substitute for the other.

| Secret | Consumed by | Notes |
|--------|-------------|-------|
| `github/token` | An activation script writes it to `~/.git-credentials` | Only reached when no other helper claims `github.com` first. If `gh auth setup-git` has run, gh's URL-scoped helper in `~/.gitconfig` takes precedence and this value goes unused. |
| `github/mcp_token` | Exported as `GITHUB_PERSONAL_ACCESS_TOKEN` in every interactive fish shell | Read by tools following that naming convention: MCP servers that authenticate to GitHub with a bearer header, and the shadcn wrapper, which uses it to lift API rate limits. |

Notes on the exported variable:

- It is set only when the secret exists, is readable, and is non-empty. If any of those fails the variable stays unset, which surfaces as a `401` rather than the `400` an empty bearer token produces.
- `gh` does not read it. The CLI honors `GH_TOKEN` and `GITHUB_TOKEN`, so exporting this cannot disturb gh's stored credential or git operations that authenticate through gh's helper.
- Suggested scopes for `mcp_token`: `repo` and `read:org` cover repository, issue, pull request, and Actions **read** access. Add `workflow` only if a tool needs to modify workflow files, remembering that anything running as you can read the variable. Organizations using SAML SSO require the token to be authorized for the organization separately from creating it.

## 🏠 Host-Specific Customization

You can add packages and configurations that only apply to specific machines without affecting other hosts that share this dotfiles repository.

### Automatic Host Detection

The configuration in `home/hosts/default.nix` automatically detects your hostname and conditionally applies settings:

```nix
{ config, pkgs, lib, ... }:

let
  # Automatically detect hostname
  hostnameFile = pkgs.runCommand "hostname" {} ''
    ${pkgs.hostname}/bin/hostname | cut -d. -f1 > $out
  '';
  hostname = builtins.readFile hostnameFile;
  isCxGawd = lib.strings.hasPrefix "CxGawd" hostname;
in
{
  # Host-specific packages
  home.packages = lib.optionals isCxGawd [
    pkgs.bazelisk  # Only installed on CxGawd host
  ];
}
```

To rebuild with host-specific settings, just use the normal rebuild command:
```bash
# Intel Mac:
home-manager switch --flake .#$(whoami)@x86_64-darwin

# Apple Silicon Mac:
home-manager switch --flake .#$(whoami)@aarch64-darwin

# x86_64 Linux:
home-manager switch --flake .#$(whoami)@x86_64-linux

# ARM64 Linux:
home-manager switch --flake .#$(whoami)@aarch64-linux

# Or use the hm-rebuild alias which handles architecture automatically
hm-rebuild
```

The hostname is automatically detected during the build process, so packages will only be installed on the appropriate hosts.

### Method 2: Host-Specific Files

Create a file named after your hostname in `home/hosts/`:
```bash
# Example: home/hosts/MyHost.nix
{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    # Packages only for MyHost
  ];
}
```

### Adding Host-Specific Packages

To add packages only to your current machine:

1. Edit `home/hosts/default.nix`
2. Add a condition for your hostname:
   ```nix
   let
     hostnameFile = pkgs.runCommand "hostname" {} ''
       ${pkgs.hostname}/bin/hostname | cut -d. -f1 > $out
     '';
     hostname = builtins.readFile hostnameFile;
     isMyHost = lib.strings.hasPrefix "MyHostName" hostname;
   in
   {
     home.packages = lib.optionals isMyHost [
       pkgs.package-name
     ];
   }
   ```
3. Rebuild with: `home-manager switch --flake .#$(whoami)@<system-architecture>`

   Where `<system-architecture>` is one of: `x86_64-darwin`, `aarch64-darwin`, `x86_64-linux`, or `aarch64-linux`

## 📋 Available Commands

### Home Manager

```bash
# Switch to new configuration (MUST specify system):
# Intel Mac:
home-manager switch --flake .#$(whoami)@x86_64-darwin

# Apple Silicon Mac:
home-manager switch --flake .#$(whoami)@aarch64-darwin

# x86_64 Linux:
home-manager switch --flake .#$(whoami)@x86_64-linux

# ARM64 Linux:
home-manager switch --flake .#$(whoami)@aarch64-linux

# Quick rebuild (aliased as 'hm-rebuild' in fish) - Works on all platforms
# Automatically uses your current username and system architecture
hm-rebuild
```

### System-Specific Commands

```bash
# Use specific system configuration (replace 'username' with your actual username)
home-manager switch --flake .#username@x86_64-darwin   # macOS Intel
home-manager switch --flake .#username@aarch64-darwin  # macOS Apple Silicon
home-manager switch --flake .#username@x86_64-linux    # Linux x64
home-manager switch --flake .#username@aarch64-linux   # Linux ARM
```

### NixOS (WSL)

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch --impure --flake .#wsl
```
We need `--impure` because our build build relies on the host specific, locally
installed `/etc/nixos/hardware-configuration.nix` file.

## ⚙️ User Configuration

The `user-config.nix` file contains all user-specific settings:

```nix
{
  # User settings
  username = "your-username";
  homeDirectory = "/home/your-username";
  
  # Git settings (overridden by sops secrets if configured)
  git = {
    name = "Your Full Name";
    email = "your.email@example.com";
  };
  
  # Platform-specific paths
  windowsUsername = "your-windows-username"; # For WSL VS Code integration (ignored on macOS)
  
  # System settings
  stateVersion = "24.11"; # Home Manager state version
}
```

This approach makes the dotfiles completely generic while allowing easy customization.

## 🔄 Updating

```bash
# Update flake inputs
nix flake update

# Apply updates (MUST specify system):
# Intel Mac:
home-manager switch --flake .#$(whoami)@x86_64-darwin

# Apple Silicon Mac:
home-manager switch --flake .#$(whoami)@aarch64-darwin

# x86_64 Linux:
home-manager switch --flake .#$(whoami)@x86_64-linux
```

### Automated maintenance (GitHub Actions)

Two scheduled workflows keep the repo from going stale:

- **`.github/workflows/update-flake.yml`** — weekly (Mondays 09:00 UTC). Runs
  `nix flake update`, builds the `x86_64-linux` home config to catch breakage,
  and opens a PR labeled `dependencies`. This keeps *versions* current
  (including Nix itself, which ships via `nixpkgs`).
- **`.github/workflows/audit-tools.yml`** — monthly (1st, 10:00 UTC). Checks
  each externally-sourced tool (flake inputs, npm packages, pinned `fetchurl`
  binaries) for **deprecation or supersession** — the kind of staleness
  `nix flake update` can't detect (e.g. a tool being replaced by a different
  one, as Gemini CLI was by Antigravity CLI). Authoritative signals (npm
  deprecation, GitHub repo archival, release-tag drift) are gathered
  deterministically with the built-in `GITHUB_TOKEN`; **GitHub Copilot** (via
  the Copilot CLI + `actions/ai-inference@v3`) writes the summary and judges
  supersession. Opens/updates a single issue labeled `tool-audit` when action is
  needed, and closes it when clean.
  - **No secret required.** The Copilot layer authenticates with the built-in
    `GITHUB_TOKEN` via the `copilot-requests: write` permission (the free GitHub
    Models endpoint was retired 2026-07-30). **Prerequisite:** the account/org
    that provides your Copilot seat must have the **Copilot CLI policy enabled**
    ("Allow use of Copilot CLI"). If it isn't, the Copilot step fails gracefully
    and the issue falls back to the deterministic findings.

#### TODO: broaden update-flake.yml CI validation

The flake-update workflow currently only builds the `x86_64-linux` home config,
because a plain Linux runner cannot validate the other targets:

- [ ] **macOS / darwin** — evaluating a darwin config forces an
  import-from-derivation that must *build* an `aarch64-darwin` derivation, which
  a Linux runner can't do. Add a `macos-latest` matrix job that really builds it
  (e.g. `homeConfigurations."runner@aarch64-darwin".activationPackage`, or
  `darwin-rebuild build --flake .`).
- [ ] **NixOS-WSL** — `nixosConfigurations.wsl` imports
  `/etc/nixos/hardware-configuration.nix` by absolute path, which is
  machine-specific, gitignored, and forbidden in pure flake eval. To validate in
  CI, generate a stub `hardware-configuration.nix` and build with `--impure`.

## 🛠️ Customization

### Adding Packages

Edit `home/platforms.nix` to add packages:

```nix
home.packages = with pkgs; [
  # Your additional packages
  firefox
  discord
];
```

### Platform-Specific Packages

```nix
# In home/platforms.nix
++ lib.optionals isDarwin [
  # macOS-specific packages
]
++ lib.optionals isLinux [
  # Linux-specific packages
]
```

### Modifying Shell Configuration

Edit `home/programs.nix` to customize fish shell, git, or other programs.

## 🎨 Fonts on macOS

Due to fontconfig dependencies that are Linux-specific, Nerd Fonts need to be installed separately on macOS:

### Via Homebrew (Recommended):
```bash
brew tap homebrew/cask-fonts
brew install --cask font-0xproto-nerd-font
brew install --cask font-droid-sans-mono-nerd-font
brew install --cask font-fira-code-nerd-font
brew install --cask font-jetbrains-mono-nerd-font
brew install --cask font-hack-nerd-font
```

### Manual Installation:
Download fonts from [Nerd Fonts Downloads](https://www.nerdfonts.com/font-downloads) and install them by double-clicking the `.ttf` files.

## 🐛 Troubleshooting

### Common Issues

1. **Secrets not decrypting**: Ensure your age key is in `~/.config/sops/age/keys.txt`
2. **VS Code not in PATH**: Check platform detection with `echo $SYSTEM_TYPE`
3. **Permission errors**: Ensure Nix has proper permissions for your user
4. **`code` command not found in Fish shell**: The configuration includes a portable `code` function that works on all platforms. If it still doesn't work:
   ```bash
   mkdir -p ~/.config/fish/functions
   echo 'function code
       "/mnt/c/Users/YOUR_USERNAME/AppData/Local/Programs/Microsoft VS Code/bin/code" $argv
   end' > ~/.config/fish/functions/code.fish
   ```
   Replace `YOUR_USERNAME` with your Windows username. This manually overrides the built-in function.

5. **VS Code Remote-WSL fails on NixOS** with error "Could not start dynamically linked executable": This occurs because VS Code's node binary cannot find required shared libraries on NixOS. To fix:
   
   a. Create the `server-env-setup` script that VS Code will run automatically:
   ```bash
   # Copy the server-env-setup script from sonowz/vscode-remote-wsl-nixos
   curl -o ~/.vscode-server/server-env-setup https://raw.githubusercontent.com/sonowz/vscode-remote-wsl-nixos/master/server-env-setup
   ```
   
   b. If you still get "libstdc++.so.6: cannot open shared object file", manually patch the node binary:
   ```bash
   # Patch the VS Code server node binary with correct library paths  
   nix shell nixpkgs#patchelf nixpkgs#stdenv.cc -c patchelf --set-rpath "$(nix eval --raw nixpkgs#stdenv.cc.cc.lib)/lib/" ~/.vscode-server/bin/*/node
   ```
   
   c. Try `code .` again - it should now work properly.
   
   Note: You may need to repeat step (b) after VS Code updates, as new versions will download fresh unpatched binaries.

### Debug Commands

```bash
# Check platform detection (works on all platforms)
echo "System: $SYSTEM_TYPE, NixOS: $IS_NIXOS, WSL: $IS_WSL"

# View decrypted secrets (for debugging)
sops -d home/secrets/secrets.enc.yaml

# Check flake evaluation
nix flake check
```

## 📄 License

This configuration is open source and available under the [MIT License](LICENSE).

## 🤝 Contributing

Feel free to fork this repository and adapt it for your own use! If you find improvements or fixes, pull requests are welcome.

## 🙏 Acknowledgments

- [Nix](https://nixos.org/) - Reproducible package management
- [Home Manager](https://github.com/nix-community/home-manager) - Declarative dotfiles management
- [sops-nix](https://github.com/Mic92/sops-nix) - Secrets management for Nix
- [Starship](https://starship.rs/) - Cross-shell prompt
- [Fish Shell](https://fishshell.com/) - Friendly interactive shell

---

**Made with ❤️ and Nix**
