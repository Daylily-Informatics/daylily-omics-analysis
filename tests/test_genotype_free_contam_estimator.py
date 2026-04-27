from __future__ import annotations

import csv
import importlib.util
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_estimator():
    path = REPO_ROOT / "bin" / "util" / "genotype_free_contam_estimator.py"
    spec = importlib.util.spec_from_file_location("genotype_free_contam_estimator", path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["genotype_free_contam_estimator"] = module
    spec.loader.exec_module(module)
    return module


def _record(module, idx: int, alt_count: int, depth: int = 20, af: float = 0.5):
    site = module.Site(chrom="chr1", pos=1000 + idx, ref="A", alt="G", af=af)
    return module.CountRecord(site=site, ref_count=depth - alt_count, alt_count=alt_count)


def test_scalar_estimator_integrates_over_unknown_target_genotype() -> None:
    module = _load_estimator()
    records = []
    for idx in range(80):
        records.append(_record(module, idx, alt_count=2))
    for idx in range(80, 160):
        records.append(_record(module, idx, alt_count=18))

    estimate = module.estimate_scalar_contamination(
        records,
        min_depth=1,
        max_depth=100,
        min_sites=20,
        max_contamination=0.4,
        grid_step=0.01,
    )

    assert 0.16 <= estimate.contamination_fraction <= 0.24
    assert estimate.site_count == 160
    assert estimate.log_likelihood > estimate.null_log_likelihood


def test_donor_attribution_ranks_true_source_without_target_sample_genotype() -> None:
    module = _load_estimator()
    records = []
    donor_a_genotypes = {}
    donor_b_genotypes = {}
    donor_c_genotypes = {}
    for idx in range(60):
        records.append(_record(module, idx, alt_count=4))
        key = records[-1].site.key
        donor_a_genotypes[key] = 1.0
        donor_b_genotypes[key] = 0.0
        donor_c_genotypes[key] = 0.5
    for idx in range(60, 120):
        records.append(_record(module, idx, alt_count=16))
        key = records[-1].site.key
        donor_a_genotypes[key] = 0.0
        donor_b_genotypes[key] = 1.0
        donor_c_genotypes[key] = 0.5

    profiles = [
        module.CandidateProfile("HG007", donor_a_genotypes),
        module.CandidateProfile("HG003", donor_b_genotypes),
        module.CandidateProfile("HG002", donor_c_genotypes),
    ]
    attribution = module.fit_donor_attribution(
        records,
        profiles,
        total_contamination_fraction=0.20,
        min_depth=1,
        max_depth=100,
        min_sites=20,
    )

    assert attribution.donor_weights["HG007"] > attribution.donor_weights.get("HG002", 0)
    assert attribution.donor_weights["HG007"] > attribution.donor_weights.get("HG003", 0)
    assert attribution.unknown_contamination_fraction < 0.05


def test_multi_donor_attribution_keeps_third_candidate_low() -> None:
    module = _load_estimator()
    records = []
    donor_a_genotypes = {}
    donor_b_genotypes = {}
    donor_c_genotypes = {}
    for idx in range(50):
        records.append(_record(module, idx, alt_count=3))
        key = records[-1].site.key
        donor_a_genotypes[key] = 1.0
        donor_b_genotypes[key] = 0.0
        donor_c_genotypes[key] = 0.0
    for idx in range(50, 100):
        records.append(_record(module, idx, alt_count=2))
        key = records[-1].site.key
        donor_a_genotypes[key] = 0.0
        donor_b_genotypes[key] = 1.0
        donor_c_genotypes[key] = 0.0

    profiles = [
        module.CandidateProfile("donor_a", donor_a_genotypes),
        module.CandidateProfile("donor_b", donor_b_genotypes),
        module.CandidateProfile("donor_c", donor_c_genotypes),
    ]
    attribution = module.fit_donor_attribution(
        records,
        profiles,
        total_contamination_fraction=0.20,
        min_depth=1,
        max_depth=100,
        min_sites=20,
    )

    assert attribution.donor_weights["donor_a"] > attribution.donor_weights["donor_b"]
    assert attribution.donor_weights["donor_b"] > attribution.donor_weights.get("donor_c", 0)


def test_cli_writes_target_genotype_free_output_schema(tmp_path: Path) -> None:
    module = _load_estimator()
    counts_tsv = tmp_path / "counts.tsv"
    output_tsv = tmp_path / "site_mix.tsv"
    donor_tsv = tmp_path / "donors.tsv"
    with counts_tsv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["chrom", "pos", "ref", "alt", "af", "ref_count", "alt_count"],
            delimiter="\t",
        )
        writer.writeheader()
        for idx in range(30):
            writer.writerow(
                {
                    "chrom": "chr1",
                    "pos": str(2000 + idx),
                    "ref": "A",
                    "alt": "G",
                    "af": "0.5",
                    "ref_count": "18",
                    "alt_count": "2",
                }
            )
        for idx in range(30, 60):
            writer.writerow(
                {
                    "chrom": "chr1",
                    "pos": str(2000 + idx),
                    "ref": "A",
                    "alt": "G",
                    "af": "0.5",
                    "ref_count": "2",
                    "alt_count": "18",
                }
            )

    exit_code = module.main(
        [
            "--sample-id",
            "sample_a",
            "--counts-tsv",
            str(counts_tsv),
            "--output",
            str(output_tsv),
            "--donor-output",
            str(donor_tsv),
            "--min-depth",
            "1",
            "--min-sites",
            "20",
            "--grid-step",
            "0.01",
        ]
    )

    assert exit_code == 0
    summary = list(csv.DictReader(output_tsv.open(encoding="utf-8"), delimiter="\t"))
    assert summary[0]["method"] == "genotype_free_site_mix"
    assert "contamination_fraction" in summary[0]
    assert "unknown_contamination_fraction" in summary[0]
    donors = list(csv.DictReader(donor_tsv.open(encoding="utf-8"), delimiter="\t"))
    assert donors[0]["source_sample_id"] == "UNKNOWN"


def test_counts_parser_accepts_gatk_pileup_summary_columns(tmp_path: Path) -> None:
    module = _load_estimator()
    counts_tsv = tmp_path / "gatk_pileups.table"
    counts_tsv.write_text(
        "#<METADATA>SAMPLE=sample_a\n"
        "contig\tposition\tref_count\talt_count\tother_alt_count\tallele_frequency\n"
        "chr1\t101\t17\t3\t0\t0.42\n",
        encoding="utf-8",
    )

    records = module.records_from_counts_tsv(counts_tsv)

    assert records[0].site.chrom == "chr1"
    assert records[0].site.pos == 101
    assert records[0].site.af == 0.42
    assert records[0].ref_count == 17
    assert records[0].alt_count == 3
