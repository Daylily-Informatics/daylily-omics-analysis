from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "workflow" / "scripts" / "alignment_preservation_audit.py"


def _load_module():
    spec = importlib.util.spec_from_file_location(
        "alignment_preservation_audit_under_test", SCRIPT_PATH
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _yaml(path: str) -> dict:
    return yaml.safe_load((REPO_ROOT / path).read_text(encoding="utf-8"))


def test_alignment_preservation_audit_rule_config_and_targets() -> None:
    snakefile = _read("workflow/Snakefile")
    rule = _read("workflow/rules/alignment_preservation_audit.smk")
    sentmm2 = _read("workflow/rules/sentmm2_align_sort.smk")
    sentmm2ont = _read("workflow/rules/sentmm2ont_align_sort.smk")
    strobe = _read("workflow/rules/strobe_align_sort.smk")

    assert 'include: "rules/alignment_preservation_audit.smk"' in snakefile
    assert "rule produce_alignment_preservation_audit:" in rule
    assert "workflow/scripts/alignment_preservation_audit.py audit" in rule
    assert "alignment_preservation_audit.md" in rule
    assert "alignment_preservation_audit.tsv" in rule

    for profile in ("local", "slurm"):
        cfg = _yaml(f"config/day_profiles/{profile}/templates/rule_config.yaml")
        assert (
            cfg["sentmm2_align_sort"]["minimap2_opts"].strip()
            == "-ax map-hifi -Y --secondary-seq"
        )
        assert (
            cfg["sentmm2ont_align_sort"]["minimap2_opts"].strip()
            == "-ax map-ont -Y --secondary-seq"
        )
        assert cfg["alignment_preservation_audit"]["env_yaml"] == "../envs/samtools_v0.1.yaml"

    for text in (sentmm2, sentmm2ont, strobe):
        assert "samtools view" in text
        assert "-c -f 0x900" in text
        assert "secondary/supplementary records before samtools fastq extraction" in text

    assert "samtools fastq -@ 4 -F 0x900 -T MM,ML" in sentmm2
    assert "samtools fastq -@ 4 -F 0x900 -T MM,ML" in sentmm2ont
    assert "samtools fastq --reference {params.huref}" in strobe
    assert "-F 0x900 {input.cram}" in strobe


def test_static_audit_classifies_known_producers_without_failures(tmp_path: Path) -> None:
    module = _load_module()
    out_md = tmp_path / "audit.md"
    out_tsv = tmp_path / "audit.tsv"

    rc = module.run_audit(
        SimpleNamespace(repo_root=REPO_ROOT, out_md=out_md, out_tsv=out_tsv)
    )

    assert rc == 0
    tsv = out_tsv.read_text(encoding="utf-8")
    markdown = out_md.read_text(encoding="utf-8")
    assert "bwa_mem2_sort" in tsv
    assert "sentmm2_align_sort" in tsv
    assert "doppelmark_dups" in tsv
    assert "intentional_subset" in tsv
    assert "out_of_scope_intermediate" in tsv
    assert "manifest downsample settings are explicit pre-alignment transforms" in tsv
    assert "Alignment BAM/CRAM Preservation Audit" in markdown


def test_minimap2_option_enforcement_reports_bad_fixture(tmp_path: Path) -> None:
    module = _load_module()
    for profile in ("local", "slurm"):
        config_dir = tmp_path / "config" / "day_profiles" / profile / "templates"
        config_dir.mkdir(parents=True)
        (config_dir / "rule_config.yaml").write_text(
            "\n".join(
                [
                    "sentmm2_align_sort:",
                    '    minimap2_opts: " -ax map-hifi "',
                    "",
                ]
            ),
            encoding="utf-8",
        )

    problems = module._check_minimap2_opts(tmp_path, "sentmm2_align_sort")

    assert any("missing -Y" in problem for problem in problems)
    assert any("missing --secondary-seq" in problem for problem in problems)


def test_alignment_record_counts_detect_missing_seq_and_hard_clip(monkeypatch) -> None:
    module = _load_module()

    def fake_records(path, reference=None):
        del path, reference
        return iter(
            [
                ["read1", "0", "chr1", "1", "60", "10M", "*", "0", "0", "ACGT", "*"],
                ["read2", "0", "chr1", "2", "60", "5H10M", "*", "0", "0", "ACGT", "*"],
                ["read3", "0", "chr1", "3", "60", "10M", "*", "0", "0", "*", "*"],
            ]
        )

    monkeypatch.setattr(module, "_iter_sam_records", fake_records)

    counts = module.alignment_record_counts(Path("out.bam"))

    assert counts == {"total": 3, "primary": 3, "missing_seq": 1, "hard_clipped": 1}


def test_validate_read_set_raises_on_residual(monkeypatch, tmp_path: Path) -> None:
    module = _load_module()
    fastq = tmp_path / "reads.fq"
    fastq.write_text("@r1\nACGT\n+\nIIII\n", encoding="utf-8")

    monkeypatch.setattr(module, "alignment_primary_read_keys", lambda path, reference=None: set())
    monkeypatch.setattr(
        module,
        "alignment_record_counts",
        lambda path, reference=None: {
            "total": 0,
            "primary": 0,
            "missing_seq": 0,
            "hard_clipped": 0,
        },
    )

    with pytest.raises(module.AuditError, match="read-set mismatch"):
        module.validate_read_set([(fastq, "1")], tmp_path / "out.bam", None)


def test_dedup_count_preservation_raises_on_record_loss(monkeypatch) -> None:
    module = _load_module()

    def fake_counts(path, reference=None):
        del reference
        if str(path) == "pre.bam":
            return {"total": 10, "primary": 8, "missing_seq": 0, "hard_clipped": 0}
        return {"total": 9, "primary": 8, "missing_seq": 0, "hard_clipped": 0}

    monkeypatch.setattr(module, "alignment_record_counts", fake_counts)

    with pytest.raises(module.AuditError, match="dedup count mismatch"):
        module.validate_dedup_counts(Path("pre.bam"), Path("post.cram"), None)


def test_guard_ubam_raises_when_secondary_or_supplementary_present(monkeypatch) -> None:
    module = _load_module()

    def fake_run(cmd, text, stdout, stderr, check):
        del cmd, text, stdout, stderr, check
        return SimpleNamespace(returncode=0, stdout="2\n", stderr="")

    monkeypatch.setattr(module.subprocess, "run", fake_run)

    with pytest.raises(module.AuditError, match="secondary/supplementary records"):
        module.fail_if_secondary_or_supplementary(Path("input.bam"))
