from __future__ import annotations

import csv
import gzip
import importlib.util
import json
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

    summary = tmp_path / "results/day/hg38/other_reports/alignstats_combo_mqc.tsv"
    summary.parent.mkdir(parents=True, exist_ok=True)
    summary.write_text("Sample\tmetric\nHG001.sent.dmd\t1\n", encoding="utf-8")
    row = module._infer_record("alignment_qc", str(summary))
    assert row["Sample"] == "alignment_qc.alignstats_combo"
    assert row["base_sample"] == ""
    assert row["aligner"] == ""
    assert row["deduper"] == ""
    assert row["tool"] == "alignstats_combo_mqc"


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
        assert rows[0]["base_sample"] == "HG003"
        assert rows[0]["sample_id"] == "HG003"
        assert rows[0]["external_sample_id"] == "EXT-HG003"
    with vb2_out.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
        assert rows[0]["Sample"] == "HG003.sent.dmd"
        assert rows[0]["base_sample"] == "HG003"
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


def _write_peddy_csv(prefix: Path, suffix: str, sample: str) -> None:
    path = Path(str(prefix) + suffix)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "sample_id,family_id,ped_sex,predicted_sex,error\n"
        f"{sample},{sample},male,male,False\n",
        encoding="utf-8",
    )


def test_stage_multiqc_inputs_rewrites_peddy_to_variant_stage_ids(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_under_test",
    )
    root = tmp_path / "results/day/hg38"
    other_reports = root / "other_reports"
    other_reports.mkdir(parents=True)
    rows = []
    for deduper in ("na", "dmd"):
        prefix = (
            root
            / "HG001/align/sent"
            / deduper
            / "snv/sentd/peddy"
            / f"HG001.sent.{deduper}.sentd.peddy."
        )
        for suffix in ("sex_check.csv", "het_check.csv", "ped_check.csv"):
            _write_peddy_csv(prefix, suffix, "HG001")
        rows.append(
            {
                "Sample": f"HG001.sent.{deduper}.sentd",
                "base_sample": "HG001",
                "aligner": "sent",
                "deduper": deduper,
                "snv_caller": "sentd",
                "peddy_prefix": str(prefix),
            }
        )
    custom = other_reports / "peddy_sample_qc_mqc.tsv"
    with custom.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "Sample",
                "base_sample",
                "aligner",
                "deduper",
                "snv_caller",
                "peddy_prefix",
            ],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)

    out_dir = root / "reports/multiqc_inputs/variants"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, custom)
    stager.finish()

    with manifest.open(newline="", encoding="utf-8") as handle:
        manifest_rows = list(csv.DictReader(handle, delimiter="\t"))
    peddy_samples = {
        row["Sample"] for row in manifest_rows if row["module"] == "peddy"
    }
    assert peddy_samples == {"HG001.sent.na.sentd", "HG001.sent.dmd.sentd"}
    assert all(row["Sample"] != "custom_content" for row in manifest_rows)
    staged_sex = out_dir / "native/peddy/HG001.sent.dmd.sentd/HG001.sent.dmd.sentd.peddy.sex_check.csv"
    assert staged_sex.read_text(encoding="utf-8").splitlines()[1].startswith(
        "HG001.sent.dmd.sentd,"
    )


def test_stage_multiqc_inputs_guards_against_native_sample_collisions(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_collision_under_test",
    )
    root = tmp_path / "results/day/hg38"
    other_reports = root / "other_reports"
    other_reports.mkdir(parents=True)
    custom = other_reports / "peddy_sample_qc_mqc.tsv"
    prefixes = []
    for idx in (1, 2):
        prefix = (
            root
            / f"HG001/align/sent/dmd/snv/sentd/peddy/run{idx}"
            / "HG001.sent.dmd.sentd.peddy."
        )
        for suffix in ("sex_check.csv", "het_check.csv", "ped_check.csv"):
            _write_peddy_csv(prefix, suffix, "HG001")
        prefixes.append(prefix)
    custom.write_text(
        "Sample\tbase_sample\taligner\tdeduper\tsnv_caller\tpeddy_prefix\n"
        f"HG001.sent.dmd.sentd\tHG001\tsent\tdmd\tsentd\t{prefixes[0]}\n"
        f"HG001.sent.dmd.sentd\tHG001\tsent\tdmd\tsentd\t{prefixes[1]}\n",
        encoding="utf-8",
    )

    out_dir = root / "reports/multiqc_inputs/variants"
    stager = module.Stager(root, out_dir, out_dir / "manifest.tsv")
    stager.reset()
    with pytest.raises(module.StagingError, match="MultiQC sample collision"):
        module.stage_known_input(stager, custom)


