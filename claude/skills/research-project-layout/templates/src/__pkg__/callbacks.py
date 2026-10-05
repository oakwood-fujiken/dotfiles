from __future__ import annotations

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pytorch_lightning as pl
import torch
import wandb
from pytorch_lightning.callbacks import RichProgressBar
from pytorch_lightning.callbacks.progress.rich_progress import RichProgressBarTheme
from pytorch_lightning.loggers import WandbLogger

from .config import VisualizeConfig


class ProgressBarCallback(RichProgressBar):
    """学習の進捗表示. main.py の Trainer に既定で渡す (参照実装 minMTRSSM と同じテーマ).

    References
    ----------
    * https://qiita.com/akihironitta/items/edfd6b29dfb67b17fb00
    """

    def __init__(self) -> None:
        theme = RichProgressBarTheme(
            description="green_yellow",
            progress_bar="green1",
            progress_bar_finished="green1",
            batch_progress="green_yellow",
            time="grey82",
            processing_speed="grey82",
            metrics="grey82",
        )
        super().__init__(theme=theme)


TARGET_KEY = "prediction/target"


class VisualizePrediction(pl.Callback):
    """生成・再構成したデータを reference/target と並べて wandb にログする.

    LightningModule の `validation_step` が次のキーを持つ dict を返すと, `every_n_epoch` ごとに
    val の最初の batch から `num_samples` 個をログする (キーが無ければ何もしない).
      - `prediction/target`: 正解 (reference/target) データ
      - `prediction/<name>`: 生成・再構成したデータ (複数可. target と同じ shape)
    shape で可視化を切り替える (画像は [0, 1]):
      - (B, T, C, H, W): 時系列画像. 各 step で [target | <name> ...] を横に並べ, 1 step = 1 frame の mp4 動画
      - (B, C, H, W): 画像. [target | <name> ...] を横に並べた画像
      - (B, T, D) / (B, D): ベクトル. target と <name> を同じ軸範囲で重ねた折れ線
    """

    def __init__(self, cfg: VisualizeConfig) -> None:
        super().__init__()
        self.cfg = cfg

    def on_validation_batch_end(self, trainer: pl.Trainer, pl_module: pl.LightningModule, outputs,
                                batch, batch_idx: int, dataloader_idx: int = 0) -> None:
        if (batch_idx != 0 or trainer.sanity_checking or not isinstance(trainer.logger, WandbLogger)
                or trainer.current_epoch % self.cfg.every_n_epoch != 0):
            return
        if not isinstance(outputs, dict) or TARGET_KEY not in outputs:
            return
        n = self.cfg.num_samples
        target = outputs[TARGET_KEY][:n].detach().float().cpu()
        preds = {k.removeprefix("prediction/"): v[:n].detach().float().cpu()
                 for k, v in outputs.items() if k.startswith("prediction/") and k != TARGET_KEY}
        if not preds:
            return

        if target.ndim == 5:
            frames = _tile([target, *preds.values()])  # (n, T, C, H, W*k)
            media = {"prediction/video": [wandb.Video(v, fps=self.cfg.fps, format="mp4") for v in frames]}
        elif target.ndim == 4:
            media = {"prediction/image": [wandb.Image(v.transpose(1, 2, 0)) for v in _tile([target, *preds.values()])]}
        else:
            fig = _plot_vectors(target, preds)
            media = {"prediction/plot": wandb.Image(fig)}
            plt.close(fig)
        media["caption"] = " | ".join(["target", *preds])
        trainer.logger.experiment.log({**media, "trainer/global_step": trainer.global_step})


def _tile(xs: list[torch.Tensor], sep: int = 2) -> np.ndarray:
    """[0, 1] の画像を幅方向に白線を挟んで並べ, uint8 にする."""
    white = torch.ones(*xs[0].shape[:-1], sep)
    parts = [p for x in xs for p in (x.clamp(0, 1), white)][:-1]
    return (torch.cat(parts, dim=-1) * 255).round().to(torch.uint8).numpy()


def _plot_vectors(target: torch.Tensor, preds: dict[str, torch.Tensor], max_dims: int = 4) -> plt.Figure:
    """target と予測を同じ軸範囲 (sharex/sharey) で重ねて描く. (B, D) は x=次元, (B, T, D) は x=step."""
    if target.ndim == 2:
        target, preds = target[:, None], {k: v[:, None] for k, v in preds.items()}  # (B, 1, D): 1 パネル
    n, n_panel = target.shape[0], 1 if target.shape[1] == 1 else min(target.shape[-1], max_dims)
    fig, axes = plt.subplots(n, n_panel, figsize=(3 * n_panel, 2 * n), sharex=True, sharey=True, squeeze=False)
    for i in range(n):
        for j in range(n_panel):
            ax = axes[i, j]
            series = {"target": target, **preds}
            for name, x in series.items():
                y = x[i, 0] if target.shape[1] == 1 else x[i, :, j]
                ax.plot(y.numpy(), label=name, lw=1.5 if name == "target" else 1.0,
                        color="black" if name == "target" else None)
    axes[0, 0].legend(fontsize=7)
    fig.tight_layout()
    return fig
