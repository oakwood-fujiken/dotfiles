---
name: research-project-layout
description: 研究 (ML) プロジェクトを標準のディレクトリ/ファイル構成で新規作成する, または既存プロジェクトをその構成へ整理する. uv + main.py 単一エントリ + src/<pkg>/ + models/cfg/<model>.yaml (hydra _target_) + data/<name>/config.yaml + models/params|reports/<data>/<model>/seed:<n>/ の構成. 「新しい研究プロジェクトを作って」「リポジトリを雛形に沿って整理して」「プロジェクト構成をチェックして」などで使う.
---

# 研究プロジェクト標準構成

参照実装は `minMTRSSM` (世界モデル研究リポジトリ). 新規プロジェクトはこの構成で作り,
既存プロジェクトはこの構成へ寄せる.

## 標準構成

```
<project>/
├── pyproject.toml          # uv 管理. 依存 pin の理由はコメントで残す
├── uv.lock                 # commit する
├── .python-version
├── .gitignore              # templates/.gitignore
├── README.md               # 日本語. セットアップ / 学習 / 評価 / 手法メモ
├── main.py                 # 唯一の実験エントリ: --model --data_dir --seed --device --train/--evaluate
├── src/
│   └── <pkg>/              # ライブラリ本体. main.py からは `from src.<pkg>.xxx import ...`
│       ├── __init__.py
│       ├── config.py       # 全設定の dataclass (ExperimentConfig / DatasetConfig / TrainerConfig / ModelConfig ...)
│       ├── dataset.py      # LightningDataModule
│       ├── model.py        # LightningModule (大きくなれば encoders.py / decoders.py / loss.py などに分割)
│       └── eval.py         # 評価 → reports/ に書き出す
├── models/
│   ├── cfg/<model>.yaml    # 実験設定. `_target_: src.<pkg>.config.XxxConfig` を hydra instantiate. commit する
│   └── params/<data>/<model>/seed:<seed>/{model.ckpt,last.ckpt}   # チェックポイント. gitignore
├── data/
│   └── <data_name>/config.yaml     # データのメタ情報 (shape, 次元, 正規化統計, 取得元). commit する
│       └── (実データ *.npz / *.hdf5 / *.blosc2 は gitignore)
├── reports/<data>/<model>/seed:<seed>/  # 評価結果 (metrics.json, 図). gitignore
├── scripts/                # 補助スクリプト (比較・可視化・変換・外部ベンチ実行). main.py の代わりにはしない
├── outputs/                # hydra / 一時出力. gitignore
└── wandb/                  # WandbLogger の save_dir. gitignore
```

### 規約 (これが構成の本質)

1. **実験は `(model, data_dir, seed)` の 3 つ組で一意に決まる.**
   - `models/cfg/<model>.yaml` がモデル・学習設定, `data/<data_dir>/config.yaml` がデータ依存の値
     (`obs_shape`, `action_dim` など). main.py が後者を前者に注入してから `instantiate` する.
   - 出力パスは必ず `models/params/<data_dir>/<model>/seed:<seed>/` と `reports/<data_dir>/<model>/seed:<seed>/`.
   - wandb の run 名は `<data_dir>_<model>_seed=<seed>`, tags に seed と data_dir.
2. **設定は YAML + dataclass.** YAML の `_target_` で `src.<pkg>.config` の dataclass を指し,
   `OmegaConf.resolve` → `hydra.utils.instantiate` で型付き設定を得る. `${seed}` 等の interpolation で
   トップレベル値を下位に流す. 新しい手法のバリアントは **YAML を 1 枚増やす** ことで表現し,
   コードの分岐はフラグ (`mode: gaussian|dlml` など) で持つ.
3. **main.py はオーケストレーションだけ.** モデル・損失・データ処理は `src/<pkg>/` に置く.
   `--train` / `--evaluate` などのフラグで動作を切り替える.
4. **commit するのは コード / YAML / data の config.yaml / README / uv.lock.**
   チェックポイント, 実データ, reports, outputs, wandb は commit しない.
5. **サブパッケージ**: ベンチマーク連携など独立した塊は `src/<pkg>/<sub>/` に. 外部コードを vendoring する場合は
   `src/<vendored_name>/` に置き README に出典と commit を明記.
6. **README は日本語**で「セットアップ (追加の手作業含む) / 学習コマンド / 評価コマンド / 手法の説明と設定キー / バージョン pin の理由」を書く.

## 手順 A: 新規プロジェクト

1. プロジェクト名 (`<project>`) とパッケージ名 (`<pkg>`, 通常は同じ) を決める. ユーザーが指定していなければ
   ディレクトリ名から推定し, その仮定を明示して進める.
2. scaffold を実行 (既存ファイルは **上書きしない**):
   ```bash
   python ~/.claude/skills/research-project-layout/scripts/scaffold.py <target_dir> --pkg <pkg> [--python 3.11]
   ```
   `--dry-run` で作成予定だけ表示できる.
3. `cd <target_dir> && git init` (未初期化なら) → `uv sync` → `uv lock` 済みを確認.
4. 動作確認: `WANDB_MODE=disabled uv run python main.py --model default --data_dir example --epochs 1 --train`
   (テンプレートの toy モデル/データで 1 epoch 回る) → `--evaluate` で `reports/example/default/seed:0/metrics.json` が出ることを確認.
5. テンプレートの toy 部分 (`model.py` の MLP, `dataset.py` のランダムデータ, `data/example`) を実際の研究内容へ置き換える.
   構成と規約 1–4 は維持する.

## 手順 B: 既存プロジェクトを整理

**勝手に大移動しない.** 調査 → 対応表の提示 → 承認後に移動, の順で行う.

1. 監査: `python ~/.claude/skills/research-project-layout/scripts/scaffold.py <dir> --pkg <pkg> --check`
   で不足・逸脱を一覧する. 加えて自分で以下を確認:
   - エントリポイントはどこか (複数の train_*.py が散在していないか)
   - 設定はどこにあるか (argparse 直書き / json / 別の yaml 構成)
   - チェックポイント・結果の出力先, `.gitignore` の漏れ (巨大ファイルが track されていないか: `git ls-files | xargs du -ch 2>/dev/null | tail -1`)
2. 「現在のパス → 標準構成のパス」の対応表と, コード変更が必要な箇所 (import パス, ハードコードされた出力先) を
   ユーザーに提示し承認を得る. 大きく書き換わる場合は worktree / ブランチで作業する.
3. 移動は `git mv` で履歴を保つ. import (`from src.<pkg>...`) とパス文字列を更新する.
4. 不足ファイルだけ scaffold で補う (上書きしないので安全): `scaffold.py <dir> --pkg <pkg>`.
   既存の `.gitignore` / `README.md` / `pyproject.toml` は上書きされないので, テンプレートとの差分を見て手で統合する.
5. 既存の実験コマンドが同じ結果パスへ出力されることを, 1 epoch 程度の実行で確認する.

## テンプレート

`templates/` 以下. `__pkg__` / `{{pkg}}` / `{{project}}` / `{{python}}` が置換される.
テンプレートの Lightning / hydra / wandb は参照実装と同じスタック. 研究内容に合わないもの
(例: RL で Lightning を使わない) は置き換えてよいが, 規約 1–4 は守る.
