#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from xml.etree import ElementTree

import boto3


BUCKET = "lsmc-ssf-sequencing-data"
PROFILE = "lsmc"
REGION = "us-west-2"
OUT_ROOT = Path.home() / "Downloads" / "ULTIMA_RUNQC"
INPUT_ROOT = OUT_ROOT / "multiqc_input"
REPO_ROOT = Path(__file__).resolve().parents[3]
MULTIQC_CONFIG = REPO_ROOT / "config" / "external_tools" / "multiqc_config.yaml"
MAX_METRIC_FILES_PER_RUN = 24
S3_RUN_ROOT = "basecalls/lsmc/ssf-hq/"


@dataclass(frozen=True)
class RunSpec:
    run_id: str
    prefix: str


def s3_uri(key: str) -> str:
    return f"s3://{BUCKET}/{key}"


def discover_runs(client) -> list[RunSpec]:
    """Find Ultima output directories under the sequencing-data basecalls tree."""
    root_resp = client.list_objects_v2(Bucket=BUCKET, Prefix=S3_RUN_ROOT, Delimiter="/")
    run_prefixes = [
        item["Prefix"]
        for item in root_resp.get("CommonPrefixes", [])
        if re.search(r"/RUN[0-9]+/$", item["Prefix"])
    ]
    runs: list[RunSpec] = []
    for run_prefix in sorted(run_prefixes):
        year_resp = client.list_objects_v2(Bucket=BUCKET, Prefix=run_prefix, Delimiter="/")
        for year_item in year_resp.get("CommonPrefixes", []):
            out_resp = client.list_objects_v2(Bucket=BUCKET, Prefix=year_item["Prefix"], Delimiter="/")
            for out_item in out_resp.get("CommonPrefixes", []):
                prefix = out_item["Prefix"]
                leaf = prefix.rstrip("/").rsplit("/", 1)[-1]
                run_id = leaf.split("-", 1)[0]
                runs.append(RunSpec(run_id=run_id, prefix=prefix))
    if not runs:
        raise RuntimeError(f"No Ultima run output prefixes found under {s3_uri(S3_RUN_ROOT)}")
    return runs


def list_objects(client, prefix: str) -> list[dict[str, object]]:
    paginator = client.get_paginator("list_objects_v2")
    objects: list[dict[str, object]] = []
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        objects.extend(page.get("Contents", []))
    return objects


def get_text(client, key: str) -> str:
    body = client.get_object(Bucket=BUCKET, Key=key)["Body"]
    return body.read().decode("utf-8", errors="replace")


def maybe_get_text(client, key: str | None) -> str:
    if not key:
        return ""
    return get_text(client, key)


def write_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise RuntimeError(f"No rows for {path}")
    headers: list[str] = []
    for row in rows:
        for key in row:
            if key not in headers:
                headers.append(key)
    if headers[0] != "Sample":
        headers.remove("Sample")
        headers.insert(0, "Sample")
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=headers, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in headers})


def find_key(objects: list[dict[str, object]], suffix: str) -> str | None:
    for obj in objects:
        key = str(obj["Key"])
        if key.endswith(suffix):
            return key
    return None


def child_dir_from_key(prefix: str, key: str) -> str:
    rel = key[len(prefix) :]
    return rel.split("/", 1)[0] if "/" in rel else ""


def sample_name(run_id: str, child_dir: str) -> str:
    barcode = "unknown"
    match = re.search(r"-(Z[0-9]+)-", child_dir)
    if match:
        barcode = match.group(1)
    elif "-TT-TT" in child_dir:
        barcode = "TT"
    elif "-UGAv3-" in child_dir:
        barcode = child_dir.split("-", 1)[1].split("-", 1)[0]
    return f"{run_id}.{barcode}.{child_dir}"


def parse_library_info(xml_text: str) -> list[dict[str, str]]:
    if not xml_text.strip():
        return []
    root = ElementTree.fromstring(xml_text)
    samples: list[dict[str, str]] = []
    for sample in root.findall(".//Sample"):
        row = dict(sample.attrib)
        for attr in sample.findall(".//Attribute"):
            name = attr.attrib.get("Name")
            if name:
                row[name] = attr.attrib.get("Value", "")
        samples.append(row)
    return samples


