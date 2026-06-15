#!/usr/bin/env python3
"""Build two-sample full-depth ILMN plus ONT chip1+chip2+chip4 config files."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PRIOR_ROOT = ROOT.parent / "20260615T060702Z_na00232_smn12_hiomr_4chip"
RUN_ID = "HYB-4NA-smn12-full-20260615"
LANE_ID = "chip1-chip2-chip4"
REQUIRED_CHIPS = ("chip1", "chip2", "chip4")
SAMPLES = {
    "NA00232": {
        "barcode": "barcode18",
        "ilmn_r1": "/fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA00232-SMN_S46_R1_001.fastq.gz",
        "ilmn_r2": "/fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA00232-SMN_S46_R2_001.fastq.gz",
        "expected_smn1": 0,
        "expected_smn2": 2,
    },
    "NA09677": {
        "barcode": "barcode19",
        "ilmn_r1": "/fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA09677-SMN_S47_R1_001.fastq.gz",
        "ilmn_r2": "/fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/NA09677-SMN_S47_R2_001.fastq.gz",
        "expected_smn1": 0,
        "expected_smn2": 3,
    },
}


PATCH = """from pathlib import Path
import yaml

path = Path('config/day_profiles/slurm/rule_config.yaml')
if not path.exists():
    raise SystemExit(f'Missing generated Slurm rule_config: {path}')
data = yaml.safe_load(path.read_text())
data['hg38_broad_samples_table'] = 'config/samples.tsv'
data['hg38_broad_units_table'] = 'config/units.tsv'
data['samples_table'] = 'config/samples.tsv'
data['units_table'] = 'config/units.tsv'
data['htd_callers'] = ['smn12', 'smaca', 'sma_finder', 'hapsma']
hapsma = data.setdefault('hapsma', {})
hapsma.update({
    'dev_exploratory': True,
    'ploidy': '1',
    'start': 'bam_single_remap',
    'smn_region': 'chr5:69949523-71054173',
    'min_smn_region_mean_coverage': 4,
    'calling_target_bed': '/fsx/references/runtime_assets/tool_specific_resources/hapsma/hg38_broad/SMN_region_38.smn_only.bed',
    'calling_target_region': 'chr5:69949523-71054173',
    'phaseset_region': 'chr5:69949523-71054173',
    'homopolymer_bed': '/fsx/references/runtime_assets/tool_specific_resources/hapsma/hg38_broad/hg38_broad_smn_100kb_pad_homopolymer_run3.bed',
    'clair3model': '/fsx/references/runtime_assets/tool_specific_resources/clair3/models/r1041_e82_400bps_sup_v500',
    'clair3_optional': '--haploid_sensitive --platform=ont --enable_long_indel',
    'minimap_index': '/fsx/references/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.map-ont.mmi',
    'minimap_param': '-y -ax map-ont',
    'fastq_tags': 'RG,Mm,Ml,MM,ML',
    'min_read_length': 1000,
    'threads': 192,
    'mem_mb': 250000,
    'partition': 'i192hugenvme,i192nvme,i384nvme',
})
sentdhiomr = data.setdefault('sentdhiomr', {})
sentdhiomr['segdup_genes'] = 'SMN1'
sentdhiomr['segdup_threads'] = 192
sentdhiomr['segdup_mem_mb'] = 250000
path.write_text(yaml.safe_dump(data, sort_keys=False))
print('patched', path)
print('samples_table', data.get('samples_table'))
print('units_table', data.get('units_table'))
print('htd_callers', data['htd_callers'])
print('hapsma.minimap_index', hapsma['minimap_index'])
print('sentdhiomr.segdup_genes', sentdhiomr['segdup_genes'])
"""


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows = list(reader)
        return list(reader.fieldnames or []), rows


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def chip_paths(rows: list[dict[str, str]], chip: str) -> list[str]:
    paths: list[str] = []
    for row in rows:
        paths.extend(
            path
            for path in row["ONT_R1_PATH"].split(",")
            if path and f"/{chip}/" in path
        )
    return sorted(set(paths))


def main() -> int:
    sample_fields, sample_rows = read_tsv(PRIOR_ROOT / "previous_4na_samples.tsv")
    unit_fields, unit_rows = read_tsv(PRIOR_ROOT / "previous_4na_units.tsv")

    selected_samples = [row for row in sample_rows if row["SAMPLEID"] in SAMPLES]
    if {row["SAMPLEID"] for row in selected_samples} != set(SAMPLES):
        raise SystemExit("Missing one or more selected sample rows")

    selected_units: list[dict[str, str]] = []
    metadata: dict[str, object] = {
        "run_id": RUN_ID,
        "lane_id": LANE_ID,
        "samples": {},
    }
    for sample_id, spec in SAMPLES.items():
        rows = [row for row in unit_rows if row["SAMPLEID"] == sample_id]
        if not rows:
            raise SystemExit(f"Missing prior unit rows for {sample_id}")
        by_chip = {chip: chip_paths(rows, chip) for chip in REQUIRED_CHIPS}
        bad = {chip: len(paths) for chip, paths in by_chip.items() if len(paths) != 73}
        if bad:
            raise SystemExit(f"Unexpected ONT path counts for {sample_id}: {bad}")
        template = next(row for row in rows if row["LANEID"] == "chip1-chip2")
        unit = dict(template)
        unit["RUNID"] = RUN_ID
        unit["LANEID"] = LANE_ID
        unit["BARCODEID"] = spec["barcode"]
        unit["ILMN_R1_PATH"] = spec["ilmn_r1"]
        unit["ILMN_R2_PATH"] = spec["ilmn_r2"]
        unit["ONT_R1_PATH"] = ",".join(
            path for chip in REQUIRED_CHIPS for path in by_chip[chip]
        )
        if "ds20x" in unit["ILMN_R1_PATH"] or "ds20x" in unit["ILMN_R2_PATH"]:
            raise SystemExit(f"Refusing downsampled ILMN path for {sample_id}")
        selected_units.append(unit)
        metadata["samples"][sample_id] = {
            "barcode": spec["barcode"],
            "ilmn_r1": spec["ilmn_r1"],
            "ilmn_r2": spec["ilmn_r2"],
            "expected_smn1": spec["expected_smn1"],
            "expected_smn2": spec["expected_smn2"],
            "ont_fastq_counts": {chip: len(by_chip[chip]) for chip in REQUIRED_CHIPS},
            "ont_fastq_total": sum(len(by_chip[chip]) for chip in REQUIRED_CHIPS),
        }

    write_tsv(ROOT / "samples_full_depth_chip124.tsv", sample_fields, selected_samples)
    write_tsv(ROOT / "units_full_depth_chip124.tsv", unit_fields, selected_units)
    (ROOT / "patch_smn12_runtime_full_depth_chip124.py").write_text(PATCH, encoding="utf-8")
    (ROOT / "full_depth_chip124_manifest_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
