from __future__ import annotations

import json
import os

import torch

from .dataset import DatasetModule
from .model import Model


@torch.no_grad()
def evaluate(model: Model, datamodule: DatasetModule, report_dir: str) -> dict:
    """評価して reports/<data_dir>/<model>/seed:<seed>/metrics.json に書き出す."""
    os.makedirs(report_dir, exist_ok=True)
    datamodule.setup("validate")
    model.eval()
    total, n = 0.0, 0
    for x, y in datamodule.val_dataloader():
        x, y = x.to(model.device), y.to(model.device)
        total += torch.nn.functional.mse_loss(model(x), y, reduction="sum").item()
        n += y.numel()
    metrics = {"val_mse": total / n}
    with open(os.path.join(report_dir, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    return metrics
