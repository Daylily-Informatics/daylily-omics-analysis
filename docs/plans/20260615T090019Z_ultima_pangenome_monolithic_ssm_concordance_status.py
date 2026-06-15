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
SAMPLE = "HG00340X-HG003-PILOT23ME-1-Z0383CGATCACAAGCTGAT-PF-UG-ULTIMA"
REPO = f"/fsx/analysis_results/ubuntu/{SESSION}/daylily-omics-analysis"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script() -> str:
    sentpg_dir = (
        f"{REPO}/results/day/hg38_broad/{SAMPLE}/align/pangenome_ug/spmd/snv/sentpg"
    )
    concordance_dir = f"{sentpg_dir}/concordance"
    tmux_log = f"/home/ubuntu/daylily-runs/{SESSION}/tmux.log"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        command -v squeue >/dev/null
        SESSION={q(SESSION)}
        TMUX_LOG={q(tmux_log)}
        SENTPG_DIR={q(sentpg_dir)}
        CONCORDANCE_DIR={q(concordance_dir)}
        echo "__POLL_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "__TMUX_EXISTS__"
        if tmux has-session -t "$SESSION" 2>/dev/null; then echo yes; else echo no; fi
        echo "__MARKERS__"
        grep -nE "__DAYOA_STAGE__|__DAYOA_FAIL__|RETURN CODE|AUTO-CONFIG" "$TMUX_LOG" | tail -n 40 || true
        echo "__QUEUE__"
        squeue -u ubuntu -o "%.18i %.12P %.50j %.2t %.10M %.60R" |
          grep -E "sentpg|rtg_vcfeval|parse_vcfeval|produce_snv|prep_for_concordance" || true
        echo "__SENTPG_INPUT__"
        ls -lh "$SENTPG_DIR"/*.sentpg.snv.sort.vcf.gz "$SENTPG_DIR"/*.sentpg.snv.sort.vcf.gz.tbi 2>/dev/null || true
        echo "__CONCORDANCE_OUTPUTS__"
        if [[ -d "$CONCORDANCE_DIR" ]]; then
          find "$CONCORDANCE_DIR" -maxdepth 4 -type f \\( -name 'concordance.done' -o -name '*.mqc.tsv' -o -name 'summary.txt' -o -name 'done.txt' -o -name '*.log' \\) -printf '%TY-%Tm-%TdT%TH:%TM:%TS %s %p\\n' | sort | sed -n '1,160p'
        else
          echo "missing $CONCORDANCE_DIR"
        fi
        echo "__LATEST_LOG_TAIL__"
        tail -n 40 "$TMUX_LOG"
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
            comment="Poll monolithic sentpg concordance",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
