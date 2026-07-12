#!/bin/bash

# Setup script for Ghostty image display support
# This script installs tools for displaying images in terminal over SSH

set -e

echo "Setting up image display tools for Ghostty..."

# Create local bin directory if it doesn't exist
mkdir -p "${HOME}/.local/bin"

# Install imgcat (a script for displaying images using Kitty graphics protocol)
if ! command -v imgcat &> /dev/null; then
  echo "Installing imgcat to ~/.local/bin/imgcat..."

  # Try to install to ~/.local/bin first (no sudo required)
  if curl -fsSL https://raw.githubusercontent.com/danielgatis/imgcat/main/imgcat -o "${HOME}/.local/bin/imgcat"; then
    chmod +x "${HOME}/.local/bin/imgcat"

    # Add ~/.local/bin to PATH if not already there
    if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
      echo "Note: Add ~/.local/bin to your PATH by adding this to your shell config:"
      echo '  export PATH="$HOME/.local/bin:$PATH"'
    fi

    echo "imgcat installed successfully to ~/.local/bin/imgcat"
  else
    echo "Warning: Failed to download imgcat"
    exit 1
  fi
else
  echo "imgcat already installed at $(command -v imgcat)"
fi

# Create a helper script for SSH image display
cat > "${HOME}/.local/bin/ssh-imgcat" << 'EOF'
#!/bin/bash
# Display images over SSH using Kitty graphics protocol
# Usage: ssh-imgcat <image_file>

if [ -z "$1" ]; then
  echo "Usage: ssh-imgcat <image_file>"
  exit 1
fi

# Check if we're in a compatible terminal
if [ -n "$GHOSTTY_RESOURCES_DIR" ] || [ "$TERM" = "xterm-ghostty" ]; then
  imgcat "$1"
else
  echo "Warning: Not running in Ghostty terminal"
  imgcat "$1"
fi
EOF

chmod +x "${HOME}/.local/bin/ssh-imgcat"

echo ""
echo "===== Setup complete! ====="
echo ""
echo "Installed tools:"
echo "  - imgcat: $(command -v imgcat || echo '~/.local/bin/imgcat')"
echo "  - ssh-imgcat: ~/.local/bin/ssh-imgcat"
echo ""
echo "To display images over SSH:"
echo "  1. Copy imgcat to your SSH server: scp ~/.local/bin/imgcat user@server:~/bin/"
echo "  2. On the remote server, use: imgcat image.png"
echo "  3. Or use the wrapper: ssh-imgcat image.png"
echo ""
echo "Note: SSH compression may interfere with image display."
echo "Consider using: ssh -o Compression=no user@server"
echo ""
