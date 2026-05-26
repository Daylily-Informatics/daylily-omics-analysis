from __future__ import annotations

import csv
import importlib.util
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
VERIFYBAMID2_HG38_100K_SVD_PREFIX = (
    "/fsx/references/tool_specific_resources/verifybamid/hg38/100k/"
    "1000g.phase3.100k.b38.vcf.gz.dat"
)
GIAB7_IDS = ["HG001", "HG002", "HG003", "HG004", "HG005", "HG006", "HG007"]
GIAB_30X_FASTQ_ROOT = (
    "/fsx/control_data/genomic_data/organism_reads/H_sapiens/giab/"
    "NovaSeqX_WHGS_TruSeqPF_HG002-007"
)
GIAB_5X_SUBSAMPLE = "0.1666666667"
SYNTHETIC_LEVELS_PCT = [0.1, 0.5, 1, 2, 3, 4, 5, 10, 20, 30]


def _read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def _load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"Unable to import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _load_synthetic_contam_module() -> ModuleType:
    candidate_paths = [
        REPO_ROOT / "bin" / "util" / "generate_synthetic_contamination_fastqs.py",
        REPO_ROOT / "bin" / "util" / "generate_synthetic_contamination_manifests.py",
        REPO_ROOT / "workflow" / "scripts" / "generate_synthetic_contamination_fastqs.py",
        REPO_ROOT / "workflow" / "scripts" / "synthetic_contamination.py",
    ]
    dynamic_candidates = sorted(
        {
            *REPO_ROOT.glob("bin/util/*contam*.py"),
            *REPO_ROOT.glob("workflow/scripts/*contam*.py"),
        }
    )
    for path in [*candidate_paths, *dynamic_candidates]:
        if path.exists():
            module = _load_module(path, "synthetic_contamination_under_test")
            required = {"parse_levels", "DEFAULT_LEVELS", "build_plan", "write_manifests"}
            if required.issubset(set(dir(module))):
                return module
    pytest.fail(
        "Expected a synthetic contamination generator module under bin/util or "
        "workflow/scripts; it must expose parse_levels, DEFAULT_LEVELS, build_plan, "
        "and write_manifests."
    )


def test_giab7_ilmn_5x_manifest_fixture_contract() -> None:
    module = _load_module(
        REPO_ROOT / "scripts" / "generate_giab7_ilmn5x_manifests.py",
        "giab7_manifest_under_test",
    )
    fixture_dir = REPO_ROOT / "tests" / "fixtures" / "giab7_ilmn_5x"
    expected_samples = _read_tsv(fixture_dir / "samples.tsv")
    expected_units = _read_tsv(fixture_dir / "units.tsv")

    _sample_fields, source_samples = module.load_samples(module.DEFAULT_SOURCE_SAMPLES)
    samples = [source_samples[sample_id] for sample_id in GIAB7_IDS]
    units = [
        module.build_unit_row(sample_id, Path(GIAB_30X_FASTQ_ROOT))
        for sample_id in GIAB7_IDS
    ]

    assert samples == expected_samples
    for generated, expected in zip(units, expected_units, strict=True):
        for field in (
            "SAMPLEID",
            "SEQ_VENDOR",
            "SEQ_PLATFORM",
            "ILMN_R1_PATH",
            "ILMN_R2_PATH",
            "SUBSAMPLE_PCT",
            "SAMPLEUSE",
            "BWA_KMER",
        ):
            assert generated[field] == expected[field]

    assert [row["SAMPLEID"] for row in samples] == GIAB7_IDS
    assert [row["SAMPLEID"] for row in units] == GIAB7_IDS

    for row in samples:
        sample_id = row["SAMPLEID"]
        assert row["EXTERNAL_SAMPLE_ID"] == sample_id
        assert row["IS_POSITIVE_CONTROL"] == "true"
        assert row["IS_NEGATIVE_CONTROL"] == "false"
        assert row["TRUTH_DATA_DIR"].endswith(f"/{sample_id}/")

    for row in units:
        sample_id = row["SAMPLEID"]
        assert row["SEQ_VENDOR"] == "ILMN"
        assert row["SEQ_PLATFORM"] == "NOVASEQ"
        assert row["SUBSAMPLE_PCT"] == GIAB_5X_SUBSAMPLE
        assert row["SAMPLEUSE"] == "posControl"
        assert row["BWA_KMER"] == "19"
        assert row["ILMN_R1_PATH"] == f"{GIAB_30X_FASTQ_ROOT}/{sample_id}_30x_R1.fastq.gz"
        assert row["ILMN_R2_PATH"] == f"{GIAB_30X_FASTQ_ROOT}/{sample_id}_30x_R2.fastq.gz"


