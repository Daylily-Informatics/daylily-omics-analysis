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
    assert "def _has_sentmm2ont_fastq_input(row):" in rule
    assert '_sentmm2ont_clean(row.get("ONT_R1_PATH", ""))' in rule
    assert "_has_sentmm2ont_fastq_input(row)" in rule
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


def test_read_group_epoch_suffixes_are_shell_expanded() -> None:
    rg_rules = (
        "workflow/rules/sentmm2ont_align_sort.smk",
        "workflow/rules/sentmm2_align_sort.smk",
        "workflow/rules/bwa_mem2a_align_sort.smk",
        "workflow/rules/hisat2.smk",
    )

    for path in rg_rules:
        rule = _read(path)
        assert "'@RG" not in rule, path
        assert "'ID:" not in rule, path
        assert "$epocsec" in rule, path


def test_fastq_derived_long_read_crams_emit_physical_lr_read_group_tag() -> None:
    lr_cram_rules = (
        "workflow/rules/sentmm2ont_align_sort.smk",
        "workflow/rules/sentmm2_align_sort.smk",
    )

    for path in lr_cram_rules:
        rule = _read(path)
        assert r'\\tPG:{params.rgpg}\\tLR:1"' in rule, path


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
    assert "def _sentdhiomr_has_ont_fastq_input(row):" in rule
    assert '_sentdhiomr_clean(row.get("ONT_R1_PATH", ""))' in rule
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
    assert "SENTDHIOMR_MISSING_LONGREAD_MARKER" in rule
    assert "return [SENTDHIOMR_MISSING_LONGREAD_MARKER]" in rule
    assert "sentdhiomr targets require at least one sample" not in rule
    assert "sample=SSAMPS,\n            alnr=ALIGNERS_DHIOMR" not in rule
    assert 'lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram"' not in rule


def test_sentdhiomr_segdup_is_pinned_and_validates_vcfs_before_done() -> None:
    rule = _read("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk")
    env = _read("workflow/envs/segdup_v0.2.yaml")

    assert "pip install git+https://github.com/Sentieon/segdup-caller.git" not in rule
    assert "ERROR: segdup-caller not found in pinned conda env" in rule
    assert 'vcf=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/{gene}/{sample}.{gene}.result.vcf.gz"' in rule
    assert 'yaml=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/{gene}/{sample}.{gene}.yaml"' in rule
    assert 'outdir=lambda wildcards: f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/segdup/sentdhiomr/results/{wildcards.gene}"' in rule
    assert 'caller_yaml=lambda wildcards: f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/segdup/sentdhiomr/results/{wildcards.gene}/{wildcards.sample}.yaml"' in rule
    assert "--sample_name \"{params.cluster_sample}\"" in rule
    assert "--keep_temp" in rule
    assert "mv {params.caller_yaml} {output.yaml}" in rule
    assert "grep -Eq '^[[:space:]]*{wildcards.gene}:' {output.yaml}" in rule
    assert "gzip -t {output.vcf}" in rule
    assert "bcftools view -h {output.vcf} >/dev/null" in rule
    assert "bcftools view -H {output.vcf} >/dev/null" in rule
    assert "touch {output.done}" in rule
    assert '"../envs/segdup_v0.2.yaml"' in rule
    assert "python=3.11" in env
    assert "sentieon-cli==1.6.1" in env
    assert "git+https://github.com/Sentieon/segdup-caller.git@v0.5.1" in env


def test_sentdhiomr_transfer_matches_sentieon_cli_v161_merge_contract() -> None:
    rule = _read("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk")

    assert 'subset_bed="$TMPDIR/transfer.{wildcards.tchrm}.bed"' in rule
    assert '"{params.huref}.fai" > "$subset_bed"' in rule
    assert "MERGE_RULES=$(bcftools view -h {params.pop_vcf}" in rule
    assert 'ids.append(match.group(1) + ":sum")' in rule
    assert "--regions-file \"$subset_bed\"" in rule
    assert "-i \"$MERGE_RULES\"" in rule
    assert "Population VCF lacks contig {params.regions}; carrying raw annotations for this shard" in rule
    assert "bcftools view --threads {threads} --no-version -W=tbi -O z -o {output.vcf}" in rule
