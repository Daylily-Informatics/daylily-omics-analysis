#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


INSTANCE_ID = "i-05b2743c3c3fffa93"
REGION = "us-west-2"
PROFILE = "lsmc"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script(*, session: str, lines: int) -> str:
    repo_dir = f"/fsx/analysis_results/ubuntu/{session}/daylily-omics-analysis"
    tmux_log = f"/home/ubuntu/daylily-runs/{session}/tmux.log"
    sample = "HG00340X-HG003-PILOT23ME-1-Z0383CGATCACAAGCTGAT-PF-UG-ULTIMA"
    sentpgs_dir = f"{repo_dir}/results/day/hg38_broad/{sample}/align/pangenome_ug/spmd/snv/sentpgs"
    final_vcf = f"{sentpgs_dir}/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        REPO_DIR={q(repo_dir)}
        TMUX_LOG={q(tmux_log)}
        SENTPGS_DIR={q(sentpgs_dir)}
        FINAL_VCF={q(final_vcf)}
        echo "__SESSION__=$SESSION"
        echo "__TMUX_EXISTS__"
        if tmux has-session -t "$SESSION" 2>/dev/null; then echo yes; else echo no; fi
        echo "__REPO_HEAD__"
        git -C "$REPO_DIR" rev-parse HEAD || true
        echo "__DAYOA_MARKERS__"
        grep -nE "__DAYOA_STAGE__|__DAYOA_FAIL__|RETURN CODE|AUTO-CONFIG" "$TMUX_LOG" | tail -n 80 || true
        echo "__SQUEUE_PANGENOME__"
        squeue -u ubuntu -o "%.18i %.12P %.36j %.2t %.10M %.40R" | grep -E "sentieon_pangenome_ug|sentpgs|rtg_vcfeval|parse_vcfeval|produce_snv|produce_pangenome" || true
        echo "__SQUEUE_ALL_TAIL__"
        squeue -u ubuntu -o "%.18i %.12P %.36j %.2t %.10M %.40R" | tail -n 40 || true
        echo "__SENTPGS_OUTPUTS__"
        if [[ -d "$SENTPGS_DIR" ]]; then
          find "$SENTPGS_DIR" -maxdepth 4 -type f \\( -name "*.vcf.gz" -o -name "*.tbi" -o -name "concordance.done" -o -name "*.mqc.tsv" \\) | sort | sed -n '1,120p'
        else
          echo "missing $SENTPGS_DIR"
        fi
        echo "__FINAL_VCF__"
        ls -lh "$FINAL_VCF" "$FINAL_VCF.tbi" 2>/dev/null || true
        echo "__PANGENOME_LOG_TAILS__"
        if [[ -d "$SENTPGS_DIR/log" ]]; then
          find "$SENTPGS_DIR/log" -type f -name "*.log" | sort | tail -n 5 | while read -r log; do
            echo "--- $log"
            tail -n {int(lines)} "$log" || true
          done
        fi
        echo "__TMUX_LOG_TAIL__"
        tail -n {int(lines)} "$TMUX_LOG"
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    parser.add_argument("--lines", type=int, default=60)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session, lines=args.lines),
            profile=PROFILE,
            timeout=180,
            comment=f"Status sharded live run {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