def test_peddy_rule_hard_fails_and_does_not_unconditionally_mark_done() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "peddy.smk").read_text(encoding="utf-8")

    assert "set +e" not in text
    assert "masking error" not in text
    assert "pca failure which can be ignored" not in text
    assert "touch {output.done}" not in text
    assert 'if [[ ! -s "$expected_output" ]]' in text
    assert "{output.prefix}html" in text
    assert "{output.prefix}het_check.csv" in text
    assert "{output.prefix}ped_check.csv" in text
    assert text.index('if [[ ! -s "$expected_output" ]]') < text.index(
        'printf \'reallydone\\n\' > "{output.done}"'
    )


def test_peddy_defaults_invalid_sample_sex_to_male_and_logs_assumption() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "peddy.smk").read_text(encoding="utf-8")

    assert 'sample_sex_for_required_tool(wildcards, "Peddy")' in text
    assert "ped_sex = 0" not in text
    assert "ped_sex = 1" in text
    assert "ped_sex = 2" in text
    assert "sample_sex_assumption_log(" in text
    assert 'printf \'%s\' {params.sex_assumption_log:q} >> "{log}"' in text


def test_required_sample_sex_helper_preserves_raw_value_and_defaults_to_male() -> None:
    common = (REPO_ROOT / "workflow" / "rules" / "common.smk").read_text(
        encoding="utf-8"
    )

    assert 'sample_info[samp_id]["biological_sex_raw"] = raw_bsex' in common
    assert "def sample_sex_for_required_tool(" in common
    assert "def sample_sex_assumption_log(" in common
    assert 'return "male"' in common
    assert "Assuming male" in common


def test_octopus_invalid_sample_sex_uses_shared_male_default() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "octopus.smk").read_text(
        encoding="utf-8"
    )

    assert 'sample_sex_for_required_tool(wildcards, "Octopus")' in text
    assert "X=2 Y=1" not in text
    assert 'config["sample_info"][wildcards.sample]["biological_sex"]' not in text


@pytest.mark.parametrize(
    "env_path",
    [
        "workflow/envs/peddy_v0.1.yaml",
        "workflow/envs/peddy.yaml",
    ],
)
def test_peddy_env_pins_numpy_and_python_for_peddy_048(env_path: str) -> None:
    text = (REPO_ROOT / env_path).read_text(encoding="utf-8")

    assert "peddy" in text
    assert "python>=3.9,<3.13" in text
    assert "numpy<2" in text


@pytest.mark.parametrize(
    ("rule_path", "target_rule", "expected"),
    [
        (
            "workflow/rules/gatk_contam.smk",
            "produce_gatk_contam_estimate",
            "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/"
            "{sample}.{alnr}.{ddup}.gatk.tsv",
        ),
        (
            "workflow/rules/verifybamid2_contam.smk",
            "produce_contam_estimate",
            "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/"
            "{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv",
        ),
        (
            "workflow/rules/site_mix_contam.smk",
            "produce_site_mix_contam_estimate",
            "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/"
            "{sample}.{alnr}.{ddup}.site_mix.tsv",
        ),
    ],
)
def test_contamination_target_expansion_includes_deduper_level(
    rule_path: str,
    target_rule: str,
    expected: str,
) -> None:
    text = (REPO_ROOT / rule_path).read_text(encoding="utf-8")
    target_start = text.index(f"rule {target_rule}:")
    target_text = text[target_start:]

    assert expected in target_text
    assert "ddup=DDUP" in target_text or "ddup=qc_contamination_dedupers()" in target_text


