from __future__ import annotations

import csv
import gzip
import importlib.util
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def _load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def assert_valid_multiqc_sample_id(
    value: str,
    *,
    requires_deduper: bool = False,
    requires_caller: bool = False,
    chromosome_scattered: bool = False,
) -> None:
    assert value not in {"R1", "R2"}
    for bad in (".metrics", "_FR", "-sent-dmd-cram"):
        assert bad not in value
    parts = value.split(".")
    if requires_deduper:
        assert len(parts) >= 3
    if requires_caller:
        assert len(parts) >= 4
    if chromosome_scattered:
        assert parts[-1].startswith("chr")


@pytest.mark.parametrize(
    "bad_id",
    [
        "R1",
        "R2",
        "HG002.metrics",
        "HG002_FR",
        "R0-HG002-sent-dmd-cram",
    ],
)
def test_sample_identifier_validator_rejects_historical_bad_patterns(bad_id: str) -> None:
    with pytest.raises(AssertionError):
        assert_valid_multiqc_sample_id(bad_id, requires_deduper=True)


def test_custom_output_inventory_uses_stage_aware_sample_first_column(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/multiqc_custom_output_inventory.py",
        "multiqc_custom_output_inventory_under_test",
    )
    path = (
        tmp_path
        / "results/day/hg38/HG001/align/sent/dmd/alignqc/samtmetrics/"
        / "HG001.sent.dmd.complete"
    )
    path.parent.mkdir(parents=True)
    path.write_text("done\n", encoding="utf-8")

    row = module._infer_record("alignment_qc", str(path))

    assert row["Sample"] == "HG001.sent.dmd"
    assert row["base_sample"] == "HG001"
    assert row["aligner"] == "sent"
    assert row["deduper"] == "dmd"
    assert_valid_multiqc_sample_id(str(row["Sample"]), requires_deduper=True)


def test_sequence_and_coverage_custom_tsv_contracts_are_sample_first() -> None:
    seqfu = _read("workflow/rules/seqfu.smk")
    coverage = _read("workflow/rules/calc_coverage_eveness.smk")
    alignstats = _read("workflow/rules/alignstats.smk")
    alignstats_compile = _read("workflow/rules/alignstats_compile.smk")
    alignstats_compile_script = _read("workflow/scripts/compile_alignstats.py")
    multiqc_final = _read("workflow/rules/multiqc_final_wgs.smk")
    multiqc_cov_aln = _read("workflow/rules/multiqc_cov_aln.smk")

    assert 'printf "Sample\\\\tbase_sample\\\\tread\\\\tsource_path\\\\n" > {output.mqc};' in seqfu
    assert 'printf "%s.R1\\\\t%s\\\\tR1\\\\t%s\\\\n"' in seqfu
    assert 'printf "%s.R2\\\\t%s\\\\tR2\\\\t%s\\\\n"' in seqfu
    assert (
        'echo "Sample\\tbase_sample\\tCHRM\\tmeanRawCov'
        in coverage
    )
    assert '"{params.stage_sample}.{params.chrm}$i"' in coverage
    assert "norm_cov_evenness_combo_mqc.tsv" in coverage
    assert "norm_cov_evenness_combo_mqc.tsv" in multiqc_final
    assert "norm_cov_evenness_combo_mqc.tsv" in multiqc_cov_aln
    assert "normcovevenness_combo_mqc.tsv" not in coverage
    assert "normcovevenness_combo_mqc.tsv" not in multiqc_final
    assert '"Sample", "base_sample", "aligner", "deduper"' in alignstats
    assert "day_stage_sample_id(" in alignstats
    assert "params.ddup" in alignstats
    assert "workflow/scripts/compile_alignstats.py" in alignstats_compile
    assert 'CORE_FIELDS = ["Sample", "base_sample", "aligner", "deduper"]' in alignstats_compile_script


def test_alignstats_compile_normalizes_legacy_space_delimited_rows(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/compile_alignstats.py",
        "compile_alignstats_under_test",
    )
    alignstats = (
        tmp_path
        / "results/day/hg38/HG003/align/sent/dmd/alignqc/alignstats/"
        / "HG003.sent.dmd.alignstats.tsv"
    )
    alignstats.parent.mkdir(parents=True)
    alignstats.write_text(
        "sample aligner AlignedBases MappedReads\n"
        "HG003.sent sent 12345 678\n",
        encoding="utf-8",
    )

    fieldnames, rows = module.collect_rows(str(tmp_path / "results/day/hg38/"))

    assert fieldnames[:4] == ["Sample", "base_sample", "aligner", "deduper"]
    assert rows == [
        {
            "Sample": "HG003.sent.dmd",
            "base_sample": "HG003",
            "aligner": "sent",
            "deduper": "dmd",
            "AlignedBases": "12345",
            "MappedReads": "678",
        }
    ]


