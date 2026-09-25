#!/bin/bash
# dotfiles の内容を今の環境に反映する. 何度実行しても同じ結果になる (install.sh からも呼ばれる).
#
#   bash ~/.dotfiles/scripts/update.sh            # git pull してから反映
#   bash ~/.dotfiles/scripts/update.sh --no-pull  # 手元の内容をそのまま反映
#
# 反映するもの:
#   - xdg_config/*  -> ~/.config/* へ symlink (実体があれば ~/.config/.dotfiles-backup/<時刻>/ へ退避)
#   - config/bashrc -> ~/.bashrc から読み込む
#   - mise install / brew bundle (macOS)
#   - claude/ -> ~/.claude (scripts/claude_sync.sh)

set -euo pipefail

# git が認証の入力待ちで止まらないようにする (削除されたリポジトリは GitHub が認証を要求してくるため)
export GIT_TERMINAL_PROMPT=0

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  # bash -c "$(curl .../update.sh)" のようにファイル無しで実行された場合
  DOTFILES="${DOTFILES_DIR:-${HOME}/.dotfiles}"
fi
if [ ! -e "${DOTFILES}" ]; then
  echo "dotfiles が見つかりません: ${DOTFILES}. 先に install.sh を実行してください" >&2
  exit 1
fi
XDG_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}"
BACKUP_DIR="${XDG_CONFIG_DIR}/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-$$"

REPO_SLUG="oakwood-fujiken/dotfiles"
REPO_URL="https://github.com/${REPO_SLUG}.git"

is_own_repo() {
  local url
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1
  case "$url" in
    *github.com[:/]"${REPO_SLUG}" | *github.com[:/]"${REPO_SLUG}.git") return 0 ;;
  esac
  return 1
}

# 自分の dotfiles を origin/main に fast-forward する. できない (未コミット変更 / 独自コミット /
# main 以外のブランチ) 場合は 1 を返す. オフライン等で fetch できない時は手元の内容で続行 (0).
fast_forward_repo() {
  local dir="$1"
  if ! GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch -q origin main; then
    echo "Warning: git fetch に失敗したため手元の内容で続行します" >&2
    return 0
  fi
  [ -z "$(git -C "$dir" status --porcelain)" ] || return 1
  [ "$(git -C "$dir" branch --show-current)" = "main" ] || return 1
  git -C "$dir" merge-base --is-ancestor HEAD origin/main || return 1
  git -C "$dir" merge -q --ff-only origin/main
}

# 古い / 他人の / 壊れた dotfiles を <dir>.bak-<時刻> に退避して clone し直す (中身は消さない)
reclone_repo() {
  local dir="$1" backup
  backup="${dir}.bak-$(date +%Y%m%d-%H%M%S)"
  echo "Moving $dir to $backup and cloning ${REPO_SLUG}"
  mv "$dir" "$backup"
  git clone -q "$REPO_URL" "$dir"
}

PULL=1
for arg in "$@"; do
  case "$arg" in
    --no-pull) PULL=0 ;;
    -h | --help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

# ===== Pull =====
if [ "$PULL" = 1 ]; then
  echo "===== Update dotfiles repo ====="
  default_dir="${DOTFILES_DIR:-${HOME}/.dotfiles}"
  # 既定の ~/.dotfiles (symlink でない実体) だけは, 古い / 他人の clone を退避して clone し直してよい.
  # 開発用の checkout (~/work/dotfiles 等) や symlink の場合は作業内容を尊重して手元の内容で続行する.
  if [ "$DOTFILES" = "$default_dir" ] && [ ! -L "$DOTFILES" ]; then
    if ! is_own_repo "$DOTFILES"; then
      echo "$DOTFILES is not ${REPO_SLUG}"
      reclone_repo "$DOTFILES"
    elif ! fast_forward_repo "$DOTFILES"; then
      echo "$DOTFILES は origin/main に fast-forward できません (未コミット変更 / 独自コミット / 別ブランチ)"
      reclone_repo "$DOTFILES"
    fi
  elif ! fast_forward_repo "$DOTFILES"; then
    echo "Warning: $DOTFILES は fast-forward できないため手元の内容で続行します" >&2
  fi
  echo "dotfiles: $(git -C "$DOTFILES" log --oneline -1)"
  # 更新後の update.sh で最初からやり直す (古いスクリプトや curl 経由の版で続きを実行しない)
  exec bash "${DOTFILES}/scripts/update.sh" --no-pull
fi

