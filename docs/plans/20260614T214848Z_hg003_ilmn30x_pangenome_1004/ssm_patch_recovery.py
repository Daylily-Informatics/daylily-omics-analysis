#!/usr/bin/env python3
from __future__ import annotations

import sys
import textwrap
from pathlib import Path

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import (
    SsmCommandFailedError,
    resolve_headnode_instance_id,
    run_shell,
    wait_for_ssm_online,
    write_remote_text,
)


CLUSTER = "dyecX4"
REGION = "us-west-2"
PROFILE = "lsmc"
REPO_ROOT = Path("/Users/jmajor/projects/lsmc/daylily-omics-analysis")
ANALYSIS_DIRS = [
    "/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/daylily-omics-analysis",
    "/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/daylily-omics-analysis",
]
SOURCE_FILES = [
    "workflow/rules/alignstats.smk",
    "workflow/rules/alignstats_compile.smk",
    "workflow/rules/rtg_vcfeval.smk",
    "workflow/scripts/parse-vcfeval-summary.py",
]
REMOTE_SOURCE_FILES = {
    "workflow/rules/alignstats.smk": "/tmp/dayoa_recovery_alignstats.smk",
    "workflow/rules/alignstats_compile.smk": "/tmp/dayoa_recovery_alignstats_compile.smk",
    "workflow/rules/rtg_vcfeval.smk": "/tmp/dayoa_recovery_rtg_vcfeval.smk",
    "workflow/scripts/parse-vcfeval-summary.py": "/tmp/dayoa_recovery_parse-vcfeval-summary.py",
}
REMOTE_CONFIG_PATCH = "/tmp/dayoa_recovery_patch_config.py"
CONFIG_PATCH_SCRIPT = """\
from pathlib import Path
import os

p = Path(os.environ["D"]) / "config/day_profiles/slurm/rule_config.yaml"
lines = p.read_text().splitlines()
section = None
out = []
for line in lines:
    stripped = line.strip()
    if line and not line.startswith((" ", "-")) and stripped.endswith(":"):
        section = stripped[:-1]
    if section == "alignstats" and stripped.startswith("mem_mb:"):
        line = "  mem_mb: 250000"
    elif section == "rtg_vcfeval" and stripped.startswith("mem_mb:"):
        line = "  mem_mb: 650000"
    elif section == "rtg_vcfeval" and stripped.startswith("parse_mem_mb:"):
        line = "  parse_mem_mb: 128000"
    elif section == "rtg_vcfeval" and stripped.startswith("partition:"):
        line = "  partition: i384nvme,i192hugenvme"
    elif section == "rtg_vcfeval" and stripped.startswith("partition_other:"):
        line = "  partition_other: i384nvme,i192hugenvme"
    out.append(line)
p.write_text("\\n".join(out) + "\\n")
"""


def main() -> None:
    target = resolve_headnode_instance_id(CLUSTER, REGION, profile=PROFILE)
    wait_for_ssm_online(target.instance_id, REGION, profile=PROFILE, timeout=120)

    for rel_path, remote_tmp in REMOTE_SOURCE_FILES.items():
        write_remote_text(
            target.instance_id,
            REGION,
            remote_tmp,
            (REPO_ROOT / rel_path).read_text(encoding="utf-8"),
            profile=PROFILE,
        )
    write_remote_text(
        target.instance_id,
        REGION,
        REMOTE_CONFIG_PATCH,
        CONFIG_PATCH_SCRIPT,
        profile=PROFILE,
    )

    analysis_args = " ".join(ANALYSIS_DIRS)
    copy_commands = "\n".join(
        f"          cp {tmp_path} \"$d/{rel_path}\""
        for rel_path, tmp_path in REMOTE_SOURCE_FILES.items()
    )
    remote_script = textwrap.dedent(
        f"""
        set -euo pipefail
        for d in {analysis_args}; do
{copy_commands}
          D="$d" python {REMOTE_CONFIG_PATCH}
          echo "===== $d patched ====="
          grep -n '^alignstats:' -A9 "$d/config/day_profiles/slurm/rule_config.yaml"
          grep -n '^rtg_vcfeval:' -A10 "$d/config/day_profiles/slurm/rule_config.yaml"
          grep -n 'mem_mb=config\\["alignstats"\\]\\["mem_mb"\\]' "$d/workflow/rules/alignstats.smk"
          grep -n 'done=f"{{MDIR}}logs/produce_alignstats.done"' "$d/workflow/rules/alignstats_compile.smk"
          grep -n 'touch {{log}}; touch {{output.done}}' "$d/workflow/rules/alignstats_compile.smk"
          grep -n 'mem_mb=config\\["rtg_vcfeval"\\]\\["mem_mb"\\]' "$d/workflow/rules/rtg_vcfeval.smk"
          grep -n 'os.makedirs(os.path.dirname(new_vcf_n), exist_ok=True)' "$d/workflow/scripts/parse-vcfeval-summary.py"
          cd "$d" && python -m py_compile workflow/scripts/parse-vcfeval-summary.py
        done
        """
    ).strip()

    try:
        result = run_shell(
            target.instance_id,
            REGION,
            remote_script,
            profile=PROFILE,
            timeout=300,
            comment="Patch HG003 pangenome recovery resources and parser",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
