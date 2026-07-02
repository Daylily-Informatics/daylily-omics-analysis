from __future__ import annotations

import importlib.util
import os
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _fastq_path_lists_module():
    helper_path = REPO_ROOT / "workflow" / "scripts" / "fastq_path_lists.py"
    spec = importlib.util.spec_from_file_location("fastq_path_lists", helper_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
    assert '"use-fq_data-starting-hrs"' in common
    assert '"use-fq_data-up-to-hrs"' in common
    assert "filter_ont_fastq_paths_by_hour_window" in common
    assert 'timestamp_source="chunk-hour"' in common


def test_ont_fastq_hour_window_config_validation() -> None:
    helper = _fastq_path_lists_module()

    assert helper.validate_fastq_hour_window(1, 24) == (1, 24)
    assert helper.validate_fastq_hour_window("2", "25") == (2, 25)

    invalid_windows = [
        (0, 24),
        (24, 24),
        (25, 24),
        ("na", 24),
        (True, 24),
    ]
    for starting_hrs, up_to_hrs in invalid_windows:
        try:
            helper.validate_fastq_hour_window(starting_hrs, up_to_hrs)
        except ValueError:
            pass
        else:
            raise AssertionError(
                f"expected invalid ONT FASTQ window: {starting_hrs}, {up_to_hrs}"
            )


def test_ont_fastq_hour_window_filters_per_run_barcode_group() -> None:
    helper = _fastq_path_lists_module()
    set4_barcode14_0h = (
        "/fsx/run_dir_mounts/20260615_ONT_Set4-FC1/20260615_ONT_Set4-FC1/"
        "20260616_0048_3A_PBM08268_14b096e3/fastq_pass/barcode14/read0.fastq.gz"
    )
    set4_barcode14_1h = (
        "/fsx/run_dir_mounts/20260615_ONT_Set4-FC1/20260615_ONT_Set4-FC1/"
        "20260616_0148_3A_PBM08268_14b096e3/fastq_pass/barcode14/read1.fastq.gz"
    )
    set4_barcode14_24h = (
        "/fsx/run_dir_mounts/20260615_ONT_Set4-FC1/20260615_ONT_Set4-FC1/"
        "20260617_0048_3A_PBM08268_14b096e3/fastq_fail/barcode14/read24.fastq.gz"
    )
    set5_barcode15_1h = (
        "/fsx/run_dir_mounts/20260615_ONT_Set5-FC1/20260615_ONT_Set5-FC1/"
        "20260616_0715_3A_PBM08268_14b096e3/fastq_pass/barcode15/read1.fastq.gz"
    )
    set5_barcode15_0h = (
        "/fsx/run_dir_mounts/20260615_ONT_Set5-FC1/20260615_ONT_Set5-FC1/"
        "20260616_0615_3A_PBM08268_14b096e3/fastq_pass/barcode15/read0.fastq.gz"
    )

    filtered = helper.filter_ont_fastq_paths_by_hour_window(
        [
            set4_barcode14_0h,
            set4_barcode14_1h,
            set4_barcode14_24h,
            set5_barcode15_1h,
            set5_barcode15_0h,
        ],
        1,
        24,
    )

    assert filtered == [set4_barcode14_1h, set5_barcode15_1h]
    assert helper.ont_fastq_group_key(set4_barcode14_1h) == (
        "20260615_ONT_Set4-FC1",
        "barcode14",
    )
    assert helper.ont_fastq_acquisition_time(set4_barcode14_1h).strftime(
        "%Y%m%d%H%M"
    ) == "202606160148"


def test_ont_fastq_hour_window_can_filter_by_file_mtime(tmp_path: Path) -> None:
    helper = _fastq_path_lists_module()
    base = (
        tmp_path
        / "20260615_ONT_Set4-FC1"
        / "20260615_ONT_Set4-FC1"
        / "20260616_0048_3A_PBM08268_14b096e3"
        / "fastq_pass"
        / "barcode14"
    )
    base.mkdir(parents=True)
    paths = [
        base / "read0.fastq.gz",
        base / "read1.fastq.gz",
        base / "read24.fastq.gz",
    ]
    for path in paths:
        path.write_text("fastq\n", encoding="utf-8")

    t0 = 1_782_500_000
    os.utime(paths[0], (t0, t0))
    os.utime(paths[1], (t0 + 3600, t0 + 3600))
    os.utime(paths[2], (t0 + 86400, t0 + 86400))

    filtered = helper.filter_ont_fastq_paths_by_hour_window(
        [str(path) for path in paths],
        1,
        24,
        timestamp_source="mtime",
    )

    assert filtered == [str(paths[1])]


def test_ont_fastq_hour_window_can_filter_by_fastq_chunk_hour() -> None:
    helper = _fastq_path_lists_module()
    paths = [
        (
            "/fsx/run_dir_mounts/20260615_ONT_Set4-FC1/20260615_ONT_Set4-FC1/"
            "20260616_0048_3A_PBM08268_14b096e3/fastq_pass/barcode14/"
            f"PBM08268_pass_barcode14_14b096e3_0d51140a_{chunk}.fastq.gz"
        )
        for chunk in [0, 1, 24, 25]
    ]

    assert helper.ont_fastq_chunk_hour(paths[2]) == 24
    filtered = helper.filter_ont_fastq_paths_by_hour_window(
        paths,
        1,
        25,
        timestamp_source="chunk-hour",
    )

    assert filtered == [paths[1], paths[2]]


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
    assert 'pipeline_status=("${{PIPESTATUS[@]}}")' in rule
    assert "tolerated upstream SIGPIPE 141" in rule
    assert "samtools quickcheck -v {output.cramo:q}" in rule

    for profile in ("local", "slurm"):
        cfg = _rule_config(profile)
        assert cfg["sentmm2ont_align_sort"]["minimap2_opts"].strip() == "-ax map-ont"


def test_sentmm2ont_slurm_align_sort_requests_384_nvme_memory() -> None:
    cfg = _rule_config("slurm")
    resources = cfg["sentmm2ont_align_sort"]

    assert resources["partition"] == "i384nvme"
    assert resources["threads"] == 96
    assert resources["mem_mb"] >= 650000


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
    assert 'dbsnp=config["supporting_files"]["files"]["popvcf"]["name"]' in rule
    assert 'pop_vcf=config["sentdont"]["pop_vcf"]' in rule
    assert '-d "{params.dbsnp}"' in rule
    assert '--pop_vcf "{params.pop_vcf}"' in rule
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
        assert (
            cfg["sentdont"]["pop_vcf"]
            == "/fsx/references/genomic_data/organism_references/H_sapiens/panhg38/pop-v20g41-20251216.vcf.gz"
        )


def test_sentdhiomr_fastq_ont_waits_for_sentmm2ont_cram() -> None:
    rule = _read("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk")
    common = _read("workflow/rules/common.smk")

    assert "SENTDHIOMR_SAMPLE_ALIGNER_PAIRS" in rule
    assert "def _sentdhiomr_has_ont_fastq_input(row):" in rule
    assert '_sentdhiomr_clean(row.get("ONT_R1_PATH", ""))' in rule
    assert 'candidates.append("sentmm2ont")' in rule
    assert '"sentdhiomr": ["sentmm2ont", "ont"]' in common
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
    assert "sentdhiomr.segdup_population_vcf is required" in rule
    assert "segdup_population_vcf=_sentdhiomr_segdup_population_vcf" in rule
    assert "ERROR: Sentieon segdup population VCF not found: {input.segdup_population_vcf}" in rule
    assert "ERROR: Sentieon segdup population VCF index not found: {input.segdup_population_vcf}.tbi" in rule
    assert "SEGDUP_PACKAGE_POP_VCF=" in rule
    assert "<<'INNERPY'" in rule
    assert "segdup_pop-population-hprc-v2.0_gnomad-v4.1.0-20251216.vcf.gz" in rule
    assert "flock 9" in rule
    assert 'cp -f {input.segdup_population_vcf} "$tmp_vcf"' in rule
    assert 'cp -f {input.segdup_population_vcf}.tbi "$tmp_tbi"' in rule
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
    assert "sentieon-cli==1.6.3" in env
    assert "git+https://github.com/Sentieon/segdup-caller.git@v0.6.0" in env


def test_sentdhiomr_transfer_matches_sentieon_cli_v163_merge_contract() -> None:
    rule = _read("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk")

    assert 'subset_bed="$TMPDIR/transfer.{wildcards.tchrm}.bed"' in rule
    assert '"{params.huref}.fai" > "$subset_bed"' in rule
    assert "MERGE_RULES=$(bcftools view -h {params.pop_vcf}" in rule
    assert 'ids.append(match.group(1) + ":sum")' in rule
    assert "--regions-file \"$subset_bed\"" in rule
    assert "-i \"$MERGE_RULES\"" in rule
    assert 'merged_bcf="$TMPDIR/transfer_merged.{wildcards.tchrm}.bcf"' in rule
    assert 'merged_vcf="$TMPDIR/transfer_merged.{wildcards.tchrm}.vcf"' in rule
    assert 'trimmed_vcf="$TMPDIR/transfer_trimmed.{wildcards.tchrm}.vcf"' in rule
    assert 'bin/dayoa_sentieon pyexec "$TRIM_SCRIPT" \\\n                < "$merged_vcf" > "$trimmed_vcf" 2>> {log}' in rule
    assert 'bcftools merge --threads {threads} --no-version --regions-overlap pos -m all \\\n                --regions-file "$subset_bed" \\\n                -i "$MERGE_RULES" \\\n                -O b -o "$merged_bcf"' in rule
    assert "|| pipe_rc=$?" not in rule
    assert "pipe_rc=$?" not in rule
    assert "Population VCF lacks contig {params.regions}; carrying raw annotations for this shard" in rule
    assert "bcftools view --threads {threads} --no-version -W=tbi -O z -o {output.vcf}" in rule
