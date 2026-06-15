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
    snv_dir = f"{REPO}/results/day/hg38_broad/{SAMPLE}/align/pangenome_ug/spmd/snv/sentpg"
    conc = f"{snv_dir}/concordance"
    aggregate = f"{REPO}/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    tmux_log = f"/home/ubuntu/daylily-runs/{SESSION}/tmux.log"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        test "$(id -un)" = ubuntu
        command -v squeue >/dev/null
        echo "__POLL_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "__MARKERS__"
        grep -nE "__DAYOA_STAGE__=monolithic_concordance|__DAYOA_FAIL__=monolithic_concordance|RETURN CODE" {q(tmux_log)} | tail -n 20 || true
        echo "__QUEUE__"
        squeue -u ubuntu -o "%.18i %.12P %.50j %.2t %.10M %.60R" |
          grep -E "HG00340X-HG003-PILOT23ME-1-Z0383CG|sentpg|rtg_vcfeval|parse_vcfeval|produce_snv" || true
        echo "__VCF__"
        ls -lh {q(snv_dir)}/*.sentpg.snv.sort.vcf.gz {q(snv_dir)}/*.sentpg.snv.sort.vcf.gz.tbi
        echo "__CONCORDANCE_COUNTS__"
        echo "summary_count=$(find {q(conc)} -mindepth 2 -maxdepth 2 -type f -name summary.txt | wc -l | tr -d ' ')"
        echo "mqc_count=$(find {q(conc)} -mindepth 2 -maxdepth 2 -type f -name '*_concordance.mqc.tsv' | wc -l | tr -d ' ')"
        echo "done_count=$(find {q(conc)} -maxdepth 1 -type f -name concordance.done | wc -l | tr -d ' ')"
        find {q(conc)} -mindepth 2 -maxdepth 2 -type f -name '*_concordance.mqc.tsv' | sort
        echo "__DONE__"
        ls -lh {q(conc)}/concordance.done
        echo "__AGGREGATE__"
        ls -lh {q(aggregate)}
        head -n 5 {q(aggregate)}
        echo "__DAY_CMD_TAIL__"
        tail -n 8 {q(REPO)}/day_cmd.log
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
            comment="Final monolithic sentpg concordance check",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
