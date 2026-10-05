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
├── main.py                 # 唯一の実験エントリ: `uv run python main.py --train` だけで既定の実験が回る
├── src/
│   └── <pkg>/              # ライブラリ本体. main.py からは `from src.<pkg>.xxx import ...`
│       ├── __init__.py
│       ├── config.py       # 全設定の dataclass (ExperimentConfig / DatasetConfig / TrainerConfig / ModelConfig ...)
│       ├── dataset.py      # LightningDataModule
│       ├── model.py        # LightningModule (大きくなれば encoders.py / decoders.py / loss.py などに分割)
│       ├── eval.py         # 評価 → reports/ に書き出す
│       ├── callbacks.py    # Lightning の callback. ProgressBarCallback (進捗) と VisualizePrediction (生成/再構成の可視化)
│       └── <sub>/          # (必要なら) ベンチマーク連携や, 外部リポジトリから抜き出して実装し直した部分
├── models/
│   ├── cfg/<model>.yaml    # 実験設定. `_target_: src.<pkg>.config.XxxConfig` を hydra instantiate. commit する
│   └── params/<data>/<model>/seed:<seed>/{model.ckpt,last.ckpt}   # チェックポイント. gitignore
├── data/
│   └── <data_name>/config.yaml     # データのメタ情報 (shape, 次元, 正規化統計, 取得元). commit する
│       └── (実データ *.npz / *.hdf5 / *.blosc2 は gitignore)
├── reports/<data>/<model>/seed:<seed>/  # 評価結果 (metrics.json, 図). gitignore
├── third_party/<name>/     # (必要なら) 別リポジトリのプロジェクト全体. git submodule
├── scripts/                # 補助スクリプト (比較・可視化・変換・外部ベンチ実行). main.py の代わりにはしない
├── tests/                  # (必要なら) テスト. 作ってよいが gitignore (commit しない)
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
   共通の接頭辞を持つキーは `surround_noise_std` のように平たく並べず, `surround_noise:` の下に一段下げてまとめ,
   対応する dataclass もネストさせる (`surround_noise: SurroundNoiseConfig`).
3. **main.py はオーケストレーションだけ.** モデル・損失・データ処理は `src/<pkg>/` に置く.
   `--train` / `--evaluate` などのフラグで動作を切り替える.
4. **commit するのは コード / YAML / data の config.yaml / README / uv.lock.**
   チェックポイント, 実データ, reports, outputs, wandb は commit しない.
   `tests/` も作ってよいが commit しない (手元での確認用. `.gitignore` に入れる).
5. **リポジトリ内で完結させる.** `git clone` → `uv sync` した 1 ディレクトリだけで学習・評価が動くこと.
   兄弟ディレクトリなどリポジトリ外の場所を前提にしない.
   - `--oc_storm_root ../OC-STORM` のように **外部ディレクトリの場所を CLI 引数や設定で受け取る実装は禁止**.
     `../` や `~/`, 絶対パスをコード・YAML に書かない.
   - 外部リポジトリのコードは, 必要な範囲で次のどちらかにする (pip で入るものは単に `pyproject.toml` の依存にする):
     - **プロジェクト全体が要る** (ベースライン一式を動かす, 環境・ベンチマークとして使うなど):
       `git submodule add <url> third_party/<name>` で入れる. 中身は編集しない. パッケージとして import するなら
       `uv add --editable third_party/<name>`. README のセットアップに `git submodule update --init --recursive` を書く.
     - **一部のモジュールだけ欲しい** (OC-STORM の特定の encoder だけ, など): submodule にせず, 必要な箇所だけを抜き出して
       `src/<pkg>/` の中に自分のコードとして実装する (このプロジェクトの config dataclass / 命名に合わせ, 使わない分岐や依存は落とす).
       ファイル冒頭のコメントと README に出典 (リポジトリ URL, commit, 元ファイル) を書く.
     - 迷ったら後者. 数ファイルのために丸ごと submodule を足さない.
   - 外部の学習済み重みは `models/params/` 以下, 外部データは `data/<data_name>/` 以下に置く (取得手順は README か
     `scripts/` のダウンロードスクリプトに). 容量の都合で実体を別ディスクに置く場合も, コードが見るのは
     リポジトリ内のパスだけにし, symlink で繋ぐ.
   - パスはリポジトリルートからの相対で, 規約 1 の `(model, data_dir, seed)` から組み立てる. パス自体を引数にしない.
   - ベンチマーク連携など自前の独立した塊は `src/<pkg>/<sub>/` に置く.
6. **CLI 引数は最小限, すべて既定値を持つ.** 普段の学習は `uv run python main.py --train` で済むようにする.
   - CLI に出すのは実験の識別 (`--model --data_dir --seed`), 実行環境 (`--device`), 動作切り替え (`--train --evaluate` など) だけ.
     `--model` / `--data_dir` の既定値はそのプロジェクトの主実験にする. `required=True` は使わない.
   - ハイパーパラメータ (epochs, batch_size, lr, ...) は `models/cfg/<model>.yaml` に書き, dataclass 側にも既定値を持たせる.
     CLI 引数として増やさない. 条件を変えたいときは YAML を 1 枚増やす (規約 2).
   - データ依存の値は `data/<data_dir>/config.yaml` から注入する (規約 1). CLI で渡さない.
   - 一時的な上書き用の引数 (`--epochs` など動作確認用) は既定値 `None` = 「YAML の値を使う」とする.