def test_gatk_contam_env_includes_cram_compat_tools() -> None:
    text = (REPO_ROOT / "workflow" / "envs" / "gatkcontam_v0.1.yaml").read_text(
        encoding="utf-8"
    )

    assert "gatk4" in text
    assert "htslib" in text
    assert "samtools" in text


def test_gatk_contam_rule_sets_heap_and_dense_interval_mode() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "gatk_contam.smk").read_text(
        encoding="utf-8"
    )

    assert 'mem_mb = config["gatk_contam"].get("mem_mb", 80000)' in text
    assert 'java_heap_mb = config["gatk_contam"].get("java_heap_mb", 64000)' in text
    assert 'exclusive = config["gatk_contam"].get("exclusive", "--exclusive")' in text
    assert '--java-options "-Xmx{params.java_heap_mb}m' in text
    assert "--interval-merging-rule OVERLAPPING_ONLY" in text
    assert "--disable-bam-index-caching" in text

    expected_exclusive = {
        "config/day_profiles/slurm/templates/rule_config.yaml": 'exclusive: "--exclusive"',
        "config/day_profiles/local/templates/rule_config.yaml": 'exclusive: ""',
    }
    for config_path, exclusive in expected_exclusive.items():
        config_text = (REPO_ROOT / config_path).read_text(encoding="utf-8")
        gatk_config = config_text[config_text.index("gatk_contam:") :]
        assert "mem_mb: 80000" in gatk_config[:240]
        assert "java_heap_mb: 64000" in gatk_config[:240]
        assert exclusive in gatk_config[:240]


def test_gatk_contam_uses_sparse_chr_prefixed_af_sites() -> None:
    expected = (
        "/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/snp_vcfs/"
        "snp_subset_1M/filtered_vcfs/merged.500perchr.nosamp.sort.vcf.gz"
    )

    for config_path in (
        "config/supporting_files/hg38_supporting_files.yaml",
        "config/supporting_files/hg38_broad_supporting_files.yaml",
    ):
        config_text = (REPO_ROOT / config_path).read_text(encoding="utf-8")
        gatk_config = config_text[config_text.index("    gatk:") :]
        assert f"af_sites: {expected}" in gatk_config[:800]
        assert "af-only-gnomad.hg38.vcf.gz" not in gatk_config[:800]


def test_gatk_cram_compat_parses_htsfile_tab_delimited_output() -> None:
    text = (REPO_ROOT / "bin" / "util" / "gatk_cram_compat.sh").read_text(
        encoding="utf-8"
    )

    assert "sed -E 's/^[^:]*:[[:space:]]*//'" in text
    assert "version[[:space:]]+" in text
    assert "awk -F': '" not in text
    assert "OUT_EXPLICIT=1" in text
    assert "samtools quickcheck" in text
    assert "Reusing existing default OUT" in text
    assert "Removing corrupt default OUT before regeneration" in text
    assert "Removing empty default OUT before regeneration" in text


def test_verifybamid2_uses_svd_prefix_not_sites_only_refvcf() -> None:
    rule_text = (REPO_ROOT / "workflow" / "rules" / "verifybamid2_contam.smk").read_text(
        encoding="utf-8"
    )

    assert "--SVDPrefix {params.db_prefix}" in rule_text
    assert "--RefVCF {params.site_vcf}" not in rule_text
    assert "verifybamid2_panel_svd_prefix(wildcards) + \".UD\"" in rule_text
    assert "verifybamid2_panel_svd_prefix(wildcards) + \".V\"" in rule_text
    assert "{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv" in rule_text
    assert "rule produce_verifybamid2_panel_comparison:" in rule_text
    assert "verifybamid2_panel_comparison_mqc.tsv" in rule_text

    for config_path in (
        "config/supporting_files/hg38_supporting_files.yaml",
        "config/supporting_files/hg38_broad_supporting_files.yaml",
    ):
        config_text = (REPO_ROOT / config_path).read_text(encoding="utf-8")
        assert "chr20_verbam/chr20.random1000.vcf.gz" in config_text
        assert VERIFYBAMID2_HG38_100K_SVD_PREFIX in config_text
        assert (
            "/fsx/references/tool_specific_resources/verifybam2/"
            "1000g.phase3.100k.b38.vcf.gz.dat"
            not in config_text
        )
        assert "daylily.snp_subset_1M.b38.vcf.gz.dat" in config_text
        assert "snp_subset_1M/1M_snps.sorted.vcf.gz" in config_text