def test_stage_multiqc_inputs_allows_repeated_custom_inventory_sample_rows(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_custom_inventory_under_test",
    )
    root = tmp_path / "results/day/hg38"
    other_reports = root / "other_reports"
    other_reports.mkdir(parents=True)
    custom = other_reports / "alignment_qc_outputs_mqc.tsv"
    custom.write_text(
        "Sample\tbase_sample\tstage\ttool\taligner\tdeduper\tsource_path\n"
        "HG001.sent.dmd\tHG001\talignment_qc\tcontam\tsent\tdmd\tgatk.tsv\n"
        "HG001.sent.dmd\tHG001\talignment_qc\tmosdepth\tsent\tdmd\tmosdepth.bed\n",
        encoding="utf-8",
    )

    out_dir = root / "reports/multiqc_inputs/final"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, custom)
    stager.finish()

    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert [row["Sample"] for row in rows] == ["HG001.sent.dmd", "HG001.sent.dmd"]
    assert {row["group_id"] for row in rows} == {
        f"{custom}:HG001.sent.dmd",
    }


def test_stage_multiqc_inputs_groups_custom_rows_with_discovered_native_sources(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_custom_native_sources_under_test",
    )
    root = tmp_path / "results/day/hg38"
    native = (
        root
        / "HG001/align/sent/dmd/snv/sentd/vcf_stats/"
        / "HG001.sent.dmd.sentd.rtg.vcfstats.txt"
    )
    native.parent.mkdir(parents=True)
    native.write_text("rtg stats\n", encoding="utf-8")
    custom = root / "other_reports/rtg_vcfstats_mqc.tsv"
    custom.parent.mkdir(parents=True)
    custom.write_text(
        "Sample\tbase_sample\taligner\tdeduper\tsnv_caller\tsource_path\n"
        f"HG001.sent.dmd.sentd\tHG001\tsent\tdmd\tsentd\t{native}\n",
        encoding="utf-8",
    )

    out_dir = root / "reports/multiqc_inputs/final"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, custom)
    stager.finish()

    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    rtg_rows = [row for row in rows if row["module"] == "rtg_vcfstats"]
    assert len(rtg_rows) == 2
    assert {row["Sample"] for row in rtg_rows} == {"HG001.sent.dmd.sentd"}
    assert {row["group_id"] for row in rtg_rows} == {
        f"{custom}:HG001.sent.dmd.sentd",
    }


def test_stage_multiqc_inputs_allows_fastqc_zip_and_html_for_same_read(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_fastqc_under_test",
    )
    root = tmp_path / "results/day/hg38"
    fastqc_dir = root / "HG001/seqqc/fastqc"
    fastqc_dir.mkdir(parents=True)
    done = fastqc_dir / "HG001.fastqc.done"
    done.write_text("done\n", encoding="utf-8")
    (fastqc_dir / "HG001.R1_fastqc.html").write_text("<html></html>\n", encoding="utf-8")
    (fastqc_dir / "HG001.R1_fastqc.zip").write_text("zip\n", encoding="utf-8")
    (fastqc_dir / "HG001.R2_fastqc.html").write_text("<html></html>\n", encoding="utf-8")
    (fastqc_dir / "HG001.R2_fastqc.zip").write_text("zip\n", encoding="utf-8")

    out_dir = root / "reports/multiqc_inputs/seq_data"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, done)
    stager.finish()

    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    fastqc_samples = [row["Sample"] for row in rows if row["module"] == "fastqc"]
    assert sorted(fastqc_samples) == ["HG001.R1", "HG001.R1", "HG001.R2", "HG001.R2"]
    assert {
        row["group_id"] for row in rows if row["module"] == "fastqc"
    } == {"fastqc:HG001:R1", "fastqc:HG001:R2"}