7. **ログのキーは `loss/` と `metrics/` で分ける.** wandb で「最適化している量」と「見ているだけの量」を混ぜない.
   - `loss/<key>/{train,val}`: **実際に backprop している値**. 合計損失 (`loss/loss/...`) と, それに足し込まれている各項
     (`loss/recon/...`, `loss/kl/...` など. 重みを掛けた後ではなく掛ける前の値でよいが, 合計に入っている項だけ).
     val 側は勾配を流さないが, train で backprop している量と同じ定義の値なので `loss/` に置く.
   - `metrics/<key>/{train,val}`: **backprop しない観察用の値** (精度, MAE, PSNR, 勾配ノルム, `detach` した診断量,
     合計損失に入れていない補助損失など).
   - ある項を係数 0 やフラグで損失から外したら, そのキーも `metrics/` へ移す.
   - ModelCheckpoint / EarlyStopping は `loss/<monitor_key>/val` を監視する. 学習ループの構成 (1 epoch = 1 周, 毎 epoch val,
     `last.ckpt` は毎回 / `model.ckpt` は best のみ, `max_epochs`, early stopping) は `~/.claude/CLAUDE.md` の「モデルの学習」に従う.
8. **進捗表示はすべて rich.** 学習は `src/<pkg>/callbacks.py` の `ProgressBarCallback` (minMTRSSM と同じテーマの
   `RichProgressBar`) を **既定で** Trainer の callbacks に入れる. 評価・データ前処理・`scripts/` のループは
   `rich.progress.track` / `Progress` を使う. tqdm や `print` での進捗表示は使わない.
9. **生成・再構成があるなら, 学習中に target と並べて見られるようにする.** `callbacks.py` の `VisualizePrediction` を
   Trainer に入れ, `validation_step` が `prediction/target` (reference/target) と `prediction/<name>` (生成・再構成, 複数可)
   を返す. val の最初の batch を `visualize.every_n_epoch` ごとに wandb へログする.
   - 時系列画像 (B, T, C, H, W) は各 step で `[target | <name> ...]` を横に並べ, **1 step = 1 frame の mp4 動画** (`prediction/video`).
   - 画像 (B, C, H, W) は並べた画像, ベクトル (B, T, D) / (B, D) は同じ軸範囲で重ねた折れ線.
   - 画像は [0, 1] で返す. 可視化専用の重い処理 (サンプリングなど) は `every_n_epoch` の epoch の batch 0 だけで行う.
10. **README は日本語**で「セットアップ (追加の手作業含む) / 学習コマンド / 評価コマンド / 手法の説明と設定キー / バージョン pin の理由」を書く.

## 手順 A: 新規プロジェクト

1. プロジェクト名 (`<project>`) とパッケージ名 (`<pkg>`, 通常は同じ) を決める. ユーザーが指定していなければ
   ディレクトリ名から推定し, その仮定を明示して進める.
2. scaffold を実行 (既存ファイルは **上書きしない**):
   ```bash
   python ~/.claude/skills/research-project-layout/scripts/scaffold.py <target_dir> --pkg <pkg> [--python 3.11]
   ```
   `--dry-run` で作成予定だけ表示できる.
3. `cd <target_dir> && git init` (未初期化なら) → `uv sync` → `uv lock` 済みを確認.
4. 動作確認: `WANDB_MODE=disabled uv run python main.py --epochs 1 --train`
   (テンプレートの toy モデル/データで 1 epoch 回る) → `--evaluate` で `reports/example/default/seed:0/metrics.json` が出ることを確認.
5. テンプレートの toy 部分 (`model.py` の MLP, `dataset.py` のランダムデータ, `data/example`) を実際の研究内容へ置き換える.
   `--model` / `--data_dir` の既定値を主実験のものに直す. 構成と規約 1–9 は維持する.

## 手順 B: 既存プロジェクトを整理

**勝手に大移動しない.** 調査 → 対応表の提示 → 承認後に移動, の順で行う.

1. 監査: `python ~/.claude/skills/research-project-layout/scripts/scaffold.py <dir> --pkg <pkg> --check`
   で不足・逸脱を一覧する. 加えて自分で以下を確認:
   - エントリポイントはどこか (複数の train_*.py が散在していないか)
   - 設定はどこにあるか (argparse 直書き / json / 別の yaml 構成)
   - リポジトリ外への依存 (`--xxx_root ../Foo` のような引数, `../`・`~/`・絶対パス, `sys.path` への外部ディレクトリ追加) → 規約 5 に従い,
     全体が要るなら `third_party/` の submodule, 一部だけなら `src/<pkg>/` へ抜き出して実装
   - CLI 引数の数 (必須引数, ハイパーパラメータの引数化) → 規約 6 に従い YAML と既定値へ移す
   - チェックポイント・結果の出力先, `.gitignore` の漏れ (巨大ファイルが track されていないか: `git ls-files | xargs du -ch 2>/dev/null | tail -1`)
2. 「現在のパス → 標準構成のパス」の対応表と, コード変更が必要な箇所 (import パス, ハードコードされた出力先, 削る CLI 引数と移す先) を
   ユーザーに提示し承認を得る. 大きく書き換わる場合は worktree / ブランチで作業する.
3. 移動は `git mv` で履歴を保つ. import (`from src.<pkg>...`) とパス文字列を更新する.
4. 不足ファイルだけ scaffold で補う (上書きしないので安全): `scaffold.py <dir> --pkg <pkg>`.
   既存の `.gitignore` / `README.md` / `pyproject.toml` は上書きされないので, テンプレートとの差分を見て手で統合する.
5. 既存の実験コマンドが同じ結果パスへ出力されることを, 1 epoch 程度の実行で確認する.

## テンプレート

`templates/` 以下. `__pkg__` / `{{pkg}}` / `{{project}}` / `{{python}}` が置換される.
テンプレートの Lightning / hydra / wandb は参照実装と同じスタック. 研究内容に合わないもの
(例: RL で Lightning を使わない) は置き換えてよいが, 規約 1–9 は守る.
