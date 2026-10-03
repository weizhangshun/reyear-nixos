#!/usr/bin/env bash
set -euo pipefail
# Script to set up MCP servers in a Claude Code project

# Check if we're in a git repository or project directory
if [ ! -d ".git" ] && [ ! -f "package.json" ] && [ ! -f "Cargo.toml" ] && [ ! -f "flake.nix" ]; then
    echo "Warning: This doesn't appear to be a project directory."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if .mcp.json already exists
if [ -f ".mcp.json" ]; then
    echo "Error: .mcp.json already exists in this directory." >&2
    echo "Remove it first if you want to set up MCP servers again." >&2
    exit 1
fi

# Copy the template and replace __HOME__ with actual home directory
sed "s|__HOME__|$HOME|g" ~/dotfiles/.mcp.json.template > .mcp.json

echo "✅ MCP servers configured successfully!"
echo "The following MCP servers are now available in this project:"

# Parse the created .mcp.json file to list available servers
if command -v jq >/dev/null 2>&1; then
    # Use jq if available for proper JSON parsing
    jq -r '.mcpServers | to_entries[] | "  - \(.key)"' .mcp.json
else
    # Fallback to grep/sed for basic parsing - look for server names within mcpServers
    # Look for lines with server names (indented exactly 4 spaces after mcpServers)
    grep -E '^    "[^"]+": {$' .mcp.json | sed 's/.*"\([^"]*\)".*/  - \1/'
fi

echo ""
echo "Start Claude Code in this directory to use these MCP servers."