#!/usr/bin/env python3
"""Compare MLX Privacy Filter model variants for Manifold evaluation.

Default behavior fetches remote Hugging Face metadata and config using only the
Python standard library. Optional flags can download model repos with
``huggingface_hub`` and inspect local safetensors metadata when
``safetensors`` is installed.

Examples:

  python3 script/test_privacy_filter_mlx.py
  python3 script/test_privacy_filter_mlx.py --download-dir /tmp/privacy-filter-mlx
  python3 script/test_privacy_filter_mlx.py \\
      --local-model bf16=/tmp/privacy-filter-mlx/bf16 \\
      --local-model mxfp8=/tmp/privacy-filter-mlx/mxfp8
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


MODEL_SPECS = {
    "bf16": {
        "repo_id": "mlx-community/openai-privacy-filter-bf16",
        "display_name": "BF16",
    },
    "mxfp8": {
        "repo_id": "mlx-community/openai-privacy-filter-mxfp8",
        "display_name": "MXFP8",
    },
}

REMOTE_REQUIRED_FILES = [
    ".gitattributes",
    "config.json",
    "model.safetensors",
    "model.safetensors.index.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "viterbi_calibration.json",
]

COMPATIBILITY_FIELDS = [
    "architectures",
    "model_type",
    "vocab_size",
    "hidden_size",
    "intermediate_size",
    "num_hidden_layers",
    "num_attention_heads",
    "num_key_value_heads",
    "num_local_experts",
    "num_experts_per_tok",
    "max_position_embeddings",
    "sliding_window",
    "default_n_ctx",
    "label2id",
    "id2label",
]

EXPECTED_SUITE = [
    {
        "id": "person_address_email",
        "text": "Alice Smith lives at 123 Main Street and uses alice@example.com",
        "expected_labels": ["private_person", "private_address", "private_email"],
    },
    {
        "id": "secret",
        "text": "Use API key sk-abcdefghijklmnopqrstuvwxyz123456 for this request",
        "expected_labels": ["secret"],
    },
    {
        "id": "phone_date",
        "text": "Call me at +44 20 7946 0958 on 2026-04-23.",
        "expected_labels": ["private_phone", "private_date"],
    },
    {
        "id": "account_number",
        "text": "Account number 1234-5678-9012 should never be shared.",
        "expected_labels": ["account_number"],
    },
    {
        "id": "benign_url_negative",
        "text": "The portal is https://intranet.example.com/login for all staff.",
        "expected_labels": [],
    },
]


@dataclass
class QuantizationInfo:
    mode: str | None
    bits: int | None
    group_size: int | None


@dataclass
class LocalInspection:
    path: str
    missing_files: list[str]
    model_file_size_bytes: int | None
    config_matches_remote: bool | None
    safetensors_tensor_count: int | None
    safetensors_first_keys: list[str]
    safetensors_error: str | None


@dataclass
class ModelReport:
    key: str
    display_name: str
    repo_id: str
    sha: str
    last_modified: str
    downloads: int
    used_storage_bytes: int
    remote_files: list[str]
    remote_required_files_present: bool
    architecture: list[str]
    model_type: str | None
    dtype: str | None
    quantization: QuantizationInfo
    config_subset: dict[str, Any]
    local: LocalInspection | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare BF16 and MXFP8 MLX Privacy Filter variants."
    )
    parser.add_argument(
        "--models",
        nargs="+",
        choices=sorted(MODEL_SPECS.keys()),
        default=["bf16", "mxfp8"],
        help="Model variants to compare.",
    )
    parser.add_argument(
        "--local-model",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="Inspect a local model checkout or snapshot for a given variant.",
    )
    parser.add_argument(
        "--download-dir",
        type=Path,
        help="Optional root directory for snapshot_download of the selected models.",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        help="Write the full report to a JSON file.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="HTTP timeout in seconds for remote metadata fetches.",
    )
    return parser.parse_args()


def fetch_json(url: str, timeout: float) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "manifold-privacy-filter-mlx-test/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def human_bytes(size: int) -> str:
    suffixes = ["B", "KB", "MB", "GB", "TB"]
    value = float(size)
    for suffix in suffixes:
        if value < 1024.0 or suffix == suffixes[-1]:
            return f"{value:.2f} {suffix}"
        value /= 1024.0
    return f"{size} B"


def parse_local_models(values: list[str]) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    for item in values:
        if "=" not in item:
            raise SystemExit(f"Invalid --local-model value: {item!r}. Expected NAME=PATH.")
        name, raw_path = item.split("=", 1)
        if name not in MODEL_SPECS:
            raise SystemExit(f"Unknown model name in --local-model: {name!r}.")
        mapping[name] = Path(raw_path).expanduser().resolve()
    return mapping


def maybe_download_models(selected: list[str], root: Path) -> dict[str, Path]:
    try:
        from huggingface_hub import snapshot_download
    except ImportError as exc:
        raise SystemExit(
            "--download-dir requires huggingface_hub. "
            "Install it with `python3 -m pip install huggingface_hub`."
        ) from exc

    root.mkdir(parents=True, exist_ok=True)
    downloaded: dict[str, Path] = {}
    for key in selected:
        repo_id = MODEL_SPECS[key]["repo_id"]
        target = root / key
        target.mkdir(parents=True, exist_ok=True)
        snapshot_download(
            repo_id=repo_id,
            local_dir=str(target),
            allow_patterns=REMOTE_REQUIRED_FILES,
        )
        downloaded[key] = target
    return downloaded


def inspect_local_model(path: Path, remote_config: dict[str, Any]) -> LocalInspection:
    missing_files = [name for name in REMOTE_REQUIRED_FILES if not (path / name).exists()]
    model_path = path / "model.safetensors"
    model_size = model_path.stat().st_size if model_path.exists() else None

    config_matches_remote: bool | None = None
    config_path = path / "config.json"
    if config_path.exists():
        try:
            local_config = json.loads(config_path.read_text(encoding="utf-8"))
            config_matches_remote = all(
                local_config.get(field) == remote_config.get(field)
                for field in COMPATIBILITY_FIELDS
                + ["dtype", "quantization", "tokenizer_config"]
            )
        except json.JSONDecodeError:
            config_matches_remote = False

    tensor_count: int | None = None
    first_keys: list[str] = []
    safetensors_error: str | None = None
    if model_path.exists():
        try:
            from safetensors import safe_open

            with safe_open(str(model_path), framework="numpy") as handle:
                keys = list(handle.keys())
                tensor_count = len(keys)
                first_keys = keys[:8]
        except ImportError:
            safetensors_error = (
                "Install safetensors to inspect tensor metadata: "
                "`python3 -m pip install safetensors`."
            )
        except Exception as exc:  # pragma: no cover - best effort reporting
            safetensors_error = str(exc)

    return LocalInspection(
        path=str(path),
        missing_files=missing_files,
        model_file_size_bytes=model_size,
        config_matches_remote=config_matches_remote,
        safetensors_tensor_count=tensor_count,
        safetensors_first_keys=first_keys,
        safetensors_error=safetensors_error,
    )


def build_report(key: str, timeout: float, local_paths: dict[str, Path]) -> ModelReport:
    spec = MODEL_SPECS[key]
    repo_id = spec["repo_id"]
    api_payload = fetch_json(f"https://huggingface.co/api/models/{repo_id}", timeout)
    config_payload = fetch_json(
        f"https://huggingface.co/{repo_id}/raw/main/config.json",
        timeout,
    )
    remote_files = [item["rfilename"] for item in api_payload.get("siblings", [])]
    quant = config_payload.get("quantization") or {}
    local = None
    if key in local_paths:
        local = inspect_local_model(local_paths[key], config_payload)

    subset = {field: config_payload.get(field) for field in COMPATIBILITY_FIELDS}
    return ModelReport(
        key=key,
        display_name=spec["display_name"],
        repo_id=repo_id,
        sha=api_payload.get("sha", ""),
        last_modified=api_payload.get("lastModified", ""),
        downloads=int(api_payload.get("downloads", 0) or 0),
        used_storage_bytes=int(api_payload.get("usedStorage", 0) or 0),
        remote_files=remote_files,
        remote_required_files_present=all(name in remote_files for name in REMOTE_REQUIRED_FILES),
        architecture=list(config_payload.get("architectures", [])),
        model_type=config_payload.get("model_type"),
        dtype=config_payload.get("dtype"),
        quantization=QuantizationInfo(
            mode=quant.get("mode"),
            bits=quant.get("bits"),
            group_size=quant.get("group_size"),
        ),
        config_subset=subset,
        local=local,
    )


def compare_reports(reports: list[ModelReport]) -> dict[str, Any]:
    if not reports:
        return {"compatible": False, "reason": "No reports to compare."}

    baseline = reports[0]
    mismatches: dict[str, dict[str, Any]] = {}
    for report in reports[1:]:
        diff: dict[str, Any] = {}
        for field in COMPATIBILITY_FIELDS:
            left = baseline.config_subset.get(field)
            right = report.config_subset.get(field)
            if left != right:
                diff[field] = {
                    baseline.key: left,
                    report.key: right,
                }
        if diff:
            mismatches[report.key] = diff

    return {
        "baseline": baseline.key,
        "compatible": not mismatches,
        "mismatches": mismatches,
        "suite": EXPECTED_SUITE,
    }


def print_report(reports: list[ModelReport], comparison: dict[str, Any]) -> None:
    print("MLX Privacy Filter comparison")
    print()
    for report in reports:
        print(f"{report.display_name} ({report.repo_id})")
        print(f"  sha: {report.sha}")
        print(f"  modified: {report.last_modified}")
        print(f"  downloads: {report.downloads}")
        print(f"  remote storage: {human_bytes(report.used_storage_bytes)}")
        print(f"  dtype: {report.dtype or 'unknown'}")
        if report.quantization.mode:
            print(
                "  quantization: "
                f"{report.quantization.mode} "
                f"({report.quantization.bits}-bit, group_size={report.quantization.group_size})"
            )
        else:
            print("  quantization: none")
        print(
            "  remote files: "
            f"{'ok' if report.remote_required_files_present else 'missing expected files'}"
        )
        if report.local:
            print(f"  local path: {report.local.path}")
            print(
                "  local files: "
                f"{'ok' if not report.local.missing_files else 'missing ' + ', '.join(report.local.missing_files)}"
            )
            if report.local.model_file_size_bytes is not None:
                print(
                    "  local model.safetensors: "
                    f"{human_bytes(report.local.model_file_size_bytes)}"
                )
            if report.local.config_matches_remote is not None:
                print(
                    "  local config matches remote: "
                    f"{'yes' if report.local.config_matches_remote else 'no'}"
                )
            if report.local.safetensors_tensor_count is not None:
                print(
                    "  safetensors tensors: "
                    f"{report.local.safetensors_tensor_count}"
                )
            if report.local.safetensors_first_keys:
                print(
                    "  first tensor keys: "
                    f"{', '.join(report.local.safetensors_first_keys)}"
                )
            if report.local.safetensors_error:
                print(f"  safetensors: {report.local.safetensors_error}")
        print()

    print("Compatibility")
    print(
        "  architecture-compatible: "
        f"{'yes' if comparison.get('compatible') else 'no'}"
    )
    if comparison.get("mismatches"):
        print("  mismatches:")
        for model_key, diff in comparison["mismatches"].items():
            print(f"    {model_key}:")
            for field, values in diff.items():
                print(f"      {field}: {values}")
    else:
        print("  note: BF16 and MXFP8 match on the core architecture and label config.")
    print()
    print("Prepared sample suite")
    for sample in EXPECTED_SUITE:
        labels = ", ".join(sample["expected_labels"]) or "(no detections expected)"
        print(f"  {sample['id']}: {labels}")


def main() -> int:
    args = parse_args()
    local_paths = parse_local_models(args.local_model)
    if args.download_dir:
        downloaded = maybe_download_models(args.models, args.download_dir.expanduser().resolve())
        local_paths.update(downloaded)

    try:
        reports = [build_report(key, args.timeout, local_paths) for key in args.models]
    except urllib.error.URLError as exc:
        print(f"Failed to fetch Hugging Face metadata: {exc}", file=sys.stderr)
        return 1

    comparison = compare_reports(reports)
    payload = {
        "reports": [asdict(report) for report in reports],
        "comparison": comparison,
    }

    print_report(reports, comparison)
    if args.json_out:
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        print()
        print(f"Wrote JSON report to {args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
