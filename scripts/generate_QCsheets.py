#!/usr/bin/env python3
"""Create threshold-flagged anatomical and functional QC sheets from MRIQC HTML reports."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pandas as pd
from bs4 import BeautifulSoup


def entity(filename: str, name: str) -> str | None:
    match = re.search(rf"(?:^|_){re.escape(name)}-([^_]+)", filename)
    return match.group(1) if match else None


def modality(filename: str) -> str | None:
    for suffix in ("T1w", "T2w", "bold"):
        if re.search(rf"_{suffix}(?:\.html)?$", filename):
            return suffix
    return None


def parse_iqms(path: Path) -> dict[str, float]:
    soup = BeautifulSoup(path.read_text(encoding="utf-8", errors="ignore"), "html.parser")
    table = None
    container = soup.find("div", id="about-metadata-2-collapse")
    if container:
        table = container.find("table")
    if table is None:
        for candidate in soup.find_all("table"):
            if any(len(row.find_all(["th", "td"])) >= 2 for row in candidate.find_all("tr")):
                table = candidate
                break
    if table is None:
        raise ValueError("no IQM table found")

    metrics: dict[str, float] = {}
    for row in table.find_all("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) < 2:
            continue
        name = "_".join(cell.get_text(" ", strip=True) for cell in cells[:-1])
        name = re.sub(r"\s+", "_", name).lower()
        value = cells[-1].get_text(" ", strip=True).replace(",", "")
        try:
            metrics[name] = round(float(value), 5)
        except ValueError:
            continue
    if not metrics:
        raise ValueError("IQM table contained no numeric metrics")
    return metrics


def flagged_anat(frame: pd.DataFrame) -> pd.Series:
    if frame.empty:
        return pd.Series(dtype=bool)
    conditions: list[pd.Series] = []
    thresholds: dict[str, tuple[str, float]] = {
        "cnr": ("<", 0.8), "qi_1": (">=", 0.1), "qi_2": (">=", 0.2),
        "snr_csf": ("<", 1), "snr_wm": ("<", 5),
    }
    if "snr_gm" in frame:
        values = pd.to_numeric(frame["snr_gm"], errors="coerce")
        threshold = values.mean() - 2 * values.std() if values.notna().any() else 15
        thresholds["snr_gm"] = ("<", threshold)
    for metric, (operator, threshold) in thresholds.items():
        if metric not in frame:
            continue
        values = pd.to_numeric(frame[metric], errors="coerce")
        conditions.append(values < threshold if operator == "<" else values >= threshold)
    return pd.concat(conditions, axis=1).any(axis=1) if conditions else pd.Series(False, index=frame.index)


def flagged_func(frame: pd.DataFrame) -> pd.Series:
    if frame.empty:
        return pd.Series(dtype=bool)
    conditions: list[pd.Series] = []
    if {"gsr_x", "gsr_y"}.issubset(frame.columns):
        frame["gsr"] = frame[["gsr_x", "gsr_y"]].apply(pd.to_numeric, errors="coerce").max(axis=1)
        conditions.append(frame["gsr"] > 0.3)
    for metric, threshold in {"fd_mean": 0.5, "fd_perc": 50, "aqi": 0.2}.items():
        if metric in frame:
            conditions.append(pd.to_numeric(frame[metric], errors="coerce") > threshold)
    return pd.concat(conditions, axis=1).any(axis=1) if conditions else pd.Series(False, index=frame.index)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mriqc-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    anatomical: list[dict[str, object]] = []
    functional: list[dict[str, object]] = []
    manifest: list[dict[str, str]] = []
    for report in sorted(args.mriqc_dir.glob("*.html")):
        report_modality = modality(report.name)
        if report_modality not in {"T1w", "T2w", "bold"}:
            continue
        row = {"subID": entity(report.name, "sub"), "sesID": entity(report.name, "ses"),
               "taskID": entity(report.name, "task"), "runID": entity(report.name, "run"),
               "modality": report_modality, "report_file": report.name}
        try:
            row.update(parse_iqms(report))
        except ValueError as error:
            manifest.append({"report_file": report.name, "status": "skipped", "detail": str(error)})
            continue
        manifest.append({"report_file": report.name, "status": "parsed", "detail": ""})
        (functional if report_modality == "bold" else anatomical).append(row)

    anat_frame, func_frame = pd.DataFrame(anatomical), pd.DataFrame(functional)
    anat_frame["Poor_Quality"] = flagged_anat(anat_frame)
    func_frame["Poor_Quality"] = flagged_func(func_frame)
    anat_path, func_path = args.output_dir / "QC_anat.csv", args.output_dir / "QC_func.csv"
    anat_frame.to_csv(anat_path, index=False)
    func_frame.to_csv(func_path, index=False)
    pd.DataFrame(manifest).to_csv(args.output_dir / "QC_parse_manifest.csv", index=False)
    summary = {
        "Poor Quality Functional/Total Scans": f"{int(func_frame['Poor_Quality'].sum()) if not func_frame.empty else 0}/{len(func_frame)}",
        "Poor Quality Structural/Total Scans": f"{int(anat_frame['Poor_Quality'].sum()) if not anat_frame.empty else 0}/{len(anat_frame)}",
        "Parsed reports": sum(row["status"] == "parsed" for row in manifest),
        "Skipped reports": sum(row["status"] == "skipped" for row in manifest),
    }
    (args.output_dir / "sum.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {anat_path}, {func_path}, QC_parse_manifest.csv, and sum.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
