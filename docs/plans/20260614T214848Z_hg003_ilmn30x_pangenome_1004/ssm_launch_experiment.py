#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import pathlib
import shlex
import sys
import textwrap

sys.path.insert(0, "/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster")

from daylily_ec.aws.ssm import SsmCommandFailedError, run_shell


PLAN_DIR = pathlib.Path(__file__).resolve().parent
INSTANCE_ID = "i-05815cdeec4a6dad8"
REGION = "us-west-2"
PROFILE = "lsmc"
TAG = "10.0.4"
CLONE_ROOT = "/fsx/analysis_results/ubuntu"
CURRENT_MODEL = (
    "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/"
    "bundles/SentieonIlluminaPangenomeRealignWGS1.2.bundle"
)
CURRENT_POP = (
    "/fsx/references/genomic_data/organism_references/H_sapiens/panhg38/"
    "pop-v20-20260528.vcf.gz"
)
PRIOR_MODEL = (
    "/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/"
    "bundles/SentieonIlluminaPangenomeRealignWGS1.0.bundle/"
    "SentieonIlluminaPangenomeRealignWGS1.0.bundle"
)
PRIOR_POP = (
    "/fsx/references/genomic_data/organism_references/H_sapiens/panhg38/"
    "pop-v20g41-20251216.vcf.gz"
)


