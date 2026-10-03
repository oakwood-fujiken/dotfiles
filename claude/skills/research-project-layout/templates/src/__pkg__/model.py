from __future__ import annotations

import pytorch_lightning as pl
import torch
from torch import nn

from .config import ModelConfig


class Model(pl.LightningModule):
    """TODO: 研究対象のモデルに置き換える.

    ログのキー:
      - `loss/<key>/{train,val}`: 実際に backprop している値 (合計損失とその各項).
        main.py の ModelCheckpoint / EarlyStopping が `loss/<monitor_key>/val` を監視する.
      - `metrics/<key>/{train,val}`: backprop しない観察用の値.
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.cfg = cfg
        layers, d = [], cfg.input_dim
        for _ in range(cfg.n_layers):
            layers += [nn.Linear(d, cfg.hidden_dim), nn.Mish()]
            d = cfg.hidden_dim
        layers.append(nn.Linear(d, cfg.output_dim))
        self.net = nn.Sequential(*layers)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)

    def _step(self, batch, split: str) -> torch.Tensor:
        x, y = batch
        pred = self(x)
        loss = nn.functional.mse_loss(pred, y)
        self.log(f"loss/loss/{split}", loss, prog_bar=True, on_epoch=True, on_step=False)
        with torch.no_grad():
            mae = (pred - y).abs().mean()
        self.log(f"metrics/mae/{split}", mae, on_epoch=True, on_step=False)
        return loss

    def training_step(self, batch, batch_idx):
        return self._step(batch, "train")

    def validation_step(self, batch, batch_idx):
        return self._step(batch, "val")

    def configure_optimizers(self):
        return torch.optim.Adam(self.parameters(), lr=self.cfg.lr)