def test_variant_and_concordance_custom_tsvs_include_full_stage_identity() -> None:
    bcftools = _read("workflow/rules/bcftools_vcfstat.smk")
    rtg_vcfstats = _read("workflow/rules/rtg_vcfstats.smk")
    snpeff = _read("workflow/rules/snpeff.smk")
    vep = _read("workflow/rules/vep.smk")
    peddy = _read("workflow/rules/peddy.smk")
    concordance = _read("workflow/rules/rtg_vcfeval.smk")
    concordance_parser = _read("workflow/scripts/parse-vcfeval-summary.py")
    tiddit = _read("workflow/rules/tiddit.smk")

    for text in (bcftools, rtg_vcfstats, snpeff, vep, peddy):
        assert '"Sample",' in text
        assert '"base_sample",' in text
        assert '"sample_id": sample' not in text
        assert '"sample_id": sample_id' not in text
        assert "day_stage_sample_id(sample, aligner, deduper, caller)" in text

    assert "{wildcards.ddup}" in concordance
    assert "Sample" in concordance_parser
    assert "VariantClass" in concordance_parser
    assert "InputSample" in concordance_parser
    assert "Deduper" in concordance_parser
    assert "f\"{stage_sample}.{variant_class}\"" in concordance_parser
    assert "mqc_id" not in concordance_parser
    aggregate_rule = concordance[concordance.index("rule produce_snv_concordances:") :]
    assert "perl -pi" not in aggregate_rule
    assert "\n    conda:" not in aggregate_rule
    assert "tiddit_sv_mqc.tsv" in tiddit
    assert "tiddit_sv_to_multiqc.py" in tiddit


def test_contamination_and_tiddit_custom_tsvs_are_sample_first(tmp_path: Path) -> None:
    site_mix = _read("workflow/rules/site_mix_contam.smk")
    contamination_script = _read("workflow/scripts/compile_contamination_mqc.py")
    contamination_module = _load_module(
        REPO_ROOT / "workflow/scripts/compile_contamination_mqc.py",
        "compile_contamination_mqc_under_test",
    )
    tiddit_module = _load_module(
        REPO_ROOT / "workflow/scripts/tiddit_sv_to_multiqc.py",
        "tiddit_sv_to_multiqc_under_test",
    )

    assert "workflow/scripts/compile_contamination_mqc.py" in site_mix
    assert "run:" not in site_mix[site_mix.index("rule contamination_mqc_gather:") :]
    assert 'CONTAMINATION_FIELDS = [\n    "Sample",' in contamination_script
    assert 'VB2_FIELDS = [\n    "Sample",' in contamination_script
    assert 'DONOR_FIELDS = [\n    "Sample",' in contamination_script
    assert '"Sample": sample_id' in contamination_script

    vb2_path = (
        tmp_path
        / "results/day/hg38/HG003/align/sent/dmd/alignqc/contam/vb2/100k/"
        / "HG003.sent.dmd.100k.vb2.tsv"
    )
    vb2_path.parent.mkdir(parents=True)
    vb2_path.write_text(
        "FREEMIX\t#SNPS\t#READS\tAVG_DP\n0.012\t100000\t200\t2\n",
        encoding="utf-8",
    )
    bench_path = (
        tmp_path
        / "results/day/hg38/HG003/benchmarks/HG003.sent.dmd.100k.vb2.bench.tsv"
    )
    bench_path.parent.mkdir(parents=True)
    bench_path.write_text("s\ttask_cost\n600\t0.1\n", encoding="utf-8")
    gatk_path = (
        tmp_path
        / "results/day/hg38/HG003/align/sent/dmd/alignqc/contam/gatk/"
        / "HG003.sent.dmd.gatk.tsv"
    )
    gatk_path.parent.mkdir(parents=True)
    gatk_path.write_text("FREEMIX\n0.0\n", encoding="utf-8")
    contam_out = tmp_path / "contamination_mqc.tsv"
    vb2_out = tmp_path / "verifybamid2_panel_comparison_mqc.tsv"
    site_out = tmp_path / "site_mix_contam_mqc.tsv"
    donor_out = tmp_path / "site_mix_donor_mqc.tsv"

    contamination_module.compile_reports(
        SimpleNamespace(
            sample_map_json='{"HG003":"EXT-HG003"}',
            panel_metadata_json=(
                '{"100k":{"label":"100k","snp_count":"100000",'
                '"svd_prefix":"/fsx/data/verifybamid/100k"}}'
            ),
            contamination_output=str(contam_out),
            vb2_comparison_output=str(vb2_out),
            site_mix_output=str(site_out),
            donor_output=str(donor_out),
            vb2=[str(vb2_path)],
            vb2_bench=[str(bench_path)],
            gatk=[str(gatk_path)],
            site_mix=[],
            site_mix_donors=[],
        )
    )
    with contam_out.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
        assert rows[0]["Sample"] == "HG003.sent.dmd"
        assert rows[0]["external_sample_id"] == "EXT-HG003"
    with vb2_out.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
        assert rows[0]["Sample"] == "HG003.sent.dmd"
        assert rows[0]["panel_id"] == "100k"
    for output in (site_out, donor_out):
        assert output.read_text(encoding="utf-8").split("\t", 1)[0] == "Sample"

    vcf_path = (
        tmp_path
        / "results/day/hg38/HG003/align/sent/dmd/sv/tiddit/"
        / "HG003.sent.tiddit.sv.sort.vcf.gz"
    )
    vcf_path.parent.mkdir(parents=True)
    with gzip.open(vcf_path, "wt", encoding="utf-8") as handle:
        handle.write("##fileformat=VCFv4.2\n")
        handle.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
        handle.write("chr1\t10\t.\tN\t<DEL>\t.\tPASS\tSVTYPE=DEL;END=20\n")
        handle.write("chr1\t30\t.\tN\t<BND>\t.\tPASS\tSVTYPE=BND\n")
        handle.write("chr1\t40\t.\tN\t<DUP>\t.\tPASS\tSVTYPE=DUP\n")
        handle.write("chr1\t50\t.\tN\t<UNK>\t.\tPASS\tEND=55\n")

    output = tmp_path / "tiddit_sv_mqc.tsv"
    tiddit_module.write_summary([str(vcf_path)], str(output))
    with output.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    assert rows[0]["Sample"] == "HG003.sent.dmd.tiddit"
    assert rows[0]["base_sample"] == "HG003"
    assert rows[0]["aligner"] == "sent"
    assert rows[0]["deduper"] == "dmd"
    assert rows[0]["sv_caller"] == "tiddit"
    assert rows[0]["total_records"] == "4"
    assert rows[0]["DEL"] == "1"
    assert rows[0]["DUP"] == "1"
    assert rows[0]["BND"] == "1"
    assert rows[0]["no_svtype"] == "1"
    assert_valid_multiqc_sample_id(rows[0]["Sample"], requires_deduper=True)


