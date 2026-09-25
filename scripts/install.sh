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
# 途中で失敗しても再実行できる: 既に自分の dotfiles があればそれを使い,
# 別物 (他人の dotfiles, 中途半端な残骸など) があれば退避してから clone し直す.
REPO_SLUG="oakwood-fujiken/dotfiles"
REPO_URL="https://github.com/${REPO_SLUG}.git"
DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/.dotfiles}"

is_own_repo() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    *github.com[:/]"${REPO_SLUG}" | *github.com[:/]"${REPO_SLUG}.git") return 0 ;;
  esac
  return 1
}

if [ -e "$DOTFILES_DIR" ] || [ -L "$DOTFILES_DIR" ]; then
  if is_own_repo "$DOTFILES_DIR"; then
    echo "Using existing dotfiles: $DOTFILES_DIR"
  else
    backup="${DOTFILES_DIR}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "$DOTFILES_DIR is not ${REPO_SLUG} ($(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || echo 'not a git repo'))"
    echo "Moving it to $backup"
    mv "$DOTFILES_DIR" "$backup"
  fi
fi
if [ ! -e "$DOTFILES_DIR" ]; then
  git clone "$REPO_URL" "$DOTFILES_DIR"
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

# ===== Deploy configs (xdg_config / bashrc / mise install / brew bundle / Claude Code) =====
bash "${DOTFILES_DIR}"/scripts/update.sh --no-pull

# ===== Setup Ghostty image display tools =====
if [ -f "${DOTFILES_DIR}"/scripts/setup_ghostty_imgcat.sh ]; then
  echo "Setting up Ghostty image display tools..."
  bash "${DOTFILES_DIR}"/scripts/setup_ghostty_imgcat.sh || echo "Warning: Ghostty imgcat setup failed"
fi

# ===== Post-installation messages =====
echo ""
echo "===== Installation Complete! ====="
echo ""
echo "To update later: bash ${DOTFILES_DIR}/scripts/update.sh"
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
