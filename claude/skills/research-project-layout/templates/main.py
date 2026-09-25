import argparse
import os
from dataclasses import asdict

import pytorch_lightning as pl
import torch
from hydra.utils import instantiate
from omegaconf import OmegaConf
from pytorch_lightning.callbacks import EarlyStopping, ModelCheckpoint
from pytorch_lightning.loggers import WandbLogger

from src.{{pkg}}.config import ExperimentConfig
from src.{{pkg}}.dataset import DatasetModule
from src.{{pkg}}.eval import evaluate
from src.{{pkg}}.model import Model

WANDB_PROJECT = "{{project}}"

# data/<data_dir>/config.yaml から models/cfg/<model>.yaml へ注入するキー
DATA_KEYS = ("input_dim", "output_dim")


def param_dir(data_dir: str, model_name: str, seed: int) -> str:
    return f"models/params/{data_dir}/{model_name}/seed:{seed}/"


def report_dir(data_dir: str, model_name: str, seed: int) -> str:
    return f"reports/{data_dir}/{model_name}/seed:{seed}/"


def load_config(model_name: str, data_dir: str, seed: int, device: int, epochs: int) -> ExperimentConfig:
    config = OmegaConf.load(f"models/cfg/{model_name}.yaml")
    config.seed = seed
    config.epochs = epochs
    config.device = device
    config.data_dir = data_dir

    data_cfg = OmegaConf.load(f"data/{data_dir}/config.yaml")
    for key in DATA_KEYS:
        config[key] = data_cfg[key]

    OmegaConf.resolve(config)
    return instantiate(config)


def train(model_name: str, config: ExperimentConfig):
    pl.seed_everything(config.seed)
    path = param_dir(config.data_dir, model_name, config.seed)
    os.makedirs(path, exist_ok=True)
    os.makedirs("wandb", exist_ok=True)

    logger = WandbLogger(
        name=f"{config.data_dir}_{model_name}_seed={config.seed}",
        project=WANDB_PROJECT,
        save_dir="./wandb/",
        config=asdict(config),
        tags=[f"seed_{config.seed}", config.data_dir, model_name],
    )
    monitor = f"loss/{config.monitor_key}/val"
    callbacks = [
        ModelCheckpoint(dirpath=path, filename="model", monitor=monitor,
                        save_on_train_epoch_end=False, save_last=True),
    ]
    if config.early_stop > 0:
        callbacks.append(EarlyStopping(monitor=monitor, patience=config.early_stop, mode="min"))

    trainer_kwargs = asdict(config.trainer)
    if torch.cuda.is_available():
        trainer_kwargs["devices"] = [config.device]
    else:
        trainer_kwargs.update(accelerator="cpu", devices=1)
    trainer = pl.Trainer(logger=logger, callbacks=callbacks, max_epochs=config.epochs, **trainer_kwargs)
    trainer.fit(model=Model(config.model), datamodule=DatasetModule(config.datamodule))


def run_evaluate(model_name: str, config: ExperimentConfig, load_last: bool):
    ckpt = os.path.join(param_dir(config.data_dir, model_name, config.seed),
                        "last.ckpt" if load_last else "model.ckpt")
    device = torch.device(f"cuda:{config.device}" if torch.cuda.is_available() else "cpu")
    model = Model.load_from_checkpoint(ckpt, cfg=config.model, map_location=device)
    metrics = evaluate(model, DatasetModule(config.datamodule),
                       report_dir(config.data_dir, model_name, config.seed))
    print(metrics)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog="main.py")
    parser.add_argument("--model", type=str, default="default", help="models/cfg/<model>.yaml")
    parser.add_argument("--data_dir", type=str, default="example", help="data/<data_dir>/config.yaml")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--epochs", type=int, default=1000)
    parser.add_argument("--train", "-tr", action="store_true", help="train model")
    parser.add_argument("--evaluate", "-e", action="store_true", help="evaluate model")
    parser.add_argument("--load_last", "-l", action="store_true", help="use last.ckpt instead of model.ckpt")
    args = parser.parse_args()

    config = load_config(args.model, args.data_dir, args.seed, args.device, args.epochs)
    if args.train:
        train(args.model, config)
    if args.evaluate:
        run_evaluate(args.model, config, args.load_last)