def test_multiqc_log_guard_renames_empty_logs_and_rejects_nonempty_logs(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/multiqc_log_guard.py",
        "multiqc_log_guard_under_test",
    )
    log_dir = tmp_path / "other_reports/logs"
    log_dir.mkdir(parents=True)
    empty_log = log_dir / "sequence_qc_outputs_mqc.log"
    empty_log.touch()

    renamed = module.guard_log_dir(log_dir)

    assert not empty_log.exists()
    assert renamed == [log_dir / "sequence_qc_outputs_legacy_custom_data.log"]
    bad_log = log_dir / "alignment_qc_outputs_mqc.log"
    bad_log.write_text("metric\tvalue\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="non-empty \\*_mqc.log"):
        module.guard_log_dir(log_dir)


def test_rtg_vcfeval_requests_explicit_memory() -> None:
    concordance = _read("workflow/rules/rtg_vcfeval.smk")

    assert 'mem_mb=config["rtg_vcfeval"].get("mem_mb", 64000)' in concordance
    assert 'mem_mb=config["rtg_vcfeval"].get("parse_mem_mb", 16000)' in concordance


def test_native_multiqc_collision_modules_are_excluded_and_cleaned() -> None:
    multiqc = _read("config/external_tools/multiqc_config.yaml")
    picard = _read("workflow/rules/picard.smk")

    assert "\n  - peddy\n" not in multiqc[multiqc.index("exclude_modules:") :]
    assert "\n  - somalier\n" not in multiqc[multiqc.index("exclude_modules:") :]
    assert "\n  - peddy\n" in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert "\n  - somalier\n" in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert 'peddy/background_pca:' not in multiqc
    assert r"^(.*)-([A-Za-z0-9_]+)-(dmd|smd|spmd|na)-cram$" in multiqc
    assert r"\.metrics$" in multiqc
    assert "_FR$" in multiqc
    assert ".alignment_summary_metrics.txt" in multiqc
    assert ".insert_size_metrics.txt" in multiqc
    assert "O={params.prefix:q}" in picard
    assert "O=$pic_d" not in picard
