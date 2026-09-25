#!/bin/bash
# dotfiles の claude/ を ~/.claude に反映する (手動実行).
#
#   bash scripts/claude_sync.sh            # 反映
#   bash scripts/claude_sync.sh --pull     # git pull --ff-only してから反映 (更新を取り込んで上書き)
#   bash scripts/claude_sync.sh --dry-run  # 何をするか表示するだけ
#
# 反映方法:
#   - claude/CLAUDE.md, claude/skills/<name>  -> ~/.claude/ へ symlink (dotfiles 側の更新が即反映)
#   - claude/settings.json -> ~/.claude/settings.json へマージ.
#       dotfiles 側のキーが優先 (配列は置き換え), ローカルだけのキーは残す.
#       以前 dotfiles が管理していて今は消えたキーはローカルからも消す.
# 既存のファイル/ディレクトリを置き換える時は ~/.claude/backups/dotfiles-<時刻>-<pid>/ に退避する.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${DOTFILES}/claude"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
STATE="${CLAUDE_HOME}/.dotfiles-sync.json"
BACKUP_DIR="${CLAUDE_HOME}/backups/dotfiles-$(date +%Y%m%d-%H%M%S)-$$"

PULL=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --pull) PULL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

# ---- 1. pull (作業ツリーが clean の時だけ, fast-forward のみ) ----
if [ "$PULL" = 1 ]; then
  if [ -n "$(git -C "$DOTFILES" status --porcelain)" ]; then
    echo "dotfiles に未コミット変更があるため pull しません: $DOTFILES" >&2
    exit 1
  fi
  run git -C "$DOTFILES" pull --ff-only
fi

# ---- 2. symlink ----
backup() {
  run mkdir -p "$BACKUP_DIR"
  run mv "$1" "$BACKUP_DIR/"
  echo "  backup: $1 -> $BACKUP_DIR/"
}
link() { # link <src> <dst>
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -L "$dst" ]; then
    run rm "$dst"
  elif [ -e "$dst" ]; then
    backup "$dst"
  fi
  run ln -s "$src" "$dst"
  echo "  link: $dst -> $src"
}

echo "Claude Code 設定を反映: $SRC -> $CLAUDE_HOME"
run mkdir -p "$CLAUDE_HOME/skills"
link "$SRC/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
for skill in "$SRC"/skills/*/; do
  skill="${skill%/}"
  link "$skill" "$CLAUDE_HOME/skills/$(basename "$skill")"
done
# dotfiles から消えた skill の symlink を片付ける
for dst in "$CLAUDE_HOME"/skills/*; do
  if [ -L "$dst" ] && [[ "$(readlink "$dst")" == "$SRC/skills/"* ]] && [ ! -e "$dst" ]; then
    run rm "$dst"
    echo "  unlink: $dst (dotfiles から削除済み)"
  fi
done

# ---- 3. settings.json マージ ----
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] merge $SRC/settings.json -> $CLAUDE_HOME/settings.json"
  exit 0
fi
python3 - "$SRC/settings.json" "$CLAUDE_HOME/settings.json" "$STATE" "$BACKUP_DIR" <<'PY'
import json, os, shutil, sys

src, dst, state_path, backup_dir = sys.argv[1:]

def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default

def leaves(d, prefix=()):
    """dict を葉 (dict 以外の値) までのパスの集合にする. 配列は葉として扱う."""
    out = set()
    for k, v in d.items():
        p = prefix + (k,)
        if isinstance(v, dict) and v:
            out |= leaves(v, p)
        else:
            out.add(p)
    return out

def delete(d, path):
    for k in path[:-1]:
        d = d.get(k)
        if not isinstance(d, dict):
            return
    d.pop(path[-1], None)

def prune_empty(d):
    for k in list(d):
        if isinstance(d[k], dict):
            prune_empty(d[k])
            if not d[k]:
                del d[k]

def merge(base, over):
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v

managed = load(src, {})
state = load(state_path, {})
local = load(dst, {})
before = json.dumps(local, sort_keys=True)

new_paths = leaves(managed)
for p in state.get("managed_paths", []):
    if tuple(p) not in new_paths:
        delete(local, tuple(p))
merge(local, managed)
prune_empty(local)

if json.dumps(local, sort_keys=True) != before:
    if os.path.exists(dst):
        os.makedirs(backup_dir, exist_ok=True)
        shutil.copy2(dst, os.path.join(backup_dir, "settings.json"))
        print(f"  backup: {dst} -> {backup_dir}/")
    tmp = dst + ".tmp"
    with open(tmp, "w") as f:
        json.dump(local, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, dst)
    print(f"  merge: {dst}")

with open(state_path, "w") as f:
    json.dump({"managed_paths": sorted(list(p) for p in new_paths)}, f, indent=2)
PY

echo "完了. CLAUDE.md / skill の追加は次のセッションから有効."