def test_verifybamid2_panel_config_and_resources_are_declared() -> None:
    common = (REPO_ROOT / "workflow" / "rules" / "common.smk").read_text(
        encoding="utf-8"
    )
    assert "def verifybamid2_selected_panels" in common
    assert "VERIFYBAMID2_PANELS = verifybamid2_selected_panels()" in common
    assert "verifybamid2_panels" in common
    assert "verifybamid2_panel_svd_prefixes" in common

    profile_expectations = {
        "config/day_profiles/local/templates/rule_config.yaml": {
            "100k_threads": 8,
            "100k_mem_mb": 16000,
            "100k_svd_prefix": VERIFYBAMID2_HG38_100K_SVD_PREFIX,
        },
        "config/day_profiles/slurm/templates/rule_config.yaml": {
            "100k_threads": 64,
            "100k_mem_mb": 64000,
            "100k_svd_prefix": VERIFYBAMID2_HG38_100K_SVD_PREFIX,
        },
    }

    for profile_path, expected in profile_expectations.items():
        profile = yaml.safe_load((REPO_ROOT / profile_path).read_text(encoding="utf-8"))
        vb2 = profile["verifybamid2_contam"]
        assert profile["verifybamid2_panels"] == []
        assert profile["verifybamid2_panel_svd_prefixes"] == {}
        assert vb2["default_panel"] == "100k"
        assert vb2["active_panels"] == ["100k"]
        assert set(vb2["panels"]) == {"1k", "100k", "1m"}
        assert vb2["panels"]["1k"]["snp_count"] == 1000
        assert vb2["panels"]["100k"]["threads"] == expected["100k_threads"]
        assert vb2["panels"]["100k"]["mem_mb"] == expected["100k_mem_mb"]
        assert (
            vb2["panels"]["100k"]["svd_prefix"]["name"]
            == expected["100k_svd_prefix"]
        )


def test_site_mix_contam_rule_is_target_genotype_free() -> None:
    rule_text = (REPO_ROOT / "workflow" / "rules" / "site_mix_contam.smk").read_text(
        encoding="utf-8"
    )

    assert "genotype_free_contam_estimator.py" in rule_text
    assert "day_stage_sample_id(sample, aligner, deduper)" in rule_text
    assert "alignqc/contam/gatk/{sample}.{alnr}.{ddup}.pileups.table" in rule_text
    assert "--counts-tsv {input.pileups}" in rule_text
    assert "--bam {input.cram}" not in rule_text
    assert "--sites-vcf {input.sites_vcf}" not in rule_text
    assert "samtools mpileup" not in rule_text
    assert "does not support candidate_manifest donor attribution" in rule_text
    assert "truth" not in rule_text.lower()
    assert "expected" not in rule_text.lower()
    assert "candidate_manifest" in rule_text

    for config_path in (
        "config/day_profiles/slurm/templates/rule_config.yaml",
        "config/day_profiles/local/templates/rule_config.yaml",
    ):
        config_text = (REPO_ROOT / config_path).read_text(encoding="utf-8")
        section = config_text[config_text.index("site_mix_contam:") :]
        assert 'candidate_manifest: ""' in section[:800]
        assert "sites_vcf:" in section[:800]
        assert "pileup_region_size: 25000000" in section[:800]