def test_stage_multiqc_inputs_stages_alignment_native_metrics(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_alignment_under_test",
    )
    root = tmp_path / "results/day/hg38"
    samt = root / "HG001/align/sent/dmd/alignqc/samtmetrics"
    samt.mkdir(parents=True)
    for suffix in ("stats.tsv", "flagstat.tsv", "idxstat.tsv"):
        (samt / f"HG001.sent.dmd.{suffix}").write_text("metric\n", encoding="utf-8")
    complete = samt / "HG001.sent.dmd.complete"
    complete.write_text("done\n", encoding="utf-8")
    mosdepth = (
        root
        / "HG001/align/sent/dmd/alignqc/mosdepth/HG001.sent.dmd.mosdepth.summary.sort.bed"
    )
    mosdepth.parent.mkdir(parents=True)
    mosdepth.write_text("chrom\tlength\tbases\tmean\n", encoding="utf-8")
    picard_done = (
        root
        / "HG001/align/sent/dmd/alignqc/picard/picard/HG001.sent.dmd.done"
    )
    picard_done.parent.mkdir(parents=True)
    picard_done.write_text("done\n", encoding="utf-8")
    picard_metric = (
        root
        / "HG001/align/sent/dmd/alignqc/picard/"
        / "HG001.sent.dmd.alignment_summary_metrics.txt"
    )
    picard_metric.write_text("CATEGORY\tTOTAL_READS\nPAIR\t1\n", encoding="utf-8")
    qmap_done = (
        root
        / "HG001/align/sent/dmd/alignqc/qmap/HG001.sent/dmd/HG001.sent.dmd.qmap.done"
    )
    qmap_done.parent.mkdir(parents=True)
    qmap_done.write_text("done\n", encoding="utf-8")
    (qmap_done.parent / "genome_results.txt").write_text("number of reads = 1\n", encoding="utf-8")
    vb2_tsv = (
        root
        / "HG001/align/sent/dmd/alignqc/contam/vb2/100k/HG001.sent.dmd.100k.vb2.tsv"
    )
    vb2_tsv.parent.mkdir(parents=True)
    vb2_tsv.write_text("SEQ_ID\tFREEMIX\nHG001\t0.01\n", encoding="utf-8")
    vb2_selfsm = vb2_tsv.with_name("HG001.sent.dmd.100k.vb2.selfSM")
    vb2_selfsm.write_text("SEQ_ID\tFREEMIX\nHG001\t0.01\n", encoding="utf-8")

    out_dir = root / "reports/multiqc_inputs/alignment"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, complete)
    module.stage_known_input(stager, mosdepth)
    module.stage_known_input(stager, picard_done)
    module.stage_known_input(stager, qmap_done)
    module.stage_known_input(stager, vb2_tsv)
    stager.finish()

    assert (out_dir / "native/samtools/HG001.sent.dmd.stats.tsv").exists()
    assert (
        out_dir / "native/mosdepth/HG001.sent.dmd.mosdepth.summary.sort.bed"
    ).exists()
    assert (
        out_dir / "native/picard/HG001.sent.dmd.alignment_summary_metrics.txt"
    ).exists()
    assert (out_dir / "native/qualimap/HG001.sent.dmd/genome_results.txt").exists()
    staged_selfsm = out_dir / "native/verifybamid/HG001.sent.dmd.100k.selfSM"
    assert staged_selfsm.exists()
    assert staged_selfsm.read_text(encoding="utf-8").splitlines()[1].startswith(
        "HG001.sent.dmd.100k\t"
    )
    with manifest.open(newline="", encoding="utf-8") as handle:
        samples = {row["Sample"] for row in csv.DictReader(handle, delimiter="\t")}
    assert samples == {"HG001.sent.dmd", "HG001.sent.dmd.100k"}


