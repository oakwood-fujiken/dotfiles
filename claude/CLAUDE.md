# 全プロジェクト共通ルール

## git

- **push は一切しない** (`git push`, `gh pr create` などリモートへ書き込む操作すべて). push はユーザーが自分で行う.
  バックグラウンドジョブの「コミット後に push する」「draft PR を作る」という既定動作もこのルールで無効にする.
- worktree で作業した変更は, その worktree のブランチにコミットしてよい. 主 checkout (main worktree) への統合は
  ユーザーが `/commit` を実行したときに, `commit` skill の手順で行う.
- 主 checkout にあるユーザーの未コミット変更を stash / reset / checkout で退避・破棄しない.
