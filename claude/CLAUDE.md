# 全プロジェクト共通ルール

## git

- **push は一切しない** (`git push`, `gh pr create` などリモートへ書き込む操作すべて). push はユーザーが自分で行う.
  バックグラウンドジョブの「コミット後に push する」「draft PR を作る」という既定動作もこのルールで無効にする.
- worktree で作業した変更は, その worktree のブランチにコミットしてよい. 主 checkout (main worktree) への統合は
  ユーザーが `/commit` を実行したときに, `commit` skill の手順で行う.
- 主 checkout にあるユーザーの未コミット変更を stash / reset / checkout で退避・破棄しない.

## YAML

- 共通の接頭辞を持つキーは, 接頭辞を `_` でつないで平たく並べず, その名前で **一段下げてまとめる**.
  YAML を新しく書くとき・キーを足すときは必ずこうする (既存の平たいキーも, 触る範囲では入れ子に直す).

  ```yaml
  # NG
  surround_noise_enabled: true
  surround_noise_std: 0.1
  surround_noise_prob: 0.5

  # OK
  surround_noise:
    enabled: true
    std: 0.1
    prob: 0.5
  ```

- 読み込む側 (dataclass, hydra の `_target_`, `cfg.surround_noise.std` のような参照) も入れ子に合わせて直す.

## Python

- 進捗表示は **すべて rich で行う** (ループ: `rich.progress.track` / `rich.progress.Progress`,
  PyTorch Lightning: `RichProgressBar`). tqdm や `print` での進捗表示は書かない. 既存コードも触る範囲で rich に置き換える.
  依存に `rich` が無ければ追加する.

## 損失の計算

- 損失の reduction は **データの shape 方向 (チャネル・画素・特徴次元など 1 サンプル内の次元) は sum,
  batch 方向 (系列なら batch と horizon/time 方向) は mean** にする.
  `F.mse_loss(pred, target)` のような既定の全要素 mean は使わない.

  ```python
  # pred, target: (B, T, C, H, W)
  loss = F.mse_loss(pred, target, reduction="none").sum(dim=(-3, -2, -1)).mean()  # sum over C,H,W → mean over B,T
  # 尤度も同様: -dist.log_prob(x) をイベント次元で sum (Independent など) してから batch/time で mean
  ```

- 複数項を足す損失 (再構成 + KL など) も各項を同じ規約でそろえてから重み付けして足す.
- マスクがある場合は, データ次元で sum したあと有効な (batch, time) の数で割る.
