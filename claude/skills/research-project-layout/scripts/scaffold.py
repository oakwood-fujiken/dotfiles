#!/usr/bin/env python3
"""研究プロジェクト標準構成の scaffold / 監査.

    python scaffold.py <target_dir> --pkg <pkg> [--project NAME] [--python 3.11] [--dry-run]
    python scaffold.py <target_dir> --pkg <pkg> --check

作成モードは既存ファイルを決して上書きしない (不足分だけ作る).
--check は何も書かず, 標準構成との差分を報告する.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

TEMPLATES = Path(__file__).resolve().parent.parent / "templates"

# 必須ディレクトリ (空でも作る)
DIRS = ["src/{pkg}", "models/cfg", "models/params", "data", "reports", "scripts", "outputs", "wandb"]

# commit されるべきでないパターン (--check 用)
UNTRACKED_PATTERNS = [
    (r"^models/params/", "チェックポイント"),
    (r"\.(ckpt|pt|pth)$", "チェックポイント"),
    (r"\.(npz|npy|hdf5|h5|blosc2)$", "実データ"),
    (r"^(outputs|wandb)/", "実験出力"),
    (r"^reports/", "評価結果"),
]


def render(text: str, ctx: dict) -> str:
    for k, v in ctx.items():
        text = text.replace("{{" + k + "}}", v)
    return text


def scaffold(root: Path, ctx: dict, dry_run: bool) -> None:
    created, skipped = [], []
    for d in DIRS:
        p = root / d.format(pkg=ctx["pkg"])
        if not p.exists():
            created.append(f"{p.relative_to(root)}/")
            if not dry_run:
                p.mkdir(parents=True, exist_ok=True)
    for src in sorted(TEMPLATES.rglob("*")):
        if src.is_dir():
            continue
        rel = Path(str(src.relative_to(TEMPLATES)).replace("__pkg__", ctx["pkg"]))
        dst = root / rel
        if dst.exists():
            skipped.append(str(rel))
            continue
        created.append(str(rel))
        if not dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(render(src.read_text(), ctx))
    head = "[dry-run] 作成予定" if dry_run else "作成"
    print(f"{head} ({len(created)}):")
    for c in created:
        print(f"  + {c}")
    if skipped:
        print(f"既存のためスキップ ({len(skipped)}) — テンプレートとの差分は手で統合:")
        for s in skipped:
            print(f"  = {s}")
        print(f"  (テンプレート: {TEMPLATES})")


def check(root: Path, pkg: str) -> int:
    issues: list[str] = []
    notes: list[str] = []

    for f in ["pyproject.toml", "uv.lock", ".python-version", ".gitignore", "README.md", "main.py"]:
        if not (root / f).exists():
            issues.append(f"不足: {f}")
    for f in ["__init__.py", "config.py"]:
        if not (root / "src" / pkg / f).exists():
            issues.append(f"不足: src/{pkg}/{f}")
    for d in ["models/cfg", "data", "scripts"]:
        if not (root / d).is_dir():
            issues.append(f"不足: {d}/")

    # models/cfg の YAML は _target_ を持つべき
    cfg_dir = root / "models/cfg"
    if cfg_dir.is_dir():
        yamls = sorted(cfg_dir.glob("*.yaml"))
        if not yamls:
            issues.append("models/cfg/ に <model>.yaml が無い")
        for y in yamls:
            if "_target_" not in y.read_text():
                notes.append(f"models/cfg/{y.name}: `_target_` が無い (hydra instantiate 前提)")

    # data/<name>/config.yaml
    data_dir = root / "data"
    if data_dir.is_dir():
        for d in sorted(p for p in data_dir.iterdir() if p.is_dir()):
            if not (d / "config.yaml").exists():
                issues.append(f"data/{d.name}/config.yaml が無い")

    # トップレベルに散らばった実行スクリプト
    stray = [p.name for p in root.glob("*.py") if p.name != "main.py"]
    if stray:
        notes.append(f"ルート直下の main.py 以外の .py: {', '.join(sorted(stray))} → src/{pkg}/ か scripts/ へ")

    # 他のトップレベル Python パッケージ
    for p in root.iterdir():
        if p.is_dir() and (p / "__init__.py").exists() and p.name not in ("src",):
            notes.append(f"トップレベルのパッケージ {p.name}/ → src/{pkg}/ 配下へ")

    # main.py が標準の CLI / 出力パスを使っているか
    main = root / "main.py"
    if main.exists():
        text = main.read_text()
        for flag in ["--model", "--data_dir", "--seed"]:
            if flag not in text:
                notes.append(f"main.py に {flag} 引数が無い")
        for pat in ["models/cfg/", "models/params/"]:
            if pat not in text:
                notes.append(f"main.py が {pat} を参照していない")
        if f"src.{pkg}" not in text:
            notes.append(f"main.py が `src.{pkg}` から import していない")

    # .gitignore
    gi = root / ".gitignore"
    if gi.exists():
        text = gi.read_text()
        for pat in ["reports", "outputs", "wandb", ".venv", "ckpt"]:
            if pat not in text:
                issues.append(f".gitignore に {pat} が無い")

    # track されているべきでないファイル
    try:
        tracked = subprocess.run(["git", "-C", str(root), "ls-files"], capture_output=True,
                                 text=True, check=True).stdout.splitlines()
    except (subprocess.CalledProcessError, FileNotFoundError):
        tracked = None
        notes.append("git リポジトリではない (git init を推奨)")
    if tracked is not None:
        bad: dict[str, list[str]] = {}
        for f in tracked:
            for pat, label in UNTRACKED_PATTERNS:
                if re.search(pat, f):
                    bad.setdefault(label, []).append(f)
                    break
        for label, files in bad.items():
            shown = ", ".join(files[:5]) + (f" 他 {len(files) - 5} 件" if len(files) > 5 else "")
            notes.append(f"git 管理下の{label} ({len(files)} 件): {shown}")

    print(f"== 標準構成チェック: {root} (pkg={pkg}) ==")
    for i in issues:
        print(f"  ✗ {i}")
    for n in notes:
        print(f"  ! {n}")
    if not issues and not notes:
        print("  ✓ 標準構成に沿っています")
    return 1 if issues else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("target", type=Path)
    ap.add_argument("--pkg", help="src/<pkg> のパッケージ名 (既定: target のディレクトリ名)")
    ap.add_argument("--project", help="プロジェクト名 (既定: target のディレクトリ名)")
    ap.add_argument("--python", default="3.11", help=".python-version / requires-python")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true", help="書き込まずに標準構成との差分を報告")
    args = ap.parse_args()

    root = args.target.resolve()
    project = args.project or root.name
    pkg = args.pkg or re.sub(r"\W", "_", root.name)
    if not pkg.isidentifier():
        sys.exit(f"--pkg {pkg!r} は Python の識別子ではありません")

    if args.check:
        return check(root, pkg)
    if not args.dry_run:
        root.mkdir(parents=True, exist_ok=True)
    ctx = {"project": project, "project_lower": project.lower(), "pkg": pkg, "python": args.python}
    scaffold(root, ctx, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
