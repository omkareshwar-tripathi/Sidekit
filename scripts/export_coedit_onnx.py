#!/usr/bin/env python3
"""
One-time export of grammarly/coedit-large to an int8 ONNX zip for SpeakType's
on-device CoEdIT Polish feature. The app downloads this zip once on first run
(see CE-3); end users never run this script.

Pipeline:
  1. optimum-cli export onnx  -> encoder + (merged) decoder ONNX, fp32, with KV cache
  2. optimum-cli quantize     -> dynamic int8 (no calibration data needed)
  3. zip the files the C# adapter needs (encoder + merged decoder + config)
  4. print + record SHA256 and byte size (paste into the app's model catalog)

Usage (Python 3.10-3.12 with torch; or via the export-coedit-model GH Actions workflow):
    pip install -r scripts/requirements-export.txt
    python scripts/export_coedit_onnx.py --out dist
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

MODEL_ID = "grammarly/coedit-large"
ARCHIVE_NAME = "coedit-large-int8.zip"

# Files the SpeakType.Onnx adapter loads. Decoder: prefer the merged graph
# (one file handles the first pass and the cached steps); fall back to the split pair.
ENCODER = "encoder_model.onnx"
DECODER_MERGED = "decoder_model_merged.onnx"
DECODER_SPLIT = ["decoder_model.onnx", "decoder_with_past_model.onnx"]
EXTRA = ["config.json", "generation_config.json"]


def run(cmd: list[str]) -> None:
    print("    $", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def export_fp32(work: Path) -> Path:
    out = work / "coedit-large-onnx"
    print(f"[1/4] Export {MODEL_ID} -> ONNX (text2text, with KV cache + merged decoder)")
    run([
        "optimum-cli", "export", "onnx",
        "--model", MODEL_ID,
        "--task", "text2text-generation-with-past",
        str(out),
    ])
    return out


def quantize_int8(fp32: Path, work: Path) -> Path:
    out = work / "coedit-large-onnx-int8"
    # Dynamic int8: weight-only-style quantization, no calibration dataset.
    # --avx2 picks a config that runs on essentially any modern x64 CPU.
    print("[2/4] Dynamic int8 quantization")
    run([
        "optimum-cli", "onnxruntime", "quantize",
        "--onnx_model", str(fp32),
        "--avx2",
        "-o", str(out),
    ])
    return out


def collect(src: Path) -> list[Path]:
    files: list[Path] = []

    enc = src / ENCODER
    if not enc.exists():
        sys.exit(f"ERROR: missing {ENCODER} in {src}")
    files.append(enc)

    if (src / DECODER_MERGED).exists():
        files.append(src / DECODER_MERGED)
    else:
        print(f"    note: {DECODER_MERGED} not produced; packaging the split decoder")
        for name in DECODER_SPLIT:
            p = src / name
            if not p.exists():
                sys.exit(f"ERROR: missing decoder file {name} in {src}")
            files.append(p)

    for name in EXTRA:
        p = src / name
        if p.exists():
            files.append(p)

    return files


def package(files: list[Path], out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / ARCHIVE_NAME
    print(f"[3/4] Package -> {archive}")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for f in files:
            print(f"    + {f.name} ({f.stat().st_size:,} bytes)")
            z.write(f, arcname=f.name)
    return archive


def fingerprint(archive: Path) -> tuple[str, int]:
    h = hashlib.sha256()
    with archive.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest(), archive.stat().st_size


def main() -> None:
    ap = argparse.ArgumentParser(description="Export grammarly/coedit-large to an int8 ONNX zip.")
    ap.add_argument("--out", default=Path("dist"), type=Path, help="output directory (default: dist)")
    ap.add_argument("--work", default=None, type=Path, help="scratch dir (default: <out>/work)")
    ap.add_argument("--keep-work", action="store_true", help="keep intermediate ONNX dirs")
    args = ap.parse_args()

    out_dir: Path = args.out
    work: Path = args.work or (out_dir / "work")
    work.mkdir(parents=True, exist_ok=True)

    fp32 = export_fp32(work)
    int8 = quantize_int8(fp32, work)
    files = collect(int8)
    archive = package(files, out_dir)
    digest, size = fingerprint(archive)

    print("[4/4] Done")
    print(f"    archive : {archive}")
    print(f"    size    : {size:,} bytes ({size / 1e6:.1f} MB)")
    print(f"    sha256  : {digest}")

    # Machine-readable sidecar for CE-3's model catalog.
    (out_dir / "coedit-large-int8.metadata.txt").write_text(
        f"name=coedit-large-int8\n"
        f"file={ARCHIVE_NAME}\n"
        f"size={size}\n"
        f"sha256={digest}\n"
    )

    # Surface the fingerprint in the GitHub Actions run summary, if present.
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as s:
            s.write(
                "## CoEdIT model export\n\n"
                f"- **file**: `{ARCHIVE_NAME}`\n"
                f"- **size**: {size:,} bytes ({size / 1e6:.1f} MB)\n"
                f"- **sha256**: `{digest}`\n\n"
                "Paste `size` + `sha256` into the app's model catalog (CE-3).\n"
            )

    if not args.keep_work:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
