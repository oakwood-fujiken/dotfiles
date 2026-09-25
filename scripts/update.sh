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

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  # bash -c "$(curl .../update.sh)" のようにファイル無しで実行された場合
  DOTFILES="${DOTFILES_DIR:-${HOME}/.dotfiles}"
fi
if [ ! -e "${DOTFILES}/.git" ]; then
  echo "dotfiles が見つかりません: ${DOTFILES}. 先に install.sh を実行してください" >&2
  exit 1
fi
XDG_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}"
BACKUP_DIR="${XDG_CONFIG_DIR}/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-$$"

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
  if [ -n "$(git -C "$DOTFILES" status --porcelain)" ]; then
    echo "dotfiles に未コミット変更があるため pull しません ($DOTFILES). --no-pull で手元の内容を反映できます" >&2
    exit 1
  fi
  echo "===== git pull ====="
  git -C "$DOTFILES" pull --ff-only
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