def parse_csv(text: str) -> list[dict[str, str]]:
    if not text.strip():
        return []
    handle = StringIO(text)
    reader = csv.DictReader(handle)
    return [dict(row) for row in reader]


def numeric(value: object) -> float:
    text = str(value or "").strip()
    if not text:
        return 0.0
    try:
        return float(text)
    except ValueError:
        return 0.0


def parse_metric_table(text: str) -> dict[str, str]:
    lines = [line.strip() for line in text.splitlines()]
    for idx, line in enumerate(lines):
        if line.startswith("## METRICS CLASS"):
            for j in range(idx + 1, len(lines) - 1):
                if not lines[j] or lines[j].startswith("#"):
                    continue
                header = lines[j].split("\t")
                values = lines[j + 1].split("\t")
                return dict(zip(header, values))
    return {}


def parse_simple_metric_csv(text: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip() or "," not in line:
            continue
        key, value = line.split(",", 1)
        rows[key.strip()] = value.strip()
    return rows


def object_counts(prefix: str, objects: list[dict[str, object]]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for obj in objects:
        key = str(obj["Key"])
        rel = key[len(prefix) :]
        name = rel.rsplit("/", 1)[-1]
        if name.endswith(".cram.crai"):
            counts["crai"] += 1
        elif name.endswith(".cram"):
            counts["cram"] += 1
        elif name.endswith("_FlowQ.metric"):
            counts["flowq_metric"] += 1
        elif name.endswith("_SNVQ.metric"):
            counts["snvq_metric"] += 1
        elif name.endswith("_trimmer-stats.csv"):
            counts["trimmer_stats"] += 1
        elif name.endswith("_trimmer-failure_codes.csv"):
            counts["trimmer_failures"] += 1
        elif name.endswith(".selfSM.selfSM"):
            counts["selfsm"] += 1
        elif name.endswith(".selfSM.contamination_stats.csv"):
            counts["contamination_stats"] += 1
        elif name.endswith("_unmatched.csv"):
            counts["unmatched_csv"] += 1
        elif name.endswith("_unmatched.cram"):
            counts["unmatched_cram"] += 1
        elif name.endswith(".csv"):
            counts["sample_csv"] += 1
        elif name.endswith(".json"):
            counts["json"] += 1
    return counts


def write_source_manifest(path: Path, objects_by_run: dict[str, list[dict[str, object]]]) -> None:
    rows: list[dict[str, object]] = []
    for run_id, objects in objects_by_run.items():
        for obj in objects:
            key = str(obj["Key"])
            name = key.rsplit("/", 1)[-1]
            if any(
                name.endswith(suffix)
                for suffix in (
                    "_FlowQ.metric",
                    "_SNVQ.metric",
                    "_trimmer-stats.csv",
                    "_trimmer-failure_codes.csv",
                    ".selfSM.selfSM",
                    ".selfSM.contamination_stats.csv",
                    ".csv",
                    "_LibraryInfo.xml",
                    "_SequencingInfo.json",
                    "UploadCompleted.json",
                    "run_SecondaryAnalysis.txt",
                    "run_VariantCalling.txt",
                )
            ):
                rows.append(
                    {
                        "run_id": run_id,
                        "size": int(obj["Size"]),
                        "s3_uri": s3_uri(key),
                    }
                )
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, delimiter="\t", fieldnames=["run_id", "size", "s3_uri"])
        writer.writeheader()
        writer.writerows(rows)


def build_run_tables(client, run: RunSpec, objects: list[dict[str, object]]) -> dict[str, list[dict[str, object]]]:
    prefix = run.prefix
    run_dir = INPUT_ROOT / "run_qc" / "ultima" / run.run_id
    lib_key = find_key(objects, f"{run.run_id}_LibraryInfo.xml")
    upload_key = find_key(objects, "UploadCompleted.json")
    trimmer_key = find_key(objects, "merged_trimmer-stats.csv")
    failures_key = find_key(objects, "merged_trimmer-failure_codes.csv")
    sequencing_key = find_key(objects, f"{run.run_id}_SequencingInfo.json")
    lib_samples = parse_library_info(maybe_get_text(client, lib_key))
    sequencing_text = maybe_get_text(client, sequencing_key)
    try:
        sequencing = json.loads(sequencing_text) if sequencing_text else {}
    except json.JSONDecodeError:
        sequencing = {}

    counts = object_counts(prefix, objects)
    total_bytes = sum(int(obj["Size"]) for obj in objects)
    inventory = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "source_uri": s3_uri(prefix),
            "object_count": len(objects),
            "total_bytes": total_bytes,
            "libraryinfo_samples": len(lib_samples),
            "sample_csv_count": counts["sample_csv"],
            "cram_count": counts["cram"],
            "crai_count": counts["crai"],
            "flowq_metric_count": counts["flowq_metric"],
            "snvq_metric_count": counts["snvq_metric"],
            "trimmer_stats_count": counts["trimmer_stats"],
            "trimmer_failure_count": counts["trimmer_failures"],
            "selfsm_count": counts["selfsm"],
            "contamination_stats_count": counts["contamination_stats"],
            "unmatched_csv_count": counts["unmatched_csv"],
            "unmatched_cram_count": counts["unmatched_cram"],
        }
    ]
    if isinstance(sequencing, dict):
        inventory[0]["sequencing_info_keys"] = len(sequencing)

    child_dirs = {
        child_dir_from_key(prefix, str(obj["Key"]))
        for obj in objects
        if child_dir_from_key(prefix, str(obj["Key"]))
    }
    expected_barcodes = {
        sample.get("Index_Label", "")
        for sample in lib_samples
        if str(sample.get("Index_Label", "")).startswith("Z")
    }
    observed_barcodes = {
        match.group(1)
        for child in child_dirs
        for match in [re.search(r"-(Z[0-9]+)-", child)]
        if match
    }
    required_suffixes = [".csv", "_trimmer-stats.csv", "_trimmer-failure_codes.csv"]
    missing_required = 0
    for barcode in sorted(expected_barcodes):
        child = next((d for d in child_dirs if f"-{barcode}-" in d), "")
        if not child:
            missing_required += len(required_suffixes)
            continue
        keys_for_child = [str(obj["Key"]) for obj in objects if f"/{child}/" in str(obj["Key"])]
        for suffix in required_suffixes:
            if not any(key.endswith(suffix) and "_unmatched" not in key for key in keys_for_child):
                missing_required += 1
    demux = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "expected_barcodes": len(expected_barcodes),
            "observed_barcodes": len(observed_barcodes),
            "observed_readgroups": len(child_dirs),
            "expected_required_outputs": len(expected_barcodes) * len(required_suffixes),
            "missing_required_outputs": missing_required,
            "observed_sample_csv": counts["sample_csv"],
            "observed_flowq_metrics": counts["flowq_metric"],
            "observed_snvq_metrics": counts["snvq_metric"],
        }
    ]

    trimmer_rows = parse_csv(maybe_get_text(client, trimmer_key))
    trimmer = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "trimmer_rows": len(trimmer_rows),
            "total_input_reads": int(sum(numeric(row.get("num input reads")) for row in trimmer_rows)),
            "total_failed_reads": int(sum(numeric(row.get("num failed reads")) for row in trimmer_rows)),
            "total_trimmed_reads": int(sum(numeric(row.get("num trimmed reads")) for row in trimmer_rows)),
            "total_matched_bases": int(sum(numeric(row.get("num matched bases")) for row in trimmer_rows)),
            "unique_read_groups": len({row.get("read group", "") for row in trimmer_rows}),
        }
    ]
    failure_rows = parse_csv(maybe_get_text(client, failures_key))
    code_counts: Counter[str] = Counter()
    for row in failure_rows:
        code = str(row.get("code") or "unknown")
        code_counts[code] += int(numeric(row.get("failed read count")))
    failures = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "failure_rows": len(failure_rows),
            "unique_failure_codes": len(code_counts),
            "total_failed_read_count": int(sum(code_counts.values())),
            "code_8_failed_read_count": code_counts.get("8", 0),
            "code_101_failed_read_count": code_counts.get("101", 0),
            "code_102_failed_read_count": code_counts.get("102", 0),
            "code_201_failed_read_count": code_counts.get("201", 0),
        }
    ]

    def selected_keys(suffix: str) -> list[str]:
        keys = [
            str(obj["Key"])
            for obj in objects
            if str(obj["Key"]).endswith(suffix) and "/" in str(obj["Key"])[len(prefix) :]
        ]
        return sorted(keys)[:MAX_METRIC_FILES_PER_RUN]

    flow_rows: list[dict[str, str]] = [
        parse_metric_table(get_text(client, key)) for key in selected_keys("_FlowQ.metric")
    ]
    flow_rows = [row for row in flow_rows if row]
    flowq = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "metric_files_sampled": len(flow_rows),
            "total_pf_reads": int(sum(numeric(row.get("PF_READS")) for row in flow_rows)),
            "total_pf_flows": int(sum(numeric(row.get("PF_FLOWS")) for row in flow_rows)),
            "mean_pct_pf_q20_flows": round(
                sum(numeric(row.get("PCT_PF_Q20_FLOWS")) for row in flow_rows) / max(len(flow_rows), 1),
                6,
            ),
            "mean_pct_pf_q30_flows": round(
                sum(numeric(row.get("PCT_PF_Q30_FLOWS")) for row in flow_rows) / max(len(flow_rows), 1),
                6,
            ),
        }
    ]

    snvq_rows: list[dict[str, str]] = [
        parse_metric_table(get_text(client, key)) for key in selected_keys("_SNVQ.metric")
    ]
    snvq_rows = [row for row in snvq_rows if row]
    snvq = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "metric_files_sampled": len(snvq_rows),
            "total_pf_reads": int(sum(numeric(row.get("PF_READS")) for row in snvq_rows)),
            "total_pf_bases": int(sum(numeric(row.get("PF_BASES")) for row in snvq_rows)),
            "mean_pct_pf_q20_bases": round(
                sum(numeric(row.get("PCT_PF_Q20_BASES")) for row in snvq_rows) / max(len(snvq_rows), 1),
                6,
            ),
            "mean_pct_pf_q30_bases": round(
                sum(numeric(row.get("PCT_PF_Q30_BASES")) for row in snvq_rows) / max(len(snvq_rows), 1),
                6,
            ),
            "mean_pct_pf_q30_snvq": round(
                sum(numeric(row.get("PCT_PF_Q30_SNVQ")) for row in snvq_rows) / max(len(snvq_rows), 1),
                6,
            ),
        }
    ]

    sample_csv_candidates = [
        str(obj["Key"])
        for obj in objects
        if str(obj["Key"]).endswith(".csv")
        and "/" in str(obj["Key"])[len(prefix) :]
        and not any(token in str(obj["Key"]) for token in ("_trimmer-", "_unmatched", ".selfSM."))
    ]
    sample_csv_keys = []
    for key in sorted(sample_csv_candidates):
        child = child_dir_from_key(prefix, key)
        name = key.rsplit("/", 1)[-1]
        if child and name == f"{child}.csv":
            sample_csv_keys.append(key)
        if len(sample_csv_keys) >= MAX_METRIC_FILES_PER_RUN:
            break
    sample_metrics = [parse_simple_metric_csv(get_text(client, key)) for key in sample_csv_keys]
    sample_metrics = [row for row in sample_metrics if row]
    picard = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "csv_files_sampled": len(sample_metrics),
            "total_pf_barcode_reads": int(sum(numeric(row.get("PF_Barcode_reads")) for row in sample_metrics)),
            "mean_quality": round(
                sum(numeric(row.get("Mean_quality")) for row in sample_metrics) / max(len(sample_metrics), 1),
                4,
            ),
            "mean_read_length": round(
                sum(numeric(row.get("Mean_Read_Length")) for row in sample_metrics) / max(len(sample_metrics), 1),
                4,
            ),
            "mean_pct_pf_q30_bases": round(
                sum(numeric(row.get("PCT_PF_Q30_bases")) for row in sample_metrics) / max(len(sample_metrics), 1),
                4,
            ),
        }
    ]
    coverage = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "csv_files_sampled": len(sample_metrics),
            "mapq_ge_1": int(sum(numeric(row.get("MAPQ >= 1")) for row in sample_metrics)),
            "mapq_ge_10": int(sum(numeric(row.get("MAPQ >= 10")) for row in sample_metrics)),
            "mapq_ge_20": int(sum(numeric(row.get("MAPQ >= 20")) for row in sample_metrics)),
        }
    ]

    contamination = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "selfsm_files": counts["selfsm"],
            "contamination_stats_files": counts["contamination_stats"],
        }
    ]
    upload = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "upload_marker_present": 1 if upload_key else 0,
            "upload_marker_size": next((int(obj["Size"]) for obj in objects if str(obj["Key"]) == upload_key), 0),
        }
    ]
    unmatched = [
        {
            "Sample": run.run_id,
            "run_id": run.run_id,
            "unmatched_csv_count": counts["unmatched_csv"],
            "unmatched_cram_count": counts["unmatched_cram"],
        }
    ]

    tables = {
        "ultima_run_inventory_mqc.tsv": inventory,
        "ultima_demux_summary_mqc.tsv": demux,
        "ultima_trimmer_stats_mqc.tsv": trimmer,
        "ultima_trimmer_failures_mqc.tsv": failures,
        "ultima_flowq_summary_mqc.tsv": flowq,
        "ultima_snvq_summary_mqc.tsv": snvq,
        "ultima_coverage_summary_mqc.tsv": coverage,
        "ultima_picard_summary_mqc.tsv": picard,
        "ultima_contamination_mqc.tsv": contamination,
        "ultima_upload_status_mqc.tsv": upload,
        "ultima_unmatched_mqc.tsv": unmatched,
    }
    for filename, rows in tables.items():
        write_tsv(run_dir / filename, rows)
    return tables


