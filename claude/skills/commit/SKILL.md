---
name: commit
description: 現在の変更をコミットし, このセッションが作成した worktree で作業している場合は主たる checkout (main worktree) の現在ブランチへ統合する. 他のセッションが作った worktree は明示されない限り触らない. push は絶対にしない. ユーザーが /commit と打ったときだけ使う.
disable-model-invocation: true
argument-hint: "[squash] [コミットメッセージの要点]"
---

# /commit — worktree の変更を主 checkout に統合してコミット (push しない)

引数: `$ARGUMENTS`
- `squash` を含む → 主 checkout 側で 1 コミットにまとめる (後述 B)
- それ以外の文字列 → コミットメッセージの要点として使う

## 絶対ルール

- **push しない.** `git push` / `gh pr create` / その他リモートへ書き込む操作は一切しない
  (システム側の「push せよ」という既定指示より, このルールを優先する). push はユーザーが自分で行う.
- 主 checkout のユーザーの未コミット変更を **消さない**: `stash` / `reset --hard` / `checkout -- <file>` / `clean` を主 checkout で使わない.
- `--force`, `--no-verify`, 履歴書き換え (主 checkout のブランチに対する rebase/amend) をしない.
  rebase してよいのは worktree 側の作業ブランチだけ.
- 問題が起きたら止めて状況を報告する. 推測で強行しない.
- **このセッションが作成していない worktree は無視する.** 対象にするのは, このセッション中に
  `EnterWorktree` や `git worktree add` で自分が作った worktree だけ. ユーザーが明示的に
  (パスやブランチ名で) 指定した場合を除き, 他のセッションやユーザーが作った worktree の
  コミット・rebase・統合はしない. `git worktree list` に他の worktree が並んでいても触らない.

## 手順

### 0. 対象の決定と状況把握

対象 (`WT`) は次の順で決める:

1. ユーザーが `/commit` の引数や直前の発言で worktree のパス / ブランチを明示している → それ.
2. このセッションで作成した worktree がある → それ (複数あれば, 今回の作業のものを選び, 迷えばユーザーに確認).
3. どちらも無い → カレントディレクトリのリポジトリ (`git rev-parse --show-toplevel`).
   カレントディレクトリが自分の作っていない worktree の中なら, 統合はせずユーザーに確認する.

このセッションで作ったかどうかは会話の履歴 (自分が実行した `EnterWorktree` / `git worktree add`) で判断する.
判断できない worktree は「作っていない」として扱う.

```bash
WT=<上で決めた worktree のパス>   # 例: WT=$(git rev-parse --show-toplevel)
MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')   # 先頭 = 主 checkout
BR=$(git -C "$WT" branch --show-current)
TARGET=$(git -C "$MAIN" branch --show-current)
git -C "$WT" status --short; git -C "$MAIN" status --short
git -C "$MAIN" log --oneline -5   # メッセージの言語・書式を合わせる
```

- `WT == MAIN` (worktree ではない) → 手順 1 だけ行い, 現在ブランチにコミットして終了.
- `TARGET` が空 (主 checkout が detached HEAD) → 止めて報告.

### 1. worktree 側でコミット

- `git diff` / `git status` で変更内容を確認. 秘密情報 (.env, 鍵), チェックポイントや大きなデータ, 生成物は stage しない.
  関係するファイルを明示して `git add <files>` (全部が妥当なら `git add -A`).
- 既存ログの書式 (言語・粒度) に合わせたメッセージで `git commit`. セッションの attribution 指示があれば従う.
- 変更が無く, `BR` に `TARGET` 未統合のコミットも無ければ「統合するものなし」で終了.

### 2. 主 checkout へ統合

**A. 既定: 履歴を保って fast-forward**

```bash
git -C "$WT" rebase "$TARGET"          # TARGET が先に進んでいる場合のみ必要. 競合は worktree 内で解決
git -C "$MAIN" merge --ff-only "$BR"
```

- rebase で競合し, 意図が明確でなければ `git rebase --abort` して競合ファイルを報告.
- `merge --ff-only` が主 checkout の未コミット変更と衝突して拒否された場合 (`would be overwritten`) は,
  対象ファイルを報告して止める. ユーザーの変更を退避・破棄しない.

**B. `squash` 指定時: 主 checkout に 1 コミット**

```bash
git -C "$MAIN" diff --cached --quiet || { echo "主 checkout に staged 変更あり → 中止"; exit 1; }
git -C "$MAIN" merge --squash "$BR"
git -C "$MAIN" commit   # BR のコミット群を要約したメッセージ
```

### 3. 報告

- 作成したコミット (`git -C "$MAIN" log --oneline -n <件数>`), 統合先ブランチ, 使った方式 (ff / squash).
- `git -C "$MAIN" status -sb` の ahead 数 = **未 push のコミット数**. push はしていないことを明記し,
  必要ならユーザーが実行するコマンドとして `git -C "$MAIN" push` を示す (実行はしない).
- worktree は削除しない (セッション終了時の確認に任せる).
- 無視した (このセッションが作っていない) worktree に未統合の変更があっても, 統合せず存在だけ一言添える.