# ===== xdg_config =====
echo "===== Deploy xdg_config -> ${XDG_CONFIG_DIR} ====="
mkdir -p "$XDG_CONFIG_DIR"
for item in "${DOTFILES}"/xdg_config/*; do
  name="$(basename "$item")"
  dst="${XDG_CONFIG_DIR}/${name}"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$item" ]; then
      continue
    fi
    echo "  relink: $dst ($(readlink "$dst") -> $item)"
  elif [ -e "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/"
    echo "  backup: $dst -> $BACKUP_DIR/"
  else
    echo "  link: $dst -> $item"
  fi
  # -n: dst がディレクトリへの symlink でも中に潜らず, dst 自体を置き換える
  ln -sfn "$item" "$dst"
done
# dotfiles の xdg_config を指していたが, 対象が無くなった symlink を片付ける
for dst in "$XDG_CONFIG_DIR"/*; do
  if [ -L "$dst" ] && [ ! -e "$dst" ] && [[ "$(readlink "$dst")" == "${DOTFILES}/xdg_config/"* ]]; then
    rm "$dst"
    echo "  unlink: $dst (dotfiles から削除済み)"
  fi
done

# ===== bashrc =====
echo "===== Deploy bashrc ====="
bashrc_target="${DOTFILES}/config/bashrc"
source_line="source \"${bashrc_target}\""
if [ -L "${HOME}/.bashrc" ] && [ "$(readlink "${HOME}/.bashrc")" = "$bashrc_target" ]; then
  : # dotfiles の bashrc への symlink
elif [ -L "${HOME}/.bashrc" ] && [ ! -e "${HOME}/.bashrc" ]; then
  ln -sfn "$bashrc_target" "${HOME}/.bashrc"
  echo "  relink: ~/.bashrc -> $bashrc_target (リンク切れを修正)"
elif [ -e "${HOME}/.bashrc" ]; then
  if ! grep -qF "$bashrc_target" "${HOME}/.bashrc"; then
    echo "$source_line" >>"${HOME}/.bashrc"
    echo "  append: ~/.bashrc に $source_line を追加"
  fi
else
  ln -s "$bashrc_target" "${HOME}/.bashrc"
  echo "  link: ~/.bashrc -> $bashrc_target"
fi
# ~/.bashrc が dotfiles 配下の存在しないファイルを読んでいたら, その行をコメントアウトする
# (シェル起動のたびにエラーになるため. 元の ~/.bashrc は退避する)
if [ -f "${HOME}/.bashrc" ] && [ ! -L "${HOME}/.bashrc" ]; then
  tmp_bashrc="$(mktemp)"
  disabled=0
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+([^[:space:]]+) ]]; then
      path="${BASH_REMATCH[2]}"
      path="${path//\"/}"
      path="${path//\'/}"
      path="${path/\$\{HOME\}/$HOME}"
      path="${path/\$HOME/$HOME}"
      path="${path/#\~/$HOME}"
      if [[ "$path" == "$DOTFILES"/* ]] && [ ! -e "$path" ]; then
        echo "# [dotfiles] 存在しないファイルのため無効化: $line" >>"$tmp_bashrc"
        echo "  disable: ~/.bashrc:${lineno} ($path が存在しない)"
        disabled=1
        continue
      fi
    fi
    printf '%s\n' "$line" >>"$tmp_bashrc"
  done <"${HOME}/.bashrc"
  if [ "$disabled" = 1 ]; then
    mkdir -p "$BACKUP_DIR"
    cp -p "${HOME}/.bashrc" "$BACKUP_DIR/bashrc"
    echo "  backup: ~/.bashrc -> $BACKUP_DIR/bashrc"
    cat "$tmp_bashrc" >"${HOME}/.bashrc"
  fi
  rm -f "$tmp_bashrc"
fi

# ===== mise =====
mise_bin="$(command -v mise || true)"
[ -z "$mise_bin" ] && [ -x "${HOME}/.local/bin/mise" ] && mise_bin="${HOME}/.local/bin/mise"
if [ -n "$mise_bin" ]; then
  echo "===== mise self-update / install ====="
  # 古い mise は廃止済みの URL (python-precompiled 等) や旧プラグインを使って失敗するので, 先に本体を更新する.
  # パッケージマネージャ経由で入れた mise は self-update できないので失敗しても続行.
  "$mise_bin" self-update -y || echo "Warning: mise self-update に失敗 (パッケージマネージャで入れた場合はそちらで更新してください)"
  # 古い mise が入れた asdf プラグインのうち, 取得元リポジトリが消えたもの (例: chessmango/asdf-zellij) を削除する.
  # 削除したツールは mise 標準のバックエンド (aqua 等) で入れ直される. インストール済みのバージョンは残る.
  plugins_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/mise}/plugins"
  # オフライン時に全プラグインを「到達不能」と誤判定しないよう, GitHub に届く時だけ判定する
  if ! timeout 30 git ls-remote -q https://github.com/jdx/mise.git HEAD >/dev/null 2>&1; then
    plugins_dir="/nonexistent"
  fi
  for plugin_dir in "$plugins_dir"/*/; do
    [ -d "${plugin_dir}.git" ] || continue
    plugin="$(basename "$plugin_dir")"
    url="$(git -C "$plugin_dir" config --get remote.origin.url 2>/dev/null || true)"
    [ -n "$url" ] || continue
    if ! timeout 30 git ls-remote -q "$url" HEAD >/dev/null 2>&1; then
      echo "  remove plugin: $plugin ($url に到達できないため. mise 標準のバックエンドで入れ直されます)"
      "$mise_bin" plugins uninstall "$plugin" || echo "Warning: plugin $plugin の削除に失敗"
    fi
  done
  # 一部のツールが失敗しても残りの反映 (Claude Code 設定など) は続ける. 再実行で失敗分だけ再試行される.
  # $HOME で実行し, カレントディレクトリのプロジェクト設定 (.python-version 等) を拾わないようにする
  (cd "$HOME" && "$mise_bin" install -y) || echo "Warning: mise install で失敗したツールがあります. 'mise install' を再実行してください"
else
  echo "warning: mise が見つからないのでスキップ (install.sh でインストールされます)" >&2
fi

# ===== Homebrew (macOS) =====
if [ "$(uname -s)" = "Darwin" ] && command -v brew &>/dev/null; then
  echo "===== brew bundle ====="
  brew bundle --file="${DOTFILES}/config/Brewfile" || echo "Warning: Some Brewfile installations failed"
fi

# ===== Claude Code =====
echo "===== Claude Code ====="
if command -v python3 &>/dev/null; then
  bash "${DOTFILES}/scripts/claude_sync.sh"
else
  echo "warning: python3 が見つからないので Claude Code 設定の反映をスキップ" >&2
fi

echo ""
echo "===== Update complete ====="
echo "新しいシェルを開くか 'source ~/.bashrc' で反映されます."