def test_stage_multiqc_inputs_rewrites_somalier_native_files(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/stage_multiqc_inputs.py",
        "stage_multiqc_inputs_somalier_under_test",
    )
    root = tmp_path / "results/day/hg38"
    somalier = root / "other_reports/relatedness/sent/dmd/somalier"
    somalier.mkdir(parents=True)
    samples = somalier / "cohort.samples.tsv"
    samples.write_text(
        "#family_id\tsample_id\tgt_depth_mean\tab_std\n"
        "HG001\tHG001\t12.5\t0.55\n"
        "HG002\tHG002\t11.5\t0.54\n",
        encoding="utf-8",
    )
    pairs = somalier / "cohort.pairs.tsv"
    pairs.write_text(
        "#sample_a\tsample_b\trelatedness\tibs0\tibs2\texpected_relatedness\n"
        "HG001\tHG002\t0.5\t1\t10\t0.5\n",
        encoding="utf-8",
    )

    out_dir = root / "reports/multiqc_inputs/final"
    manifest = out_dir / "manifest.tsv"
    stager = module.Stager(root, out_dir, manifest)
    stager.reset()
    module.stage_known_input(stager, samples)
    module.stage_known_input(stager, pairs)
    stager.finish()

    staged_samples = out_dir / "native/somalier/sent.dmd/cohort.samples.tsv"
    staged_pairs = out_dir / "native/somalier/sent.dmd/cohort.pairs.tsv"
    assert "HG001.sent.dmd" in staged_samples.read_text(encoding="utf-8")
    assert "HG001.sent.dmd\tHG002.sent.dmd" in staged_pairs.read_text(encoding="utf-8")
    with manifest.open(newline="", encoding="utf-8") as handle:
        somalier_samples = {
            row["Sample"]
            for row in csv.DictReader(handle, delimiter="\t")
            if row["module"] == "somalier"
        }
    assert somalier_samples == {
        "HG001.sent.dmd",
        "HG002.sent.dmd",
        "HG001.sent.dmd*HG002.sent.dmd",
    }


def test_multiqc_module_exclude_file_renders_empty_args_by_default(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/multiqc_module_exclude_args.py",
        "multiqc_module_exclude_args_under_test",
    )
    exclude_file = REPO_ROOT / "config/multiqc_module_exclude.txt"
    assert module.render_args(exclude_file) == ""

    populated = tmp_path / "exclude.txt"
    populated.write_text("peddy\nsomalier\n", encoding="utf-8")
    assert module.render_args(populated) == "--exclude peddy --exclude somalier"

    bad = tmp_path / "bad.txt"
    bad.write_text(" peddy\n", encoding="utf-8")
    with pytest.raises(ValueError, match="invalid MultiQC module name"):
        module.render_args(bad)


