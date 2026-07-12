#!/bin/bash

set -e

echo "===== Installing dotfiles ====="

# Detect OS
OS_TYPE="$(uname -s)"
DISTRO=""

if [ "$OS_TYPE" = "Linux" ]; then
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
  fi
fi

echo "Detected OS: $OS_TYPE${DISTRO:+ ($DISTRO)}"

# ===== Install repo =====
if [ ! -d "${HOME}"/.dotfiles ]; then
  git clone https://github.com/oakwood-fujiken/dotfiles.git "${HOME}"/.dotfiles
else
  echo "dotfiles already exists"
  exit 1
fi

# ===== Install system packages =====
if [ "$OS_TYPE" = "Darwin" ]; then
  # macOS: Install Homebrew
  if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon
    if [ -d /opt/homebrew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  else
    echo "Homebrew already installed"
  fi
elif [ "$OS_TYPE" = "Linux" ]; then
  # Linux: Install packages via apt/yum/pacman
  echo "Installing system packages for Linux..."

  case "$DISTRO" in
    ubuntu|debian)
      echo "Using apt package manager..."
      sudo apt update
      sudo apt install -y curl git poppler-utils ffmpeg libreoffice || echo "Warning: Some packages failed to install"
      ;;
    fedora|rhel|centos)
      echo "Using dnf/yum package manager..."
      if command -v dnf &> /dev/null; then
        sudo dnf install -y curl git poppler-utils ffmpeg libreoffice || echo "Warning: Some packages failed to install"
      else
        sudo yum install -y curl git poppler-utils ffmpeg libreoffice || echo "Warning: Some packages failed to install"
      fi
      ;;
    arch|manjaro)
      echo "Using pacman package manager..."
      sudo pacman -Sy --noconfirm curl git poppler ffmpeg libreoffice-fresh || echo "Warning: Some packages failed to install"
      ;;
    *)
      echo "Warning: Unsupported Linux distribution. Please install these packages manually:"
      echo "  - curl, git"
      echo "  - poppler-utils (pdftoppm)"
      echo "  - ffmpeg"
      echo "  - libreoffice"
      ;;
  esac
fi

# ===== Install mise =====
if ! (type 'mise' >/dev/null 2>&1); then
  curl https://mise.run | sh
fi

# ===== Deploy xdg-based configs =====
xdg_config_dir="${HOME}"/.config
if [ ! -d "${xdg_config_dir}" ]; then
  mkdir -p "${xdg_config_dir}"
fi

for item in "${HOME}"/.dotfiles/xdg_config/*; do
  base_item=$(basename "$item")
  link_name="${xdg_config_dir}/$base_item"
  if [ -f "$link_name" ]; then
    echo "$link_name exists, skipping"
    continue
  fi
  ln -s "$item" "$link_name"
done

# ===== Deploy bashrc =====
bashrc_target="${HOME}/.dotfiles/config/bashrc"
if [ -L "${HOME}"/.bashrc ] && [ "$(readlink "${HOME}"/.bashrc)" = "$bashrc_target" ]; then
  : # already symlinked to dotfiles bashrc, nothing to do
elif [ -f "${HOME}"/.bashrc ]; then
  if ! grep -qF 'source "$HOME/.dotfiles/config/bashrc"' "${HOME}"/.bashrc; then
    echo 'source "$HOME/.dotfiles/config/bashrc"' >> "${HOME}"/.bashrc
  fi
else
  ln -s "$bashrc_target" "${HOME}"/.bashrc
fi
source "${HOME}"/.bashrc

# ===== Install applications via Homebrew (macOS only) =====
if [ "$OS_TYPE" = "Darwin" ] && command -v brew &> /dev/null; then
  echo "Installing applications from Brewfile..."
  brew bundle --file="${HOME}"/.dotfiles/config/Brewfile || echo "Warning: Some Brewfile installations failed"
fi

# ===== Install dependencies =====
mise install -y

# ===== Setup Ghostty image display tools =====
if [ -f "${HOME}"/.dotfiles/scripts/setup_ghostty_imgcat.sh ]; then
  echo "Setting up Ghostty image display tools..."
  bash "${HOME}"/.dotfiles/scripts/setup_ghostty_imgcat.sh || echo "Warning: Ghostty imgcat setup failed"
fi

# ===== Post-installation messages =====
echo ""
echo "===== Installation Complete! ====="
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.bashrc"
echo "  2. Open Neovim and run ':Lazy sync' to install plugins"

if [ "$OS_TYPE" = "Darwin" ]; then
  echo "  3. Launch Ghostty terminal emulator from Applications or using 'open -a Ghostty'"
  echo ""
  echo "For SSH image display on remote servers, copy imgcat:"
  echo "  scp ~/.local/bin/imgcat user@server:~/bin/"
else
  echo "  3. (Optional) For SSH image display FROM this server, imgcat is installed at ~/.local/bin/imgcat"
  echo ""
  echo "Note: Ghostty is only available on macOS. On Linux, use a terminal that supports"
  echo "      Kitty graphics protocol (e.g., Kitty terminal, WezTerm) for image display."
fi
echo ""

# ===== Set up Macos =====
# if [ "$(uname)" = "Darwin" ]; then
#   bash "${HOME}"/.dotfiles/scripts/macos.sh
# fi
