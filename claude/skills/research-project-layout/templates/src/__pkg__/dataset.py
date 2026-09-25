from __future__ import annotations

import pytorch_lightning as pl
import torch
from omegaconf import OmegaConf
from torch.utils.data import DataLoader, TensorDataset

from .config import DatasetConfig


class DatasetModule(pl.LightningDataModule):
    """data/<path>/ を読む DataModule.

    TODO: テンプレートは data/<path>/config.yaml の次元からランダムな回帰データを作るだけ.
    実データ (data/<path>/training/*.npz など) の読み込みに置き換える.
    """

    def __init__(self, cfg: DatasetConfig):
        super().__init__()
        self.cfg = cfg
        self.data_cfg = OmegaConf.load(f"data/{cfg.path}/config.yaml")

    def setup(self, stage: str | None = None):
        g = torch.Generator().manual_seed(self.cfg.seed)
        d_in, d_out = int(self.data_cfg.input_dim), int(self.data_cfg.output_dim)
        w = torch.randn(d_in, d_out, generator=g)

        def make(n: int) -> TensorDataset:
            x = torch.randn(n, d_in, generator=g)
            return TensorDataset(x, x @ w + 0.1 * torch.randn(n, d_out, generator=g))

        self.train_set = make(int(self.data_cfg.n_train))
        self.val_set = make(int(self.data_cfg.n_val))

    def train_dataloader(self):
        return DataLoader(self.train_set, batch_size=self.cfg.batch_size, shuffle=True,
                          num_workers=self.cfg.num_workers)

    def val_dataloader(self):
        return DataLoader(self.val_set, batch_size=self.cfg.batch_size,
                          num_workers=self.cfg.num_workers)
