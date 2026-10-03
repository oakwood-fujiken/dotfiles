# {{project}}

(研究の一行要約)

## セットアップ

```bash
uv sync
```

(uv sync 以外に必要な手作業があればここに書く. `third_party/` に submodule があれば
`git submodule update --init --recursive`. 外部のデータ・重みは `data/`, `models/params/` に置き,
リポジトリ外のディレクトリは前提にしない. 外部リポジトリから抜き出して実装した部分は出典と commit をここに書く)

### バージョン pin について

(pyproject.toml で pin/緩和した依存とその理由)

## ディレクトリ構成

| パス | 内容 | git |
|---|---|---|
| `main.py` | 実験エントリ (`--train` / `--evaluate`. 他の引数はすべて既定値あり) | ✓ |
| `src/{{pkg}}/` | 本体 (config / dataset / model / eval) | ✓ |
| `third_party/<name>/` | 別リポジトリのプロジェクト全体 (あれば. git submodule) | ✓ |
| `models/cfg/<model>.yaml` | 実験設定 (hydra `_target_`) | ✓ |
| `data/<data_dir>/config.yaml` | データのメタ情報 | ✓ |
| `models/params/<data_dir>/<model>/seed:<seed>/` | チェックポイント | ✗ |
| `reports/<data_dir>/<model>/seed:<seed>/` | 評価結果 | ✗ |
| `scripts/` | 補助スクリプト | ✓ |

## 学習

```bash
uv run python main.py --train
```

既定値は `--model default --data_dir example --seed 0 --device 0`. 変えるものだけ指定する
(例: `uv run python main.py --seed 1 --train`). epochs や batch_size などのハイパーパラメータは
`models/cfg/<model>.yaml` に書く. 条件を変えるときは YAML を増やして `--model` で選ぶ.

チェックポイントは `models/params/<data_dir>/<model>/seed:<seed>/{model.ckpt,last.ckpt}` に保存される.

wandb には, backprop している値を `loss/<key>/{train,val}`, 観察用の値を `metrics/<key>/{train,val}` としてログする.

## 評価

```bash
uv run python main.py --evaluate
```

結果は `reports/<data_dir>/<model>/seed:<seed>/metrics.json`.

## 手法

(手法の説明, 主要な設定キーと意味, 比較条件の注意)
