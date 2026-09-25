<div align="center">

# .dotfiles

Minimal dotfiles for my `macOS` and `Linux`.

![platform](https://img.shields.io/badge/platform-macOS%20|%20Linux-blue)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/nomutin/dotfiles)
[![ci](https://github.com/nomutin/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/nomutin/dotfiles/actions/workflows/ci.yaml)
[![lint](https://github.com/nomutin/dotfiles/actions/workflows/lint.yaml/badge.svg)](https://github.com/nomutin/dotfiles/actions/workflows/lint.yaml)

</div>

```shell
bash -c "$(curl https://raw.githubusercontent.com/oakwood-fujiken/dotfiles/main/scripts/install.sh)"
```

`install.sh` は途中で失敗しても再実行できる. `~/.dotfiles` が自分の dotfiles ならそれを使い,
別物 (他人の dotfiles など) なら `~/.dotfiles.bak-<時刻>` に退避してから clone し直す.
sudo が必要な処理 (apt 等でのパッケージ導入, Homebrew 本体のインストール) は行わず, 不足していればコマンドを案内するだけ. `git` と `curl` は事前に必要.

### Update

```shell
bash ~/.dotfiles/scripts/update.sh            # git pull してから反映
bash ~/.dotfiles/scripts/update.sh --no-pull  # 手元の内容を反映
```

`xdg_config/*` の symlink (実体があれば `~/.config/.dotfiles-backup/` へ退避, dotfiles から消した項目のリンクは削除),
bashrc, `mise install`, `brew bundle` (macOS), Claude Code 設定 (`claude_sync.sh`) をまとめて反映する. 何度実行しても同じ結果になる.

## Apps

- Shell - [bash](https://www.gnu.org/software/bash/)
- Terminal Emulator - [Ghostty](https://ghostty.org/)
- CLI Manager - [mise](https://mise.jdx.dev/)
- App Manager (Mac) - [Homebrew](https://brew.sh)
- Terminal Multiplexer - [zellij](https://zellij.dev)
- Text Editor - [neovim](https://neovim.io)

## Claude Code

`claude/` を `~/.claude/` に反映する (`scripts/install.sh` からも実行される).

```shell
bash ~/.dotfiles/scripts/claude_sync.sh          # 反映
bash ~/.dotfiles/scripts/claude_sync.sh --pull   # dotfiles を git pull してから反映 (更新を取り込んで上書き)
bash ~/.dotfiles/scripts/claude_sync.sh --dry-run
```

| dotfiles | ~/.claude | 方法 |
|---|---|---|
| `claude/CLAUDE.md` | `CLAUDE.md` | symlink |
| `claude/skills/<name>/` | `skills/<name>` | symlink (dotfiles に無い skill には触らない) |
| `claude/settings.json` | `settings.json` | マージ. dotfiles 側のキーが優先 (配列は置き換え), ローカルだけのキーは保持. dotfiles から消したキーはローカルからも消える |

`claude/skills/scientific-figure-making/` は [figures4papers](https://github.com/ChenLiu-1996/figures4papers) からの取り込み (CC BY-NC 4.0, 出典と更新方法は同ディレクトリの `SOURCE.md`).

置き換えた既存ファイルは `~/.claude/backups/dotfiles-<時刻>-<pid>/` に退避される.
~/.claude 側で skill を編集すると symlink 先の dotfiles が変わるので, そのまま dotfiles でコミットできる.
