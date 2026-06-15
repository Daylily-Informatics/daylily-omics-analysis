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
SAMPLE = "HG00340X-HG003-PILOT23ME-1-Z0383CGATCACAAGCTGAT-PF-UG-ULTIMA"


def q(value: str) -> str:
    return shlex.quote(value)


def remote_script(*, session: str) -> str:
    repo_dir = f"/fsx/analysis_results/ubuntu/{session}/daylily-omics-analysis"
    tmux_log = f"/home/ubuntu/daylily-runs/{session}/tmux.log"
    sentpgs_dir = (
        f"{repo_dir}/results/day/hg38_broad/{SAMPLE}/align/pangenome_ug/spmd/snv/sentpgs"
    )
    final_vcf = f"{sentpgs_dir}/{SAMPLE}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz"
    marker = f"{repo_dir}/gatheredall.pangenome_ug_sharded"
    benchmark_summary = f"{repo_dir}/results/day/hg38_broad/reports/benchmarks_summary.tsv"
    return textwrap.dedent(
        f"""
        set -euo pipefail
        SESSION={q(session)}
        REPO_DIR={q(repo_dir)}
        TMUX_LOG={q(tmux_log)}
        SENTPGS_DIR={q(sentpgs_dir)}
        FINAL_VCF={q(final_vcf)}
        MARKER={q(marker)}
        BENCHMARK_SUMMARY={q(benchmark_summary)}

        test "$(id -un)" = ubuntu
        command -v squeue >/dev/null
        test -d "$REPO_DIR"
        test -f "$TMUX_LOG"

        echo "__POLL_UTC__=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "__TMUX_EXISTS__=yes"
        else
          echo "__TMUX_EXISTS__=no"
        fi
        echo "__REPO_HEAD__=$(git -C "$REPO_DIR" rev-parse HEAD)"
        echo "__LATEST_MARKERS__"
        grep -nE "__DAYOA_STAGE__|__DAYOA_FAIL__|RETURN CODE|AUTO-CONFIG" "$TMUX_LOG" | tail -n 16 || true

        echo "__SHARD_QUEUE__"
        shard_jobs=$(squeue -h -u ubuntu -o "%i|%T|%M|%j|%R" | awk -F'|' '$4 ~ /sentieon_pangenome_ug_sharded/ {{print}}')
        if [[ -n "$shard_jobs" ]]; then
          printf "%s\\n" "$shard_jobs" | awk -F'|' '{{count[$2]++}} END {{for (state in count) print state "=" count[state]}}' | sort
          printf "%s\\n" "$shard_jobs" | sort -n
        else
          echo "no sentieon_pangenome_ug_sharded jobs in squeue"
        fi

        echo "__CONCORDANCE_QUEUE__"
        concordance_jobs=$(squeue -h -u ubuntu -o "%i|%T|%M|%j|%R" | awk -F'|' '$4 ~ /rtg_vcfeval|parse_vcfeval|produce_snv_concordances/ {{print}}')
        if [[ -n "$concordance_jobs" ]]; then
          printf "%s\\n" "$concordance_jobs" | sort -n
        else
          echo "no concordance jobs in squeue"
        fi

        echo "__OUTPUT_COUNTS__"
        if [[ -d "$SENTPGS_DIR/vcfs" ]]; then
          echo "shard_vcfs=$(find "$SENTPGS_DIR/vcfs" -mindepth 2 -maxdepth 2 -type f -name '*.snv.sort.vcf.gz' | wc -l | tr -d ' ')"
          echo "shard_tbis=$(find "$SENTPGS_DIR/vcfs" -mindepth 2 -maxdepth 2 -type f -name '*.snv.sort.vcf.gz.tbi' | wc -l | tr -d ' ')"
        else
          echo "shard_vcfs=0"
          echo "shard_tbis=0"
        fi
        if [[ -f "$FINAL_VCF" ]]; then
          stat -c "final_vcf=%n bytes=%s mtime=%y" "$FINAL_VCF"
        else
          echo "final_vcf=missing"
        fi
        if [[ -f "$FINAL_VCF.tbi" ]]; then
          stat -c "final_tbi=%n bytes=%s mtime=%y" "$FINAL_VCF.tbi"
        else
          echo "final_tbi=missing"
        fi
        if [[ -f "$MARKER" ]]; then
          stat -c "target_marker=%n bytes=%s mtime=%y" "$MARKER"
        else
          echo "target_marker=missing"
        fi
        if [[ -d "$SENTPGS_DIR/concordance" ]]; then
          find "$SENTPGS_DIR/concordance" -maxdepth 3 -type f \\( -name 'concordance.done' -o -name '*.mqc.tsv' -o -name 'summary.txt' -o -name 'done.txt' \\) | sort | sed 's#^#concordance_file=#'
        else
          echo "concordance_dir=missing"
        fi
        if [[ -f "$BENCHMARK_SUMMARY" ]]; then
          stat -c "benchmark_summary=%n bytes=%s mtime=%y" "$BENCHMARK_SUMMARY"
        else
          echo "benchmark_summary=missing"
        fi

        echo "__LATEST_SNAKEMAKE_PROGRESS__"
        latest_log=$(find "$REPO_DIR/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
        echo "snakemake_log=$latest_log"
        grep -E "^([0-9]+ of [0-9]+ steps|Finished job|Complete log|WorkflowError|Error in rule|Exiting because)" "$latest_log" | tail -n 12 || true

        echo "__LATEST_SHARD_STAGE__"
        if [[ -d "$SENTPGS_DIR/log" ]]; then
          find "$SENTPGS_DIR/log" -type f -name '*.log' -printf '%T@ %p\\n' |
            sort -nr |
            head -n 5 |
            cut -d' ' -f2- |
            while read -r log; do
              printf "%s\\n" "--- $log"
              tr '\\r' '\\n' < "$log" | grep -E 'Stage [0-9]+:|Elapsed-Time-min|ERROR|VCF not produced' | tail -n 5 || true
            done
        else
          echo "shard_log_dir=missing"
        fi
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", required=True)
    args = parser.parse_args()
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            remote_script(session=args.session),
            profile=PROFILE,
            timeout=180,
            comment=f"Compact status sharded Ultima pangenome {args.session}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