def test_synthetic_contamination_manifest_levels_and_count_calculations(tmp_path: Path) -> None:
    module = _load_synthetic_contam_module()

    parsed_levels = [float(level) for level in module.parse_levels(module.DEFAULT_LEVELS)]
    assert parsed_levels == SYNTHETIC_LEVELS_PCT
    args_defaults = module.parse_args([])
    assert args_defaults.primary_coverage == "30"
    assert args_defaults.primary_sample == "HG002"
    assert args_defaults.donor_sample == "HG003"
    assert args_defaults.sample_prefix == "HG002-HG003-contam"
    assert args_defaults.primary_r1.endswith("/HG002_30x_R1.fastq.gz")
    assert args_defaults.primary_r2.endswith("/HG002_30x_R2.fastq.gz")
    assert args_defaults.donor_r1.endswith("/HG003_30x_R1.fastq.gz")
    assert args_defaults.donor_r2.endswith("/HG003_30x_R2.fastq.gz")

    hg001_hg007_args = module.parse_args(
        ["--primary-sample", "HG001", "--donor-sample", "HG007"]
    )
    assert hg001_hg007_args.sample_prefix == "HG001-HG007-contam"
    assert hg001_hg007_args.primary_r1.endswith("/HG001_30x_R1.fastq.gz")
    assert hg001_hg007_args.primary_r2.endswith("/HG001_30x_R2.fastq.gz")
    assert hg001_hg007_args.donor_r1.endswith("/HG007_30x_R1.fastq.gz")
    assert hg001_hg007_args.donor_r2.endswith("/HG007_30x_R2.fastq.gz")

    args = SimpleNamespace(
        levels="0.1,5",
        output_dir="/fsx/scratch/dayoa_qc_contam/giab_hg002_hg003_5x_20260425",
        sample_prefix="HG002-HG003-contam",
        target_coverage="5",
        primary_coverage="5",
        donor_coverage="30",
    )
    out_dir, rows = module.build_plan(args)
    assert str(out_dir) == args.output_dir
    assert [row["sample_id"] for row in rows] == [
        "HG002-HG003-contam-0p1pct",
        "HG002-HG003-contam-5pct",
    ]
    assert rows[0]["primary_fraction"] == module.Decimal("0.999")
    assert rows[0]["donor_fraction"] == module.Decimal("0.0001666666666666666666666666667")
    assert rows[1]["primary_fraction"] == module.Decimal("0.95")
    assert rows[1]["donor_fraction"] == module.Decimal("0.008333333333333333333333333333")

    manifest_args = SimpleNamespace(
        dry_run=False,
        truth_dir="/truth/HG002/",
        run_id="GIABCONTAM20260425",
        primary_sample="HG002",
        donor_sample="HG003",
        target_coverage="5",
        primary_coverage="5",
        donor_coverage="30",
        primary_seed=20260425,
        donor_seed=20260426,
    )
    local_out_dir = tmp_path / "synthetic_contam_manifest"
    local_rows = [
        {
            **row,
            "r1": local_out_dir / row["r1"].name,
            "r2": local_out_dir / row["r2"].name,
        }
        for row in rows
    ]
    module.write_manifests(
        manifest_args,
        local_out_dir,
        local_rows,
        Path("/inputs/HG002_5x_R1.fastq.gz"),
        Path("/inputs/HG002_5x_R2.fastq.gz"),
        Path("/inputs/HG003_30x_R1.fastq.gz"),
        Path("/inputs/HG003_30x_R2.fastq.gz"),
    )
    samples = _read_tsv(local_out_dir / "samples.tsv")
    units = _read_tsv(local_out_dir / "units.tsv")
    plan = _read_tsv(local_out_dir / "contamination_plan.tsv")

    assert [row["SAMPLEID"] for row in samples] == [
        "HG002-HG003-contam-0p1pct",
        "HG002-HG003-contam-5pct",
    ]
    assert [row["SUBSAMPLE_PCT"] for row in units] == ["", ""]
    assert [row["contamination_percent"] for row in plan] == ["0.1", "5"]
    assert [row["primary_sample"] for row in plan] == ["HG002", "HG002"]
    assert [row["donor_sample"] for row in plan] == ["HG003", "HG003"]
    assert [row["primary_sampling_fraction"] for row in plan] == ["0.999", "0.95"]
    assert [row["donor_sampling_fraction"] for row in plan] == [
        "0.000166666667",
        "0.008333333333",
    ]

    script_text = (
        REPO_ROOT / "bin" / "util" / "make_giab_hg002_hg003_contam_fastqs.py"
    ).read_text(encoding="utf-8")
    assert 'require_tool("pigz")' in script_text
    assert "seqkit" not in script_text.lower()


