#!/usr/bin/env python3
"""
One-time export of grammarly/coedit-large to an fp16 ONNX zip for Sidekit's
on-device CoEdIT Polish feature. The app downloads this zip once on first run
(see CE-3); end users never run this script.

Pipeline:
  1. optimum-cli export onnx  -> encoder + merged decoder ONNX (fp32, with KV cache)
  2. convert fp32 -> fp16     -> compute in fp16, I/O kept fp32 (keep_io_types)
  3. smoke test               -> run encoder + a cached decode step in onnxruntime
  4. zip the files the C# adapter loads (encoder + merged decoder + config)
  5. print + record SHA256 and byte size (paste into the app's model catalog)

Why not int8: int8 dynamic quantization breaks T5 cross-attention at runtime in
ONNX Runtime (DynamicQuantizeMatMul "cannot broadcast on dim 0"). We fp16 the
encoder (robust, ~half size) but keep the merged decoder fp32, because fp16
conversion of its `If` subgraph yields an invalid model. Net ~2.4 GB, quality
~= fp32. A full-fp16 decoder is a later size optimization.

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
ARCHIVE_NAME = "coedit-large-fp16.zip"
METADATA_NAME = "coedit-large-fp16.metadata.txt"

ENCODER = "encoder_model.onnx"
DECODER = "decoder_model_merged.onnx"
EXTRA = ["config.json", "generation_config.json"]

# CoEdIT / Flan-T5-large architecture (from config.json), for the smoke test.
N_LAYERS, N_HEADS, D_KV = 24, 16, 64
VOCAB = 32100


def run(cmd: list[str]) -> None:
    print("    $", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def export_fp32(work: Path) -> Path:
    out = work / "coedit-large-onnx"
    print(f"[1/5] Export {MODEL_ID} -> ONNX (text2text, with KV cache + merged decoder)")
    run([
        "optimum-cli", "export", "onnx",
        "--model", MODEL_ID,
        "--task", "text2text-generation-with-past",
        str(out),
    ])
    return out


def convert_fp16(fp32: Path, work: Path) -> Path:
    import onnx
    # ONNX Runtime ships its own fp16 converter (same algorithm as
    # onnxconverter-common) with no extra dependency / protobuf-version conflict.
    from onnxruntime.transformers.float16 import convert_float_to_float16

    out = work / "coedit-large-onnx-fp16"
    out.mkdir(parents=True, exist_ok=True)
    # fp16 the ENCODER only (saves ~600 MB, converts cleanly). The merged decoder
    # has an `If` subgraph that the fp16 converter turns into an invalid model
    # ("subgraph output is an outer scope value"), so keep it fp32. Net ~2.4 GB;
    # both halves are validated by the smoke test below. A full-fp16 decoder is a
    # later size optimization (needs graph surgery on the If subgraph).
    print("[2/5] Convert encoder -> fp16 (keep_io_types); keep merged decoder fp32")
    enc = onnx.load(str(fp32 / ENCODER))  # external data auto-loaded from same dir
    enc16 = convert_float_to_float16(enc, keep_io_types=True, disable_shape_infer=True)
    onnx.save(enc16, str(out / ENCODER))

    # Copy the fp32 decoder verbatim (incl. any external-data sidecar files).
    for f in fp32.glob("decoder_model_merged.onnx*"):
        shutil.copy(f, out / f.name)

    for extra in EXTRA:
        p = fp32 / extra
        if p.exists():
            shutil.copy(p, out / extra)
    return out


def smoke_test(model_dir: Path) -> None:
    """Run the encoder + first + cached decode step, exactly as the C# adapter will.
    Fails loudly (non-zero exit) if the model can't actually run inference."""
    import numpy as np
    import onnxruntime as ort

    print("[3/5] Smoke test: encoder + 2 decode steps in onnxruntime")
    enc = ort.InferenceSession(str(model_dir / ENCODER))
    dec = ort.InferenceSession(str(model_dir / DECODER))
    out_names = [o.name for o in dec.get_outputs()]

    ids = np.array([[14269, 8, 19519, 10, 3, 1]], dtype=np.int64)  # "Fix the grammar:" + eos
    attn = np.ones_like(ids)
    enc_hidden = enc.run(None, {"input_ids": ids, "attention_mask": attn})[0]

    decoded, cache, first = [0], None, True
    for _ in range(2):
        dec_in = np.array([[decoded[-1]]], dtype=np.int64)
        feeds = {
            "encoder_attention_mask": attn,
            "input_ids": dec_in,
            "encoder_hidden_states": enc_hidden,
            "use_cache_branch": np.array([not first]),
        }
        empty = np.zeros((1, N_HEADS, 0, D_KV), dtype=np.float32)
        for i in range(N_LAYERS):
            for kind in ("decoder", "encoder"):
                feeds[f"past_key_values.{i}.{kind}.key"] = empty if first else cache[f"present.{i}.{kind}.key"]
                feeds[f"past_key_values.{i}.{kind}.value"] = empty if first else cache[f"present.{i}.{kind}.value"]
        res = dict(zip(out_names, dec.run(None, feeds)))
        assert res["logits"].shape[-1] == VOCAB, f"bad logits shape {res['logits'].shape}"
        decoded.append(int(np.argmax(res["logits"][0, -1])))
        cache, first = res, False
    print(f"    OK - inference runs; first sampled tokens: {decoded[1:]}")


def collect(src: Path) -> list[Path]:
    files: list[Path] = []
    for name in [ENCODER, DECODER]:
        p = src / name
        if not p.exists():
            sys.exit(f"ERROR: missing {name} in {src}; have: {sorted(q.name for q in src.glob('*.onnx'))}")
        files.append(p)
    for name in EXTRA:
        p = src / name
        if p.exists():
            files.append(p)
    return files


def package(files: list[Path], out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / ARCHIVE_NAME
    print(f"[4/5] Package -> {archive}")
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
    ap = argparse.ArgumentParser(description="Export grammarly/coedit-large to an fp16 ONNX zip.")
    ap.add_argument("--out", default=Path("dist"), type=Path, help="output directory (default: dist)")
    ap.add_argument("--work", default=None, type=Path, help="scratch dir (default: <out>/work)")
    ap.add_argument("--keep-work", action="store_true", help="keep intermediate ONNX dirs")
    args = ap.parse_args()

    out_dir: Path = args.out
    work: Path = args.work or (out_dir / "work")
    work.mkdir(parents=True, exist_ok=True)

    fp32 = export_fp32(work)
    fp16 = convert_fp16(fp32, work)
    smoke_test(fp16)
    files = collect(fp16)
    archive = package(files, out_dir)
    digest, size = fingerprint(archive)

    print("[5/5] Done")
    print(f"    archive : {archive}")
    print(f"    size    : {size:,} bytes ({size / 1e6:.1f} MB)")
    print(f"    sha256  : {digest}")

    (out_dir / METADATA_NAME).write_text(
        f"name=coedit-large-fp16\n"
        f"file={ARCHIVE_NAME}\n"
        f"size={size}\n"
        f"sha256={digest}\n"
    )

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as s:
            s.write(
                "## CoEdIT model export (fp16)\n\n"
                f"- **file**: `{ARCHIVE_NAME}`\n"
                f"- **size**: {size:,} bytes ({size / 1e6:.1f} MB)\n"
                f"- **sha256**: `{digest}`\n\n"
                "Smoke test passed (model runs). Paste `size` + `sha256` into the catalog (CE-3).\n"
            )

    if not args.keep_work:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
