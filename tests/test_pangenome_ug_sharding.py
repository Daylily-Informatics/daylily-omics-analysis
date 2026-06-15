from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "workflow/scripts/make_scoped_pangenome_bed.py"


def _load_helper():
    spec = importlib.util.spec_from_file_location("make_scoped_pangenome_bed", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def _run_helper(tmp_path: Path, regions: str, bed_text: str, fai_text: str = "chr1\t300\nchr2\t300\nchr17\t300\nchr18\t300\nchr19\t300\n") -> subprocess.CompletedProcess[str]:
    bed = _write(tmp_path / "canonical.bed", bed_text)
    fai = _write(tmp_path / "ref.fa.fai", fai_text)
    output = tmp_path / "out.bed"
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--regions",
            regions,
            "--canonical-bed",
            str(bed),
            "--fai",
            str(fai),
            "--output",
            str(output),
        ],
        check=False,
        text=True,
        capture_output=True,
    )


def test_scoped_pangenome_bed_intersects_single_contig_and_preserves_extra_columns(tmp_path: Path) -> None:
    helper = _load_helper()
    fai = _write(tmp_path / "ref.fa.fai", "chr19\t300\nchr20\t300\n")
    bed = _write(
        tmp_path / "canonical.bed",
        "chr19\t50\t250\tcanon19\t42\nchr20\t0\t100\tcanon20\t7\n",
    )
    output = tmp_path / "scoped.bed"

    helper.write_bed(
        helper.intersect(helper.read_bed(bed), helper.parse_regions("chr19", helper.read_fai(fai))),
        output,
    )

    assert output.read_text(encoding="utf-8") == "chr19\t50\t250\tcanon19\t42\n"


def test_scoped_pangenome_bed_accepts_range_expanded_region_order(tmp_path: Path) -> None:
    result = _run_helper(
        tmp_path,
        "chr17,chr18,chr19",
        "chr19\t10\t20\nchr17\t30\t40\nchr18\t50\t60\n",
    )

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "out.bed").read_text(encoding="utf-8") == (
        "chr17\t30\t40\nchr18\t50\t60\nchr19\t10\t20\n"
    )


def test_scoped_pangenome_bed_handles_tilde_and_colon_subregions(tmp_path: Path) -> None:
    bed_text = "chr1\t50\t250\tcanon1\n"

    tilde = _run_helper(tmp_path / "tilde", "chr1~101-200", bed_text)
    colon = _run_helper(tmp_path / "colon", "chr1:101-200", bed_text)

    assert tilde.returncode == 0, tilde.stderr
    assert colon.returncode == 0, colon.stderr
    assert (tmp_path / "tilde/out.bed").read_text(encoding="utf-8") == "chr1\t100\t200\tcanon1\n"
    assert (tmp_path / "colon/out.bed").read_text(encoding="utf-8") == "chr1\t100\t200\tcanon1\n"


@pytest.mark.parametrize(
    ("regions", "bed_text", "expected"),
    [
        ("chr1", "chr2\t0\t10\n", "No overlap"),
        ("chr1", "chr1\t0\n", "Malformed BED"),
        ("chr1", "chr1\t-1\t10\n", "Invalid BED"),
        ("chr1", "chr1\t10\t10\n", "Invalid BED"),
    ],
)
def test_scoped_pangenome_bed_fails_hard_for_bad_or_empty_inputs(
    tmp_path: Path, regions: str, bed_text: str, expected: str
) -> None:
    result = _run_helper(tmp_path, regions, bed_text)

    assert result.returncode != 0
    assert expected in result.stderr


def test_scoped_pangenome_bed_rejects_unknown_contig(tmp_path: Path) -> None:
    result = _run_helper(tmp_path, "chr3", "chr1\t0\t10\n")

    assert result.returncode != 0
    assert "absent from the reference FAI" in result.stderr


def test_sentpgs_profile_config_matches_requested_shard_defaults() -> None:
    slurm = yaml.safe_load((REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml").read_text(encoding="utf-8"))
    local = yaml.safe_load((REPO_ROOT / "config/day_profiles/local/templates/rule_config.yaml").read_text(encoding="utf-8"))

    expected_slurm = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17-19,20-25"
    for key in ("hg38_sentpgs_chrms", "hg38_broad_sentpgs_chrms", "b37_sentpgs_chrms"):
        assert slurm["sentieon_pangenome_ug"][key] == expected_slurm
        assert local["sentieon_pangenome_ug"][key] == "19-20"

    for key in ("shard_threads", "shard_mem_mb", "shard_partition", "concat_threads", "concat_mem_mb", "concat_partition"):
        assert key in slurm["sentieon_pangenome_ug"]
        assert key in local["sentieon_pangenome_ug"]


def test_sentpgs_rules_are_isolated_from_monolithic_sentpg() -> None:
    rules = (REPO_ROOT / "workflow/rules/sentieon_pangenome_ug.smk").read_text(encoding="utf-8")

    assert "rule sentieon_pangenome_ug:" in rules
    assert 'snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz' in rules
    assert 'rule sentieon_pangenome_ug_shard_bed:' in rules
    assert 'rule sentieon_pangenome_ug_sharded:' in rules
    assert 'rule sentpgs_concat_fofn:' in rules
    assert 'rule sentpgs_concat_index_chunks:' in rules
    assert 'rule produce_pangenome_ug_sharded_vcf:' in rules
    assert 'cluster_sample=lambda wildcards: f"{ret_sample(wildcards)}-{wildcards.dchrm}"' in rules
    assert "make_scoped_pangenome_bed.py" in rules
    assert '--canonical-bed "{params.canonical_bed}"' in rules
    assert '-b "$scoped_canonical_bed"' in rules
    assert 'snv/sentpgs/vcfs/{dchrm}/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.snv.sort.vcf.gz' in rules
    assert 'snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz' in rules
    assert "-b \"{params.canonical_bed}\"" in rules


def test_sentpgs_common_routing_contract() -> None:
    common = (REPO_ROOT / "workflow/rules/common.smk").read_text(encoding="utf-8")

    assert 'SENTPGS_CHRMS = config["sentieon_pangenome_ug"][f"{config[\'genome_build\']}_sentpgs_chrms"].split(",")' in common
    assert '"sentpgs":   ["pangenome_ug"]' in common
    assert 'if snv in {"sentpg", "sentpgs"} and alnr in GRAPH_ONLY_PANGENOME_ALIGNERS:' in common


def test_rtg_vcfeval_roi_escapes_internal_shell_variables_for_dryrun() -> None:
    rtg = (REPO_ROOT / "workflow/rules/rtg_vcfeval.smk").read_text(encoding="utf-8")

    assert 'rtg_mem_gb=$(( ({resources.mem_mb} * 85 / 100 + 1023) / 1024 ))' in rtg
    assert 'RTG_MEM="${{rtg_mem_gb}}G" rtg vcfeval' in rtg