def test_synthetic_contamination_manifests_accept_arbitrary_giab_pair(
    tmp_path: Path,
) -> None:
    module = _load_synthetic_contam_module()
    args = SimpleNamespace(
        levels="0.5",
        output_dir=str(tmp_path / "synthetic"),
        sample_prefix="HG001-HG007-contam",
        target_coverage="5",
        primary_coverage="30",
        donor_coverage="30",
    )
    out_dir, rows = module.build_plan(args)
    assert rows[0]["sample_id"] == "HG001-HG007-contam-0p5pct"

    manifest_args = SimpleNamespace(
        dry_run=False,
        truth_dir="/truth/HG001/",
        run_id="GIABCONTAMHG001HG00720260426",
        primary_sample="HG001",
        donor_sample="HG007",
        target_coverage="5",
        primary_coverage="30",
        donor_coverage="30",
        primary_seed=20260425,
        donor_seed=20260426,
    )
    module.write_manifests(
        manifest_args,
        out_dir,
        rows,
        Path("/inputs/HG001_30x_R1.fastq.gz"),
        Path("/inputs/HG001_30x_R2.fastq.gz"),
        Path("/inputs/HG007_30x_R1.fastq.gz"),
        Path("/inputs/HG007_30x_R2.fastq.gz"),
    )

    samples = _read_tsv(out_dir / "samples.tsv")
    units = _read_tsv(out_dir / "units.tsv")
    plan = _read_tsv(out_dir / "contamination_plan.tsv")

    assert samples[0]["SAMPLEID"] == "HG001-HG007-contam-0p5pct"
    assert samples[0]["EXTERNAL_SAMPLE_ID"] == "HG001"
    assert units[0]["RUNID"] == "GIABCONTAMHG001HG00720260426"
    assert units[0]["EXPERIMENTID"] == "HG001-5x-HG007-0p5pct"
    assert plan[0]["primary_sample"] == "HG001"
    assert plan[0]["donor_sample"] == "HG007"
    assert plan[0]["primary_r1"] == "/inputs/HG001_30x_R1.fastq.gz"
    assert plan[0]["donor_r1"] == "/inputs/HG007_30x_R1.fastq.gz"


def test_synthetic_contamination_observed_summary(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "bin" / "util" / "summarize_contamination_expected_vs_observed.py",
        "contam_summary_under_test",
    )
    synthetic_root = tmp_path / "synthetic"
    results_root = tmp_path / "results"
    sample_id = "HG002-HG003-contam-5pct"
    result_sample = (
        results_root
        / f"GIABCONTAM20260425-{sample_id}-HG002-5x-HG003-5pct-1-D0-PCR-FREE-ILMN-NOVASEQ"
        / "align"
        / "sent"
        / "dmd"
        / "alignqc"
        / "contam"
    )
    gatk_path = result_sample / "gatk" / f"{sample_id}.sent.dmd.gatk.tsv"
    vb2_path = result_sample / "vb2" / "100k" / f"{sample_id}.sent.dmd.100k.vb2.tsv"
    synthetic_root.mkdir(parents=True)
    gatk_path.parent.mkdir(parents=True)
    vb2_path.parent.mkdir(parents=True)
    (synthetic_root / "contamination_plan.tsv").write_text(
        "sample_id\tcontamination_percent\n"
        f"{sample_id}\t5\n",
        encoding="utf-8",
    )
    gatk_path.write_text("SEQ_ID\tFREEMIX\nsample\t0.047\n", encoding="utf-8")
    vb2_path.write_text("SEQ_ID\tFREEMIX\nsample\t0.052\n", encoding="utf-8")

    rc = module.main(
        [
            "--synthetic-root",
            str(synthetic_root),
            "--results-root",
            str(results_root),
        ]
    )

    assert rc == 0
    rows = _read_tsv(synthetic_root / "observed_vs_expected_contam.tsv")
    assert rows[0]["expected_contamination_pct"] == "5"
    assert rows[0]["gatk_contamination_pct"] == "4.7"
    assert rows[0]["gatk_delta_pct"] == "-0.3"
    assert rows[0]["verifybamid2_contamination_pct"] == "5.2"
    assert rows[0]["verifybamid2_delta_pct"] == "0.2"


