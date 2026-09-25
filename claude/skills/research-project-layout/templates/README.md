# {{project}}

(研究の一行要約)

## セットアップ

```bash
uv sync
```

(uv sync 以外に必要な手作業があればここに書く)

### バージョン pin について

(pyproject.toml で pin/緩和した依存とその理由)

## ディレクトリ構成

| パス | 内容 | git |
|---|---|---|
| `main.py` | 実験エントリ (`--model --data_dir --seed --train/--evaluate`) | ✓ |
| `src/{{pkg}}/` | 本体 (config / dataset / model / eval) | ✓ |
| `models/cfg/<model>.yaml` | 実験設定 (hydra `_target_`) | ✓ |
| `data/<data_dir>/config.yaml` | データのメタ情報 | ✓ |
| `models/params/<data_dir>/<model>/seed:<seed>/` | チェックポイント | ✗ |
| `reports/<data_dir>/<model>/seed:<seed>/` | 評価結果 | ✗ |
| `scripts/` | 補助スクリプト | ✓ |

## 学習

```bash
uv run python main.py --model default --data_dir example --seed 0 --device 0 --epochs 100 --train
```

チェックポイントは `models/params/<data_dir>/<model>/seed:<seed>/{model.ckpt,last.ckpt}` に保存される.

## 評価

```bash
uv run python main.py --model default --data_dir example --seed 0 --evaluate
```

結果は `reports/<data_dir>/<model>/seed:<seed>/metrics.json`.

## 手法

(手法の説明, 主要な設定キーと意味, 比較条件の注意)
