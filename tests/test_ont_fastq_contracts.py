from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _rule_config(profile: str) -> dict:
    path = REPO_ROOT / "config" / "day_profiles" / profile / "templates" / "rule_config.yaml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_ont_fastq_manifest_rows_route_to_sentmm2ont_cram_aligner() -> None:
    common = _read("workflow/rules/common.smk")

    assert "def _is_ont_fastq_unit(row):" in common
    assert 'str(row.get("SEQ_VENDOR", "") or "").strip().upper() == "ONT"' in common
    assert 'ont_r1_path not in {"", "na", "none"}' in common
    assert "metadata.apply(_validate_ont_fastq_unit, axis=1)" in common
    assert 'ont_r2_path not in {"", "na", "none"}' in common
    assert 'CRAM_ALIGNERS.append("sentmm2ont")' in common


def test_sentmm2ont_consumes_single_end_ont_fastq_with_map_ont() -> None:
    rule = _read("workflow/rules/sentmm2ont_align_sort.smk")

    assert "_is_ont_fastq_unit(row)" in rule
    assert "def get_sentmm2ont_reads(wildcards):" in rule
    assert '_split_fastq_path_list(row.get("ONT_R1_PATH", ""))' in rule
    assert "return reads" in rule
    assert "reads=get_sentmm2ont_reads" in rule
    assert "input_kind=get_sentmm2ont_input_kind" in rule
    assert 'if [[ "{params.input_kind}" == "fastq" ]]' in rule
    assert "for read_path in {input.reads:q}; do" in rule
    assert 'gzip -dc -- "$read_path"' in rule
    assert 'cat -- "$read_path"' in rule
    assert "samtools fastq -@ 4 -T MM,ML {input.reads:q}" in rule
    assert "{params.minimap2_opts}" in rule

    for profile in ("local", "slurm"):
        cfg = _rule_config(profile)
        assert cfg["sentmm2ont_align_sort"]["minimap2_opts"].strip() == "-ax map-ont"


def test_sentdont_outputs_snv_and_sv_but_marks_cnv_unsupported() -> None:
    rule = _read("workflow/rules/sent_snv_ont.smk")

    assert 'ALIGNERS_ONT = ["ont", "sentmm2ont"]' in rule
    assert "bin/dayoa_sentieon_cli dnascope-longread" in rule
    assert "--tech ONT" in rule
    assert "--retain_tmpdir" in rule
    assert 'keep_tmp_dirs=config["sentdont"]["keep_tmp_dirs"]' in rule
    assert "Retaining sentdont TMPDIR because sentdont.keep_tmp_dirs=true" in rule
    assert "Preserving sentdont TMPDIR after failure" not in rule
    assert "svvcfgz=MDIR" in rule
    assert ".sentdont.sv.vcf.gz" in rule
    assert "SENTDONT_CNV_SUPPORTED = False" in rule
    assert "produce_sentdont_cnv" not in rule

    for profile in ("local", "slurm"):
        cfg = _rule_config(profile)
        assert cfg["sentdont"]["keep_tmp_dirs"] is False


def test_sentdhiomr_fastq_ont_waits_for_sentmm2ont_cram() -> None:
    rule = _read("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk")

    assert "SENTDHIOMR_SAMPLE_ALIGNER_PAIRS" in rule
    assert 'candidates.append("sentmm2ont")' in rule
    assert "def _sentdhiomr_lr_cram(wildcards):" in rule
    assert (
        'return MDIR + f"{wildcards.sample}/align/sentmm2ont/'
        '{wildcards.sample}.sentmm2ont.cram"'
    ) in rule
    assert "def _sentdhiomr_expand(pattern, **wildcards):" in rule
    assert "cram=_sentdhiomr_lr_cram" in rule
    assert "lr_cram=_sentdhiomr_lr_cram" in rule
    assert "lr_crai=_sentdhiomr_lr_crai" in rule
    assert "sample=SSAMPS,\n            alnr=ALIGNERS_DHIOMR" not in rule
    assert 'lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram"' not in rule
