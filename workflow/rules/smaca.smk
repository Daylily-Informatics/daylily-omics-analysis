"""Rules for running the SMAca copy number caller."""

rule smaca:  # TARGET : Run SMAca copy-number estimation for SMN genes.
    """Execute SMAca on a CRAM/CRAI pair."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/htd/smaca/results/{sample}.{alnr}"),
        summary=MDIR + "{sample}/align/{alnr}/htd/smaca/{sample}.{alnr}.smaca.summary.tsv",
        done=MDIR + "{sample}/align/{alnr}/htd/smaca/{sample}.{alnr}.smaca.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards: config.get("smaca", {}).get("command", "SMAca.py"),
        controls=lambda wildcards: config.get("smaca", {}).get("controls_manifest", ""),
        panel=lambda wildcards: config.get("smaca", {}).get("panel_bed", ""),
        extra=lambda wildcards: config.get("smaca", {}).get("extra_args", ""),
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        flag_case=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("case", "--case"),
        flag_crai=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("crai", "--crai"),
        flag_reference=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("reference", "--reference"),
        flag_controls=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("controls", "--controls"),
        flag_panel=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("panel", "--panel"),
        flag_output=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("output", "--output"),
        flag_sample=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("sample", "--sample"),
        flag_threads=lambda wildcards: config.get("smaca", {}).get("flags", {}).get("threads", "--threads"),
        summary_filename=lambda wildcards: config.get("smaca", {}).get("summary_filename", "SMAca_results.tsv"),
    log:
        MDIR + "{sample}/align/{alnr}/htd/smaca/logs/{sample}.{alnr}.smaca.log",
    threads: config["go_left"]["threads"]
    conda:
        "workflow/envs/smaca_v0.1.yaml"
    shell:
        """
        set -euo pipefail

        out_dir={output.results_dir}
        summary_dir=$(dirname "{output.summary}")
        log_dir=$(dirname "{log}")

        rm -rf "$out_dir"
        mkdir -p "$out_dir" "$summary_dir" "$log_dir"

        export SMACA_COMMAND="{params.command}"
        export SMACA_CASE="{input.cram}"
        export SMACA_CRAI="{input.crai}"
        export SMACA_REFERENCE="{params.reference}"
        export SMACA_CONTROLS="{params.controls}"
        export SMACA_PANEL="{params.panel}"
        export SMACA_OUTPUT="$out_dir"
        export SMACA_SAMPLE="{wildcards.sample}"
        export SMACA_THREADS="{threads}"
        export SMACA_EXTRA="{params.extra}"
        export SMACA_FLAG_CASE="{params.flag_case}"
        export SMACA_FLAG_CRAI="{params.flag_crai}"
        export SMACA_FLAG_REFERENCE="{params.flag_reference}"
        export SMACA_FLAG_CONTROLS="{params.flag_controls}"
        export SMACA_FLAG_PANEL="{params.flag_panel}"
        export SMACA_FLAG_OUTPUT="{params.flag_output}"
        export SMACA_FLAG_SAMPLE="{params.flag_sample}"
        export SMACA_FLAG_THREADS="{params.flag_threads}"
        export SMACA_LOG="{log}"

        python - <<'PY'
import os
import shlex
import subprocess


def norm(value: str) -> str:
    value = (value or "").strip()
    if value.lower() == "none":
        return ""
    return value


def maybe_extend(args, flag_name: str, value_name: str):
    flag = norm(os.environ.get(flag_name, ""))
    value = norm(os.environ.get(value_name, ""))
    if not value:
        return
    if flag:
        args.extend([flag, value])
    else:
        args.append(value)


log_path = os.environ["SMACA_LOG"]
cmd_raw = norm(os.environ.get("SMACA_COMMAND", ""))
if not cmd_raw:
    raise SystemExit("SMAca command was empty")
args = shlex.split(cmd_raw)
maybe_extend(args, "SMACA_FLAG_CASE", "SMACA_CASE")
maybe_extend(args, "SMACA_FLAG_CRAI", "SMACA_CRAI")
maybe_extend(args, "SMACA_FLAG_REFERENCE", "SMACA_REFERENCE")
maybe_extend(args, "SMACA_FLAG_CONTROLS", "SMACA_CONTROLS")
maybe_extend(args, "SMACA_FLAG_PANEL", "SMACA_PANEL")
maybe_extend(args, "SMACA_FLAG_OUTPUT", "SMACA_OUTPUT")
maybe_extend(args, "SMACA_FLAG_SAMPLE", "SMACA_SAMPLE")
threads = norm(os.environ.get("SMACA_THREADS", ""))
flag_threads = norm(os.environ.get("SMACA_FLAG_THREADS", ""))
if threads:
    if flag_threads:
        args.extend([flag_threads, threads])
    else:
        args.append(threads)
extra = norm(os.environ.get("SMACA_EXTRA", ""))
if extra:
    args.extend(shlex.split(extra))
os.makedirs(os.path.dirname(log_path), exist_ok=True)
with open(log_path, "wb") as log_handle:
    command_line = " ".join(shlex.quote(p) for p in args)
    log_handle.write(("Running command: %s\n" % command_line).encode())
    log_handle.flush()
    proc = subprocess.run(args, stdout=log_handle, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
PY

        summary_src="{output.results_dir}/{params.summary_filename}"
        if [ -f "$summary_src" ]; then
            cp "$summary_src" "{output.summary}"
        else
            touch "{output.summary}"
        fi
        touch "{output.done}"
        """


localrules: produce_smaca

rule produce_smaca:
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/htd/smaca/{sample}.{alnr}.smaca.done",
            sample=SSAMPS,
            alnr=ALIGNERS,
        )
    output:
        "./logs/smaca.done"
    shell:
        "touch {output}"
