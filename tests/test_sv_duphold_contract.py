from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    full_path = REPO_ROOT / path
    assert full_path.exists(), path
    return full_path.read_text(encoding="utf-8")


def test_dysgu_is_retired_from_active_workflow() -> None:
    snakefile = _read("workflow/Snakefile")
    active_includes = [
        line.strip()
        for line in snakefile.splitlines()
        if line.strip().startswith("include:")
    ]
    common = _read("workflow/rules/common.smk")

    assert 'include: "rules/dysgu_sv.smk"' not in active_includes
    assert '# include: "rules/dysgu_sv.smk"' in snakefile
    assert "SUPPORTED_SV_CALLERS" in common
    assert '"manta"' in common
    assert '"tiddit"' in common
    assert "RETIRED_SV_CALLERS" in common
    assert '"dysgu"' in common
    assert "Dysgu is retired from active workflow rules" in common
    assert "The requested SV annotation target requires --config sv_callers=[...]" in common


def test_profile_templates_do_not_expose_dysgu() -> None:
    for template in (
        "config/day_profiles/local/templates/rule_config.yaml",
        "config/day_profiles/slurm/templates/rule_config.yaml",
    ):
        text = _read(template)
        assert "dysgu" not in text
        assert "dedupers=['dmd']" in text
        assert "sv_callers=['manta','tiddit']" in text


def test_duphold_uses_cram_inputs_and_explicit_target() -> None:
    duphold = _read("workflow/rules/duphold.smk")

    assert 'rule produce_duphold:' in duphold
    assert 'rule produce_all_svs:' in duphold
    assert 'output:\n        MDIR + "logs/duphold.done"' in duphold
    assert 'input:\n        MDIR + "logs/duphold.done"' in duphold
    assert 'MDIR + "logs/all_svVCF_dupheld.done"' in duphold
    assert "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram" in duphold
    assert "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai" in duphold
    assert "-b {input.cram}" in duphold
    assert "mrkdup.sort.bam" not in duphold
    assert "config['dysgu']" not in duphold