def test_relatedness_classification_interface_and_manifest_validation(tmp_path: Path) -> None:
    module = _load_module(
        REPO_ROOT / "workflow" / "scripts" / "relatedness_report.py",
        "relatedness_report_under_test",
    )
    manifest_path = tmp_path / "samples.tsv"
    manifest_path.write_text(
        "sample_id\tpath\tpath_type\tsex\tfamily_id\texternal_sample_id\n"
        "HG002\t/fsx/not-mounted/HG002.cram\tcram\tmale\ttrio\tKID\n"
        "HG003\t/fsx/not-mounted/HG003.cram\tcram\tmale\ttrio\tDAD\n"
        "HG004\t/fsx/not-mounted/HG004.cram\tcram\tfemale\ttrio\tMOM\n"
        "NA12878\t/fsx/not-mounted/NA12878.vcf.gz\tvcf\tfemale\tceph\tNA12878\n",
        encoding="utf-8",
    )
    manifest = module.load_manifest(manifest_path)
    assert list(manifest["sample_id"]) == ["HG002", "HG003", "HG004", "NA12878"]

    pairs = [
        {"sample_a": "HG002", "sample_b": "HG002", "relatedness": "0.99", "ibs0": "0"},
        {"sample_a": "KID", "sample_b": "DAD", "relatedness": "0.50", "ibs0": "0.5"},
        {"sample_a": "DAD", "sample_b": "MOM", "relatedness": "0.48", "ibs0": "12"},
        {"sample_a": "HG002", "sample_b": "NA12878", "relatedness": "0.02", "ibs0": "90"},
        {"sample_a": "MOM", "sample_b": "NA12878", "relatedness": "0.28", "ibs0": "4"},
    ]
    expected = module.load_expected(
        [
            {"samples": ["HG002", "HG003"], "relationship": "father_child"},
            {"samples": ["HG003", "HG004"], "relationship": "sibling"},
            {"samples": "HG002,NA12878", "relationship": "unrelated"},
            {"samples": "HG004,NA12878", "relationship": "unrelated"},
        ]
    )

    classified = module.classify_pairs(pairs, manifest, expected=expected)
    by_pair = {tuple(sorted([row.sample_a, row.sample_b])): row for row in classified}

    assert by_pair[("HG002", "HG002")].relationship == "duplicate_or_identical"
    assert by_pair[("HG002", "HG003")].relationship == "parent_child"
    assert by_pair[("HG003", "HG004")].relationship == "sibling_or_first_degree"
    assert by_pair[("HG002", "NA12878")].relationship == "unrelated"
    assert by_pair[("HG004", "NA12878")].relationship == "ambiguous"
    assert by_pair[("HG004", "NA12878")].status == "FAIL"
    assert "expected unrelated; observed ambiguous" in by_pair[("HG004", "NA12878")].note

    hash_prefixed_pairs = [
        {"#sample_a": "HG002", "sample_b": "HG003", "relatedness": "0.50", "ibs0": "0.5"}
    ]
    assert module.classify_pairs(hash_prefixed_pairs, manifest)[0].relationship == "parent_child"


def test_relatedness_rule_is_somalier_manifest_driven() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "relatedness_test_day.smk").read_text(
        encoding="utf-8"
    )

    assert 'configfile: "config/relatedness.yaml"' in text
    assert "samples_manifest" in text
    assert 'REPORT_DIR + "/relatedness_pairs_classified.tsv"' in text
    assert 'script:\n        "../scripts/relatedness_report.py"' in text
    assert "--genome-build" not in text
    assert "--unknown" not in text
    assert "-o {params.prefix}" not in text
    assert "--out-dir {params.out_dir}" in text
    assert "--sample-prefix" not in text
    assert "picard" not in text.lower()
    assert "conpair" not in text.lower()
