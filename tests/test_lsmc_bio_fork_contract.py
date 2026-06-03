from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

_OLD_ORG = "Daylily-" + "Informatics"

FORBIDDEN_ACTIVE_REFERENCES = (
    f"{_OLD_ORG}/daylily-omics-analysis",
    f"{_OLD_ORG}/daylily-ephemeral-cluster",
    f"github.com:{_OLD_ORG}/daylily-omics-analysis",
    f"github.com:{_OLD_ORG}/daylily-ephemeral-cluster",
    f"github.com/{_OLD_ORG}/daylily-omics-analysis",
    f"github.com/{_OLD_ORG}/daylily-ephemeral-cluster",
)

ACTIVE_PATHS = (
    "README.md",
    "config/daylily_cli_global.yaml",
    "docs/catalog_of_tools.md",
    "scripts/setup_main_tests.sh",
    "bin/util/launch_1x_3x_all_workflows.sh",
    "workflow/rules/help.smk",
    "workflow/rules/multiqc_singleton.smk",
    "workflow/rules/expansionhunter.smk",
    "workflow/rules/multiqc_final_wgs.smk",
    "workflow/rules/multiqc_for_raw_fastqs.smk",
)


def test_active_surfaces_do_not_reference_daylily_informatics_dayoa_or_dyec() -> None:
    offenders: list[str] = []
    for relative_path in ACTIVE_PATHS:
        text = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        for forbidden in FORBIDDEN_ACTIVE_REFERENCES:
            if forbidden in text:
                offenders.append(f"{relative_path}: {forbidden}")

    assert not offenders


def test_lsmc_bio_repo_identity_is_declared() -> None:
    config_text = (REPO_ROOT / "config/daylily_cli_global.yaml").read_text(encoding="utf-8")
    readme_text = (REPO_ROOT / "README.md").read_text(encoding="utf-8")

    assert "https://github.com/lsmc-bio/daylily-omics-analysis.git" in config_text
    assert "git@github.com:lsmc-bio/daylily-omics-analysis.git" in config_text
    assert "https://github.com/lsmc-bio/daylily-ephemeral-cluster" in readme_text
