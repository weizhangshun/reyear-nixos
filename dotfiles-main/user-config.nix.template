# User Configuration Template
# Copy this file to user-config.nix and modify the values to match your setup

{
  # User settings
  username = "your-username";
  homeDirectory = "/home/your-username";  # or "/Users/your-username" on macOS
  
  # Git settings (can be overridden by sops secrets if configured)
  git = {
    name = "Your Full Name";
    email = "your.email@example.com";
  };
  
  # Platform-specific paths
  windowsUsername = "your-windows-username"; # Your Windows username for WSL VS Code integration
  
  # System settings
  system = "x86_64-linux"; # Your system architecture (e.g., "x86_64-linux", "aarch64-linux", "aarch64-darwin")
  stateVersion = "24.11"; # Home Manager state version - see https://nix-community.github.io/home-manager/release-notes.html
}
