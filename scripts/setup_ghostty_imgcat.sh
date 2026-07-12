#!/bin/bash

# Setup script for Ghostty image display support
# This script installs tools for displaying images in terminal over SSH

set -e

echo "Setting up image display tools for Ghostty..."

# Create local bin directory if it doesn't exist
mkdir -p "${HOME}/.local/bin"

# Install imgcat (danielgatis/imgcat - displays images using terminal graphics protocols)
if ! command -v imgcat &> /dev/null; then
  echo "Installing imgcat to ~/.local/bin/imgcat..."

  # Map this host's OS/arch to the release asset naming used by danielgatis/imgcat
  imgcat_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64|amd64) imgcat_arch="amd64" ;;
    arm64|aarch64) imgcat_arch="arm64" ;;
    i386|i686) imgcat_arch="386" ;;
    *) imgcat_arch="" ;;
  esac

  if [ -z "$imgcat_arch" ] || { [ "$imgcat_os" != "darwin" ] && [ "$imgcat_os" != "linux" ]; }; then
    echo "Warning: Unsupported OS/architecture for imgcat ($(uname -s)/$(uname -m)), skipping"
  else
    imgcat_tag="$(curl -fsSL https://api.github.com/repos/danielgatis/imgcat/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')"

    if [ -z "$imgcat_tag" ]; then
      echo "Warning: Failed to resolve latest imgcat release"
    else
      if [ "$imgcat_os" = "darwin" ]; then
        imgcat_asset="imgcat_${imgcat_tag}_${imgcat_os}_${imgcat_arch}.zip"
      else
        imgcat_asset="imgcat_${imgcat_tag}_${imgcat_os}_${imgcat_arch}.tar.gz"
      fi
      imgcat_url="https://github.com/danielgatis/imgcat/releases/download/v${imgcat_tag}/${imgcat_asset}"
      imgcat_tmpdir="$(mktemp -d)"

      if curl -fsSL "$imgcat_url" -o "${imgcat_tmpdir}/${imgcat_asset}"; then
        if [ "$imgcat_os" = "darwin" ]; then
          unzip -oq "${imgcat_tmpdir}/${imgcat_asset}" -d "$imgcat_tmpdir"
        else
          tar -xzf "${imgcat_tmpdir}/${imgcat_asset}" -C "$imgcat_tmpdir"
        fi
        mv "${imgcat_tmpdir}/imgcat" "${HOME}/.local/bin/imgcat"
        chmod +x "${HOME}/.local/bin/imgcat"

        # Add ~/.local/bin to PATH if not already there
        if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
          echo "Note: Add ~/.local/bin to your PATH by adding this to your shell config:"
          echo '  export PATH="$HOME/.local/bin:$PATH"'
        fi

        echo "imgcat installed successfully to ~/.local/bin/imgcat"
      else
        echo "Warning: Failed to download imgcat"
      fi
      rm -rf "$imgcat_tmpdir"
    fi
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