def b64_text(path: pathlib.Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def checked(command: str, label: str) -> str:
    return (
        f"{command}; rc=$?; "
        f"if [[ $rc -ne 0 ]]; then echo __DAYOA_FAIL__={label} rc=$rc $(date --iso-8601=seconds); exit $rc; fi"
    )


def build_remote_script(
    *, analysis_id: str, session: str, model_mode: str, resume_existing: bool
) -> str:
    repo_dir = f"{CLONE_ROOT}/{analysis_id}/daylily-omics-analysis"
    run_dir = f"/home/ubuntu/daylily-runs/{session}"
    samples_b64 = b64_text(PLAN_DIR / "samples.tsv")
    units_b64 = b64_text(PLAN_DIR / "units.tsv")
    patch_script = textwrap.dedent(
        f"""
        from pathlib import Path

        rule_config = Path("config/day_profiles/slurm/rule_config.yaml")
        text = rule_config.read_text()
        replacements = {{
            {CURRENT_MODEL!r}: {PRIOR_MODEL!r},
            {CURRENT_POP!r}: {PRIOR_POP!r},
        }}
        for old, new in replacements.items():
            if old not in text:
                raise SystemExit(f"missing expected current config value: {{old}}")
            text = text.replace(old, new)
        rule_config.write_text(text)
        verify = rule_config.read_text()
        for expected in ({PRIOR_MODEL!r}, {PRIOR_POP!r}):
            if expected not in verify:
                raise SystemExit(f"failed to write prior config value: {{expected}}")
        print("patched prior pangenome model/pop_vcf")
        """
    ).strip()
    verify_script = textwrap.dedent(
        f"""
        from pathlib import Path
        import sys

        mode = sys.argv[1]
        rule_config = Path("config/day_profiles/slurm/rule_config.yaml")
        text = rule_config.read_text()
        expected = {{
            "current": ({CURRENT_MODEL!r}, {CURRENT_POP!r}),
            "prior": ({PRIOR_MODEL!r}, {PRIOR_POP!r}),
        }}[mode]
        for value in expected:
            if value not in text:
                raise SystemExit(f"missing expected {{mode}} config value: {{value}}")
        print(f"verified {{mode}} pangenome model/pop_vcf")
        """
    ).strip()
    patch_b64 = base64.b64encode(patch_script.encode("utf-8")).decode("ascii")
    verify_b64 = base64.b64encode(verify_script.encode("utf-8")).decode("ascii")

    prior_patch_cmd = (
        f"python3 {shell_quote(run_dir + '/patch_prior_model.py')}"
        if model_mode == "prior"
        else "true"
    )

    pangenome_dry = (
        "dy-r produce_pangenome_sr_vcf produce_snv_concordances "
        "-p -j 150 -k -T 0 --rerun-triggers mtime "
        "--config 'aligners=[\"pangenome_sr\"]' 'snv_callers=[\"sentpg\"]' -n"
    )
    alignstats_dry = (
        "dy-r produce_sent_align produce_dmd_dedup_cram produce_alignstats "
        "-p -j 150 -k -T 0 --rerun-triggers mtime "
        "--config 'aligners=[\"sent\"]' 'dedupers=[\"dppl\"]' -n"
    )

    commands = [
        "set -o pipefail",
        f"export PS1='[{session}]$ '",
    ]
    if not resume_existing:
        commands.extend(
            [
                f"cd {shell_quote(CLONE_ROOT)}",
                (
                    checked(
                        f"day-clone -t {shell_quote(TAG)} -d {shell_quote(analysis_id)} "
                        "--executing-entity ubuntu --repository daylily-omics-analysis",
                        "day_clone",
                    )
                ),
            ]
        )
    commands.extend(
        [
        checked(f"cd {shell_quote(repo_dir)}", "cd_repo"),
        checked(
            f"mkdir -p config && cp {shell_quote(run_dir + '/samples.tsv')} config/samples.tsv && cp {shell_quote(run_dir + '/units.tsv')} config/units.tsv",
            "copy_manifests",
        ),
        checked("source dyoainit --skip-project-check", "dyoainit"),
        checked("dy-a slurm hg38_broad", "dy_a"),
        checked(prior_patch_cmd, "patch_prior_model"),
        checked(
            f"python3 {shell_quote(run_dir + '/verify_model_config.py')} {shell_quote(model_mode)}",
            "verify_model_config",
        ),
        "echo __DAYOA_STAGE__=pangenome_dry_run_start $(date --iso-8601=seconds)",
        checked(pangenome_dry, "pangenome_dry_run"),
        "echo __DAYOA_STAGE__=pangenome_dry_run_done $(date --iso-8601=seconds)",
        "echo __DAYOA_STAGE__=alignstats_dry_run_start $(date --iso-8601=seconds)",
        checked(alignstats_dry, "alignstats_dry_run"),
        "echo __DAYOA_STAGE__=alignstats_dry_run_done $(date --iso-8601=seconds)",
        f"echo __DAYOA_READY_FOR_LIVE__={shell_quote(model_mode)} $(date --iso-8601=seconds)",
        ]
    )

    send_lines = "\n".join(
        f"tmux send-keys -t \"$SESSION\" {shell_quote(command)} C-m"
        for command in commands
    )

    return textwrap.dedent(
        f"""
        set -euo pipefail
        ANALYSIS_ID={shell_quote(analysis_id)}
        SESSION={shell_quote(session)}
        MODEL_MODE={shell_quote(model_mode)}
        export RUN_DIR={shell_quote(run_dir)}
        REPO_DIR={shell_quote(repo_dir)}
        TMUX_LOG="$RUN_DIR/tmux.log"

        test "$(id -un)" = ubuntu
        command -v day-clone
        command -v tmux
        command -v squeue
        if tmux has-session -t "$SESSION" 2>/dev/null; then
          echo "tmux session already exists: $SESSION" >&2
          exit 64
        fi
        if [[ {shell_quote("yes" if resume_existing else "no")} == "yes" ]]; then
          if [[ ! -d "$REPO_DIR" ]]; then
            echo "resume requested but analysis repo directory is missing: $REPO_DIR" >&2
            exit 66
          fi
        elif [[ -e "$REPO_DIR" || -e {shell_quote(CLONE_ROOT)}/"$ANALYSIS_ID" ]]; then
          echo "analysis directory already exists: {CLONE_ROOT}/$ANALYSIS_ID" >&2
          exit 65
        fi

        mkdir -p "$RUN_DIR"
        printf '\n__DAYOA_LAUNCH__=%s model=%s resume_existing=%s started=%s\n' "$SESSION" "$MODEL_MODE" {shell_quote("yes" if resume_existing else "no")} "$(date --iso-8601=seconds)" >> "$TMUX_LOG"
        export SAMPLES_B64={shell_quote(samples_b64)}
        export UNITS_B64={shell_quote(units_b64)}
        export PATCH_B64={shell_quote(patch_b64)}
        export VERIFY_B64={shell_quote(verify_b64)}
        python3 -c 'import base64, os, pathlib; pathlib.Path(os.environ["RUN_DIR"], "samples.tsv").write_bytes(base64.b64decode(os.environ["SAMPLES_B64"])); pathlib.Path(os.environ["RUN_DIR"], "units.tsv").write_bytes(base64.b64decode(os.environ["UNITS_B64"])); pathlib.Path(os.environ["RUN_DIR"], "patch_prior_model.py").write_text(base64.b64decode(os.environ["PATCH_B64"]).decode(), encoding="utf-8"); pathlib.Path(os.environ["RUN_DIR"], "verify_model_config.py").write_text(base64.b64decode(os.environ["VERIFY_B64"]).decode(), encoding="utf-8")'

        tmux new-session -d -s "$SESSION" 'bash -il'
        tmux pipe-pane -o -t "$SESSION" "cat >> '$TMUX_LOG'"
        {send_lines}

        echo "__DAYLILY_SESSION__=$SESSION"
        echo "__DAYLILY_ANALYSIS_DIR__=$REPO_DIR"
        echo "__DAYLILY_TMUX_LOG__=$TMUX_LOG"
        echo "__DAYLILY_MODEL_MODE__=$MODEL_MODE"
        """
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-id", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--model-mode", required=True, choices=["current", "prior"])
    parser.add_argument("--resume-existing", action="store_true")
    args = parser.parse_args()

    script = build_remote_script(
        analysis_id=args.analysis_id,
        session=args.session,
        model_mode=args.model_mode,
        resume_existing=args.resume_existing,
    )
    try:
        result = run_shell(
            INSTANCE_ID,
            REGION,
            script,
            profile=PROFILE,
            timeout=180,
            comment=f"Launch HG003 pangenome {TAG} {args.model_mode}",
        )
    except SsmCommandFailedError as exc:
        print(exc.result.stdout, end="")
        print(exc.result.stderr, end="", file=sys.stderr)
        raise
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)


if __name__ == "__main__":
    main()
