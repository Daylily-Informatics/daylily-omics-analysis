from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SLURM_RULE_CONFIG = REPO_ROOT / "config/day_profiles/slurm/templates/rule_config.yaml"
NVME_PARTITION = "bcl2fq-i384-nvme-test"


CALLER_SECTIONS = {
    "clair3": ("partition", "partition_other"),
    "deepvariant": ("partition", "partition_other"),
    "deepvariant_1_9_roche": ("partition", "partition_other"),
    "deepsomatic": ("partition", "partition_other"),
    "mutect2": ("partition", "partition_other"),
    "dysgu": ("partition",),
    "expansionhunter": ("partition",),
    "longtr": ("partition",),
    "genetocn": ("partition",),
    "lofreq2": ("partition",),
    "parascopy": ("partition",),
    "aiv": ("partition", "partition_other"),
    "varn": ("partition", "partition_other"),
    "senttn": ("partition", "partition_other"),
    "manta": ("partition",),
    "octopus": ("partition",),
    "sentdhio": ("partition",),
    "sentdhuo": ("partition",),
    "sentdhip": ("partition",),
    "sentdhup": ("partition",),
    "sentdhipm": ("partition",),
    "sentdhupm": ("partition",),
    "sentdhrom": ("partition",),
    "sentdhrpm": ("partition",),
    "sentdhiomr": ("partition",),
    "sentdhipmr": ("partition",),
    "sentdhupmr": ("partition",),
    "sentdhuomr": ("partition",),
    "sentdug": ("partition",),
    "sentdpb": ("partition",),
    "sentdont": ("partition",),
    "sentD": ("partition",),
    "cgt7p": ("partition",),
    "sentieon_haplocaller": ("partition",),
    "sentieon_dnascope": ("partition",),
    "sentieon_pangenome_sr": ("partition",),
    "sentieon_pangenome_ug": ("partition",),
    "sentieon_gatk": ("partition", "partition_other"),
    "tiddit": ("partition",),
    "surveyor": ("partition",),
    "svaba": ("partition",),
    "svim_asm": ("partition",),
    "roche_gatk_haplotypecaller": ("partition",),
    "roche_filter_variants": ("partition",),
}


def _partition_list(value: str) -> list[str]:
    return [part.strip() for part in str(value).split(",") if part.strip()]


def test_slurm_hybrid_snv_sv_callers_try_nvme_partition_first() -> None:
    cfg = yaml.safe_load(SLURM_RULE_CONFIG.read_text(encoding="utf-8"))

    missing = []
    wrong_first = []
    for section, keys in CALLER_SECTIONS.items():
        for key in keys:
            value = cfg.get(section, {}).get(key)
            parts = _partition_list(value)
            if not parts:
                missing.append(f"{section}.{key}")
            elif parts[0] != NVME_PARTITION:
                wrong_first.append(f"{section}.{key}={value}")

    assert not missing, "Missing caller partition config(s): " + ", ".join(missing)
    assert not wrong_first, (
        "Caller partitions must try bcl2fq-i384-nvme-test first: "
        + ", ".join(wrong_first)
    )
