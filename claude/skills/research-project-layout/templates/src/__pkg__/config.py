from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional, Tuple

from omegaconf import ListConfig

# 設定はすべてここの dataclass で型付けし, models/cfg/<model>.yaml の `_target_` から
# hydra.utils.instantiate で生成する. omegaconf がフィールド型を評価するので,
# 古い Python を使う場合は `tuple[int]` ではなく `Tuple[int, ...]` / `Optional[...]` を使う.


@dataclass
class DatasetConfig:
    path: str
    batch_size: int
    seed: int
    num_workers: int = 0


@dataclass
class ModelConfig:
    input_dim: int
    output_dim: int
    hidden_dim: int = 128
    n_layers: int = 2
    lr: float = 1e-3


@dataclass
class TrainerConfig:
    """pl.Trainer にそのまま渡すキーだけを持つ."""

    accelerator: str
    devices: Tuple[int, ...]
    deterministic: bool
    precision: int
    log_every_n_steps: int
    check_val_every_n_epoch: int
    gradient_clip_val: Optional[float] = None
    gradient_clip_algorithm: Optional[Literal["norm", "value"]] = None

    def __post_init__(self):
        if isinstance(self.devices, (list, ListConfig)):
            self.devices = tuple(self.devices)


@dataclass
class ExperimentConfig:
    epochs: int
    data_dir: str
    seed: int
    device: int
    input_dim: int
    output_dim: int
    datamodule: DatasetConfig
    model: ModelConfig
    trainer: TrainerConfig
    monitor_key: str = "loss"
    early_stop: int = 0