def test_validate_multiqc_sample_ids_rejects_collapsed_native_outputs(
    tmp_path: Path,
) -> None:
    module = _load_module(
        REPO_ROOT / "workflow/scripts/validate_multiqc_sample_ids.py",
        "validate_multiqc_sample_ids_under_test",
    )
    manifest = tmp_path / "manifest.tsv"
    manifest.write_text(
        "Sample\tmodule\tstage\tbase_sample\taligner\tdeduper\tcaller\t"
        "input_kind\tsource_path\tstaged_path\tgroup_id\n"
        "HG001.sent.na.sentd\tpeddy\tsnv\tHG001\tsent\tna\tsentd\t"
        "peddy_sex_check.csv\ta\tb\tc\n"
        "HG001.sent.dmd.sentd\tpeddy\tsnv\tHG001\tsent\tdmd\tsentd\t"
        "peddy_sex_check.csv\td\te\tf\n",
        encoding="utf-8",
    )
    collapsed = tmp_path / "collapsed.json"
    collapsed.write_text(
        json.dumps({"report_saved_raw_data": {"multiqc_peddy": {"HG001": {}}}}),
        encoding="utf-8",
    )
    with pytest.raises(SystemExit, match="collapsed stage-aware samples"):
        module.validate(manifest, collapsed)

    valid = tmp_path / "valid.json"
    valid.write_text(
        json.dumps(
            {
                "report_saved_raw_data": {
                    "multiqc_peddy": {
                        "HG001.sent.na.sentd": {},
                        "HG001.sent.dmd.sentd": {},
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    module.validate(manifest, valid)


def test_rtg_vcfeval_requests_explicit_memory() -> None:
    concordance = _read("workflow/rules/rtg_vcfeval.smk")

    assert 'mem_mb=config["rtg_vcfeval"].get("mem_mb", 64000)' in concordance
    assert 'mem_mb=config["rtg_vcfeval"].get("parse_mem_mb", 16000)' in concordance


def test_manta_converts_cram_to_bam_before_calling() -> None:
    manta_rule = _read("workflow/rules/manta.smk")
    gatk_rule = _read("workflow/rules/gatk_contam.smk")
    compat_rule = _read("workflow/rules/legacy_cram_compat_bam.smk")
    snakefile = _read("workflow/Snakefile")
    slurm_config = _read("config/day_profiles/slurm/templates/rule_config.yaml")

    assert 'include: "rules/legacy_cram_compat_bam.smk"' in snakefile
    assert "bam=temp(" in compat_rule
    assert "bai=temp(" in compat_rule
    assert "samtools view" in compat_rule
    assert "samtools index" in compat_rule
    assert "bam=rules.legacy_cram_compat_bam.output.bam" in manta_rule
    assert "bam = rules.legacy_cram_compat_bam.output.bam" in gatk_rule
    assert "gatk_cram_compat.sh" not in gatk_rule
    assert "configManta.py --bam {input.bam}" in manta_rule
    assert 'mem_mb=config["manta"].get("mem_mb", 128000)' in manta_rule
    assert "manta:\n    threads: 128\n    mem_mb: 128000" in slurm_config
    assert "legacy_cram_compat_bam:\n    threads: 32\n    mem_mb: 64000" in slurm_config


def test_native_multiqc_modules_are_enabled_and_stage_cleaned() -> None:
    multiqc = _read("config/external_tools/multiqc_config.yaml")
    snakefile = _read("workflow/Snakefile")
    exclude_file = REPO_ROOT / "config/multiqc_module_exclude.txt"

    assert "exclude_modules: []" in multiqc
    assert exclude_file.exists()
    assert not exclude_file.read_text(encoding="utf-8").strip()
    assert "\n  - goleft_indexcov\n" in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert "\n  - peddy\n" in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    assert "\n  - somalier\n" in multiqc[multiqc.index("module_order:") : multiqc.index("table_columns_visible:")]
    filename_block = multiqc[
        multiqc.index("use_filename_as_sample_name:") : multiqc.index("extra_fn_clean_trim:")
    ]
    assert "\n  - goleft_indexcov\n" not in filename_block
    assert "\n  - peddy\n" not in filename_block
    assert "\n  - somalier\n" not in filename_block
    assert 'peddy/background_pca:' not in multiqc
    assert r"^(.*)-([A-Za-z0-9_]+)-(dmd|smd|spmd|na)-cram$" in multiqc
    assert r"\.metrics$" in multiqc
    assert "_FR$" in multiqc
    assert ".alignment_summary_metrics.txt" in multiqc
    assert ".insert_size_metrics.txt" in multiqc
    active_includes = [
        line.strip()
        for line in snakefile.splitlines()
        if line.strip().startswith("include:")
    ]
    assert 'include: "rules/picard.smk"' not in active_includes
    assert '# include: "rules/picard.smk"' in snakefile
    assert 'include: "rules/qualimap.smk"' not in active_includes
    assert '# include: "rules/qualimap.smk"' in snakefile
    assert "alignqc/qmap" not in _read("workflow/rules/multiqc_final_wgs.smk")
    assert "alignqc/qmap" not in _read("workflow/rules/multiqc_cov_aln.smk")


def test_container_profile_uses_fsx_tmp_for_image_builds_and_binds_dev_shm() -> None:
    day_run = _read("bin/day_run")

    assert 'source "$profile_env_script"' in day_run
    assert "Profile environment script failed before Snakemake launch" in day_run

    for profile in ("local", "slurm"):
        config = _read(f"config/day_profiles/{profile}/templates/config.yaml")
        profile_env = _read(f"config/day_profiles/{profile}/templates/profile_env.bash")

        assert "-B /dev/shm:/dev/shm" in config
        assert 'export APPTAINER_TMPDIR="/fsx/scratch/dayoa_apptainer_tmp/${dayoa_user}"' in profile_env
        assert 'export SINGULARITY_TMPDIR="${APPTAINER_TMPDIR}"' in profile_env
        assert (
            'export APPTAINER_CACHEDIR="/fsx/resources/environments/apptainer_cache/${dayoa_user}/${dayoa_host}"'
            in profile_env
        )
        assert 'export SINGULARITY_CACHEDIR="${APPTAINER_CACHEDIR}"' in profile_env
        assert 'mkdir -p "${APPTAINER_TMPDIR}" "${APPTAINER_CACHEDIR}" || return 1' in profile_env