def main() -> int:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    if INPUT_ROOT.exists():
        shutil.rmtree(INPUT_ROOT)
    data_dir = OUT_ROOT / "ultima_all_runs.multiqc_data"
    html_path = OUT_ROOT / "ultima_all_runs.multiqc.html"
    if data_dir.exists():
        shutil.rmtree(data_dir)
    if html_path.exists():
        html_path.unlink()

    session = boto3.Session(profile_name=PROFILE, region_name=REGION)
    client = session.client("s3")

    objects_by_run: dict[str, list[dict[str, object]]] = {}
    all_tables: dict[str, list[dict[str, object]]] = {}
    runs = discover_runs(client)
    (OUT_ROOT / "discovered_runs.tsv").write_text(
        "run_id\tprefix\n"
        + "".join(f"{run.run_id}\t{s3_uri(run.prefix)}\n" for run in runs),
        encoding="utf-8",
    )
    for run in runs:
        print(f"Discover/build {run.run_id}: {s3_uri(run.prefix)}")
        objects = list_objects(client, run.prefix)
        if not objects:
            raise RuntimeError(f"No S3 objects found under {s3_uri(run.prefix)}")
        objects_by_run[run.run_id] = objects
        tables = build_run_tables(client, run, objects)
        for filename, rows in tables.items():
            all_tables.setdefault(filename, []).extend(rows)

    combined_dir = INPUT_ROOT / "run_qc" / "ultima" / "combined_all_runs"
    for filename, rows in all_tables.items():
        write_tsv(combined_dir / filename, rows)
    for path in (INPUT_ROOT / "run_qc" / "ultima").iterdir():
        if path.is_dir() and path.name != "combined_all_runs":
            shutil.rmtree(path)
    write_source_manifest(OUT_ROOT / "source_manifest.tsv", objects_by_run)

    cmd = [
        "multiqc",
        str(INPUT_ROOT),
        "--config",
        str(MULTIQC_CONFIG),
        "--outdir",
        str(OUT_ROOT),
        "--filename",
        "ultima_all_runs.multiqc.html",
        "--force",
    ]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, cwd=str(REPO_ROOT), check=True)
    if not html_path.exists():
        raise RuntimeError(f"Expected MultiQC HTML was not created: {html_path}")
    if not data_dir.exists():
        raise RuntimeError(f"Expected MultiQC data directory was not created: {data_dir}")

    print(f"HTML={html_path}")
    print(f"DATA_DIR={data_dir}")
    print(f"INPUT_DIR={INPUT_ROOT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
