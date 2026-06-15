#!/usr/bin/env python3
from __future__ import annotations

import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


INSTANCE_ID = "i-05b2743c3c3fffa93"
REGION = "us-west-2"
PROFILE = "lsmc"
SESSION = "altair_hg003_ultima_pg_20260615T052434Z"
REMOTE_REPO = (
    "/fsx/analysis_results/ubuntu/"
    "altair_hg003_ultima_pg_20260615T052434Z/daylily-omics-analysis"
)
SAMPLE = "HG00340X-HG003-PILOT23ME-1-Z0383CGATCACAAGCTGAT-PF-UG-ULTIMA"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script() -> str:
    align_dir = f"{REMOTE_REPO}/results/day/hg38_broad/{SAMPLE}/align/ug"
    sample_cram = f"{align_dir}/{SAMPLE}.cram"
    sample_crai = f"{sample_cram}.crai"
    pg_dir = (
        f"{REMOTE_REPO}/results/day/hg38_broad/{SAMPLE}/align/"
        f"pangenome_ug/spmd/snv/sentpg"
    )
    pg_log = f"{pg_dir}/log/{SAMPLE}.pangenome_ug.spmd.sentpg.log"
    pg_vcf = f"{pg_dir}/{SAMPLE}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz"
    slurm_dir = f"{REMOTE_REPO}/logs/slurm/sentieon_pangenome_ug"
    slurm_out = f"{slurm_dir}/sentieon_pangenome_ug.{SAMPLE}.1.out"
    slurm_err = f"{slurm_dir}/sentieon_pangenome_ug.{SAMPLE}.1.err"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(SESSION)}
        LOG=/home/ubuntu/daylily-runs/{q(SESSION)}/tmux.log
        CRAM={q(sample_cram)}
        CRAI={q(sample_crai)}
        PG_LOG={q(pg_log)}
        PG_VCF={q(pg_vcf)}
        SLURM_OUT={q(slurm_out)}
        SLURM_ERR={q(slurm_err)}

        echo "__STATUS_AT__=$(date --iso-8601=seconds)"
        if timeout 5s tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "__TMUX_EXISTS__=yes"
        else
          echo "__TMUX_EXISTS__=no"
        fi

        echo "__SQUEUE_RELEVANT__"
        timeout 20s squeue -u ubuntu -o "%.18i %.12P %.20j %.2t %.10M %.40R" \
          | awk 'NR == 1 || $1 == "48" || $1 == "49" || $3 ~ /pre_prep|sentieon_pangenome|pangenome|dnascope/' || true

        echo "__SACCT_48__"
        timeout 20s sacct -j 48 --format=JobID,JobName%24,State,ExitCode,Elapsed,NodeList -P 2>/dev/null || true

        echo "__SCONTROL_JOB_49__"
        timeout 20s scontrol show job 49 || true

        echo "__SCONTROL_NODE_49__"
        NODE=$(timeout 20s squeue -j 49 -h -o "%N" 2>/dev/null || true)
        if [[ -n "$NODE" && "$NODE" != "(None)" ]]; then
          timeout 20s scontrol show node "$NODE" || true
        else
          echo "no node assigned"
        fi

        echo "__EXPECTED_ALIGN_LINKS__"
        for f in "$CRAM" "$CRAI"; do
          if [[ -e "$f" || -L "$f" ]]; then
            ls -lh "$f"
            readlink "$f" || true
          else
            echo "missing $f"
          fi
        done

        echo "__PANGENOME_OUTPUT__"
        if [[ -e "$PG_VCF" || -L "$PG_VCF" ]]; then
          ls -lh "$PG_VCF" "$PG_VCF.tbi" 2>/dev/null || true
        else
          echo "missing $PG_VCF"
        fi

        echo "__PANGENOME_LOG_TAIL__"
        if [[ -f "$PG_LOG" ]]; then
          timeout 20s tail -n 60 "$PG_LOG" || true
        else
          echo "missing $PG_LOG"
        fi

        echo "__PANGENOME_SLURM_STDOUT_TAIL__"
        if [[ -f "$SLURM_OUT" ]]; then
          timeout 20s tail -n 40 "$SLURM_OUT" || true
        else
          echo "missing $SLURM_OUT"
        fi

        echo "__PANGENOME_SLURM_STDERR_TAIL__"
        if [[ -f "$SLURM_ERR" ]]; then
          timeout 20s tail -n 40 "$SLURM_ERR" || true
        else
          echo "missing $SLURM_ERR"
        fi

        echo "__TMUX_MARKERS__"
        if [[ -f "$LOG" ]]; then
          timeout 20s grep -E "__DAYOA_|Submitted job|Finished job|Error|FAILED|sentieon_pangenome_ug|pre_prep_ultima_cram" "$LOG" | tail -n 80 || true
        else
          echo "missing $LOG"
        fi
        """
    ).strip()


def main() -> None:
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(),
            profile=PROFILE,
            timeout=180,
            comment=f"Read-only status for {SESSION}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
