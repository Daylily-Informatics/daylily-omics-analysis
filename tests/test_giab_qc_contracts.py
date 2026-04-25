from __future__ import annotations

import csv
import importlib.util
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
GIAB7_IDS = ["HG001", "HG002", "HG003", "HG004", "HG005", "HG006", "HG007"]
GIAB_30X_FASTQ_ROOT = (
    "/fsx/data/genomic_data/organism_reads/H_sapiens/giab/"
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
            return _load_module(path, "synthetic_contamination_under_test")
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
            "{sample}.{alnr}.{ddup}.vb2.tsv",
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
    assert "ddup=DDUP" in target_text


def test_gatk_contam_env_includes_cram_compat_tools() -> None:
    text = (REPO_ROOT / "workflow" / "envs" / "gatkcontam_v0.1.yaml").read_text(
        encoding="utf-8"
    )

    assert "gatk4" in text
    assert "htslib" in text
    assert "samtools" in text


def test_gatk_cram_compat_parses_htsfile_tab_delimited_output() -> None:
    text = (REPO_ROOT / "bin" / "util" / "gatk_cram_compat.sh").read_text(
        encoding="utf-8"
    )

    assert "sed -E 's/^[^:]*:[[:space:]]*//'" in text
    assert "version[[:space:]]+" in text
    assert "awk -F': '" not in text


def test_verifybamid2_uses_svd_prefix_not_sites_only_refvcf() -> None:
    rule_text = (REPO_ROOT / "workflow" / "rules" / "verifybamid2_contam.smk").read_text(
        encoding="utf-8"
    )

    assert "--SVDPrefix {params.db_prefix}" in rule_text
    assert "--RefVCF {params.site_vcf}" not in rule_text

    for config_path in (
        "config/supporting_files/hg38_supporting_files.yaml",
        "config/supporting_files/hg38_broad_supporting_files.yaml",
    ):
        config_text = (REPO_ROOT / config_path).read_text(encoding="utf-8")
        assert "chr20_verbam/chr20.random1000.vcf.gz" in config_text


def test_synthetic_contamination_manifest_levels_and_count_calculations(tmp_path: Path) -> None:
    module = _load_synthetic_contam_module()

    parsed_levels = [float(level) for level in module.parse_levels(module.DEFAULT_LEVELS)]
    assert parsed_levels == SYNTHETIC_LEVELS_PCT
    args_defaults = module.parse_args([])
    assert args_defaults.primary_coverage == "30"
    assert args_defaults.primary_r1.endswith("/HG002_30x_R1.fastq.gz")
    assert args_defaults.primary_r2.endswith("/HG002_30x_R2.fastq.gz")

    args = SimpleNamespace(
        levels="0.1,5",
        output_dir="/fsx/scratch/dayoa_qc_contam/giab_hg002_hg003_5x_20260425",
        sample_prefix="HG002_HG003_contam",
        target_coverage="5",
        primary_coverage="5",
        donor_coverage="30",
    )
    out_dir, rows = module.build_plan(args)
    assert str(out_dir) == args.output_dir
    assert [row["sample_id"] for row in rows] == [
        "HG002_HG003_contam_0p1pct",
        "HG002_HG003_contam_5pct",
    ]
    assert rows[0]["primary_fraction"] == module.Decimal("0.999")
    assert rows[0]["donor_fraction"] == module.Decimal("0.0001666666666666666666666666667")
    assert rows[1]["primary_fraction"] == module.Decimal("0.95")
    assert rows[1]["donor_fraction"] == module.Decimal("0.008333333333333333333333333333")

    manifest_args = SimpleNamespace(
        dry_run=False,
        truth_dir="/truth/HG002/",
        run_id="GIABCONTAM20260425",
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
        "HG002_HG003_contam_0p1pct",
        "HG002_HG003_contam_5pct",
    ]
    assert [row["SUBSAMPLE_PCT"] for row in units] == ["", ""]
    assert [row["contamination_percent"] for row in plan] == ["0.1", "5"]
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


def test_relatedness_classification_interface_and_manifest_validation(tmp_path: Path) -> None:
    pd = pytest.importorskip("pandas")
    pytest.importorskip("jinja2")
    module = _load_module(
        REPO_ROOT / "workflow" / "scripts" / "relatedness_report.py",
        "relatedness_report_under_test",
    )
    manifest_path = tmp_path / "samples.tsv"
    manifest_path.write_text(
        "sample_id\tpath\tpath_type\tsex\tfamily_id\n"
        "HG002\t/fsx/not-mounted/HG002.cram\tcram\tmale\ttrio\n"
        "HG003\t/fsx/not-mounted/HG003.cram\tcram\tmale\ttrio\n"
        "HG004\t/fsx/not-mounted/HG004.cram\tcram\tfemale\ttrio\n"
        "NA12878\t/fsx/not-mounted/NA12878.vcf.gz\tvcf\tfemale\tceph\n",
        encoding="utf-8",
    )
    manifest = module.load_manifest(manifest_path)
    assert list(manifest["sample_id"]) == ["HG002", "HG003", "HG004", "NA12878"]

    pairs = pd.DataFrame(
        [
            {"sample_a": "HG002", "sample_b": "HG002", "relatedness": "0.99", "ibs0": "0"},
            {"sample_a": "HG002", "sample_b": "HG003", "relatedness": "0.50", "ibs0": "0.5"},
            {"sample_a": "HG003", "sample_b": "HG004", "relatedness": "0.48", "ibs0": "12"},
            {"sample_a": "HG002", "sample_b": "NA12878", "relatedness": "0.02", "ibs0": "90"},
            {"sample_a": "HG004", "sample_b": "NA12878", "relatedness": "0.28", "ibs0": "4"},
        ]
    )
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


def test_relatedness_rule_is_somalier_manifest_driven() -> None:
    text = (REPO_ROOT / "workflow" / "rules" / "relatedness_test_day.smk").read_text(
        encoding="utf-8"
    )

    assert 'configfile: "config/relatedness.yaml"' in text
    assert "samples_manifest" in text
    assert 'REPORT_DIR + "/relatedness_pairs_classified.tsv"' in text
    assert 'script:\n        "../scripts/relatedness_report.py"' in text
    assert "picard" not in text.lower()
    assert "conpair" not in text.lower()
