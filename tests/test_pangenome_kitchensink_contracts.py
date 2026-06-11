from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_graph_pangenome_aligners_are_not_cram_qc_aligners() -> None:
    common = _read("workflow/rules/common.smk")

    assert 'GRAPH_ONLY_PANGENOME_ALIGNERS = {"pangenome_sr", "pangenome_ug"}' in common
    assert '_KNOWN_CRAM_ALIGNERS = {"sentmm2", "sentmm2ont", "ug", "ont", "pb"}' in common
    assert (
        "QC_CRAM_ALIGNERS=sorted(set(ALL_ALIGNERS)-set(BAM_ALIGNERS)-GRAPH_ONLY_PANGENOME_ALIGNERS)"
        in common
    )


def test_sentpg_variant_paths_use_fixed_spmd_deduper() -> None:
    common = _read("workflow/rules/common.smk")

    assert 'PANGENOME_SENTPG_DEDUPER = "spmd"' in common
    assert "def valid_snv_alnr_ddup_tuples(all_aligners, callers, ddups):" in common
    assert 'if snv == "sentpg" and alnr in GRAPH_ONLY_PANGENOME_ALIGNERS:' in common
    assert "tuples.append((alnr, PANGENOME_SENTPG_DEDUPER, snv))" in common


def test_variant_qc_targets_use_aligner_deduper_caller_tuples() -> None:
    for path in (
        "workflow/rules/bcftools_vcfstat.smk",
        "workflow/rules/rtg_vcfstats.smk",
        "workflow/rules/rtg_vcfeval.smk",
        "workflow/rules/vep.smk",
    ):
        rule = _read(path)
        assert "valid_snv_alnr_ddup_tuples(" in rule, path


def test_cram_qc_targets_use_cram_qc_aligners_not_all_aligners() -> None:
    expected_files = (
        "workflow/rules/generate_deduplicated_bams.smk",
        "workflow/rules/alignstats_compile.smk",
        "workflow/rules/calc_coverage_eveness.smk",
        "workflow/rules/calc_coverage_evenness_two.smk",
        "workflow/rules/multiqc_cov_aln.smk",
        "workflow/rules/picard.smk",
    )

    for path in expected_files:
        rule = _read(path)
        assert "QC_CRAM_ALIGNERS" in rule, path


def test_target_alias_na_dedup_excludes_graph_only_pangenome_aligners() -> None:
    aliases = _read("workflow/rules/workflow_target_aliases.smk")

    assert "aligners = set(QC_CRAM_ALIGNERS) | set(BAM_ALIGNERS)" in aliases
    assert "if alnr not in GRAPH_ONLY_PANGENOME_ALIGNERS:" in aliases


def test_metagenomics_kitchensink_uses_cram_qc_aligners() -> None:
    for path in (
        "workflow/rules/multiqc_final_wgs.smk",
        "workflow/rules/unmapped_metagenomics.smk",
    ):
        rule = _read(path)
        assert "aligners = sorted(ALL_ALIGNERS)" not in rule, path
        assert "QC_CRAM_ALIGNERS" in rule, path
