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

# ===== Required commands =====
for cmd in git curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd が必要です. インストールしてから再実行してください." >&2
    exit 1
  fi
done

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
    # 既存の clone を最新にしてから反映する (未コミット変更があれば手元の内容のまま)
    if [ -z "$(git -C "$DOTFILES_DIR" status --porcelain)" ]; then
      git -C "$DOTFILES_DIR" pull --ff-only || echo "Warning: git pull に失敗したため手元の内容で続行します"
    else
      echo "Warning: $DOTFILES_DIR に未コミット変更があるため pull せずに続行します"
    fi
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

# ===== Check system packages =====
# sudo が必要なインストール (apt / dnf / pacman / Homebrew 本体) は行わず, sudo コマンドの案内も出さない.
if [ "$OS_TYPE" = "Darwin" ] && ! command -v brew &>/dev/null && [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)" # Apple Silicon: インストール済みだが PATH に無い場合
fi

missing_pkgs=()
command -v pdftoppm &>/dev/null || missing_pkgs+=(poppler)
command -v ffmpeg &>/dev/null || missing_pkgs+=(ffmpeg)
command -v soffice &>/dev/null || command -v libreoffice &>/dev/null || missing_pkgs+=(libreoffice)

if [ "$OS_TYPE" = "Darwin" ] && ! command -v brew &>/dev/null; then
  echo "Note: Homebrew が見つかりません (インストールには管理者権限が必要なため自動では入れません)."
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  echo "  を実行後, もう一度 install.sh (または update.sh) を実行すると Brewfile も反映されます."
fi

if [ "${#missing_pkgs[@]}" -gt 0 ]; then
  echo "Note: 次のツールが見つかりません (任意. 無くても dotfiles の反映には影響しません): ${missing_pkgs[*]}"
  if [ "$OS_TYPE" = "Darwin" ] && command -v brew &>/dev/null; then
    echo "  brew install poppler ffmpeg && brew install --cask libreoffice"
  fi
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
