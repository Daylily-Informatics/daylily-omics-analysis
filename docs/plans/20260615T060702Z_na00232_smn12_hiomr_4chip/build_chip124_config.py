#!/usr/bin/env python3
"""Build approved NA00232 chip1+chip2+chip4 config files."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
RUN_ID = "HYB-NA00232-smn12-current-20260615"
LANE_ID = "chip1-chip2-chip4"
REQUIRED_CHIPS = ("chip1", "chip2", "chip4")


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


def main() -> int:
    inspect = json.loads((ROOT / "ssm_inspect_inputs_runtime.json").read_text(encoding="utf-8"))
    counts = inspect["counts"]
    missing = []
    for chip in REQUIRED_CHIPS:
        count = int(counts[f"staged:{chip}"]["count"])
        if count <= 0:
            missing.append(chip)
    if missing:
        raise SystemExit(f"Missing required staged ONT barcode18 chips: {', '.join(missing)}")

    sample_fields, sample_rows = read_tsv(ROOT / "previous_4na_samples.tsv")
    samples = [row for row in sample_rows if row["SAMPLEID"] == "NA00232"]
    if len(samples) != 1:
        raise SystemExit(f"Expected exactly one NA00232 sample row, found {len(samples)}")

    unit_fields, unit_rows = read_tsv(ROOT / "previous_4na_units.tsv")
    base_rows = [row for row in unit_rows if row["SAMPLEID"] == "NA00232"]
    chip12 = next((row for row in base_rows if row["LANEID"] == "chip1-chip2"), None)
    chip4 = next((row for row in base_rows if row["LANEID"] == "chip4-only-sub-for-missing-chip3"), None)
    if chip12 is None or chip4 is None:
        raise SystemExit("Missing prior NA00232 chip1-chip2 or chip4 source unit")

    paths = []
    for row in (chip12, chip4):
        paths.extend([p for p in row["ONT_R1_PATH"].split(",") if p])
    by_chip = {chip: [p for p in paths if f"/{chip}/" in p] for chip in REQUIRED_CHIPS}
    bad = [chip for chip, chip_paths in by_chip.items() if len(chip_paths) != int(counts[f"staged:{chip}"]["count"])]
    if bad:
        detail = ", ".join(f"{chip}={len(by_chip[chip])}" for chip in bad)
        raise SystemExit(f"Unexpected ONT path count(s): {detail}")

    unit = dict(chip12)
    unit["RUNID"] = RUN_ID
    unit["LANEID"] = LANE_ID
    unit["ONT_R1_PATH"] = ",".join(paths)

    write_tsv(ROOT / "samples_chip124.tsv", sample_fields, samples)
    write_tsv(ROOT / "units_chip124.tsv", unit_fields, [unit])
    (ROOT / "patch_smn12_runtime_chip124.py").write_text(PATCH, encoding="utf-8")

    metadata = {
        "run_id": RUN_ID,
        "lane_id": LANE_ID,
        "sample": "NA00232",
        "barcode": "barcode18",
        "ilmn_r1": unit["ILMN_R1_PATH"],
        "ilmn_r2": unit["ILMN_R2_PATH"],
        "ont_fastq_counts": {chip: len(by_chip[chip]) for chip in REQUIRED_CHIPS},
        "ont_fastq_total": len(paths),
        "approved_substitute": "chip1+chip2+chip4, no chip3",
    }
    (ROOT / "chip124_manifest_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
