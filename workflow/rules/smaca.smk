"""Rules for running the SMAca SMN copy-number caller."""


SMACA_REFERENCE_ARG = "hg19" if config["genome_build"] == "b37" else "hg38"


rule smaca:  # TARGET : Run SMAca copy-number estimation for SMN genes.
    """Execute SMAca on a short-read CRAM/CRAI pair."""
    input:
        cram=smn_short_cram,
        crai=smn_short_crai,
        preflight=smn12_input_qc_done,
    output:
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.summary.tsv",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards: config.get("smaca", {}).get("command", "smaca"),
        reference=SMACA_REFERENCE_ARG,
        extra=lambda wildcards: config.get("smaca", {}).get("extra_args", ""),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/logs/{sample}.{alnr}.{ddup}.smaca.log",
    benchmark:
        MDIR + "benchmarks/smaca.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["smaca"]["threads"]
    conda:
        "../envs/smaca_v0.1.yaml"
    resources:
        partition=config["smaca"]["partition"],
        threads=config["smaca"]["threads"],
        vcpu=config["smaca"]["threads"],
        mem_mb=config["smaca"]["mem_mb"],
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.summary:q}) $(dirname {log:q})
        rm -f {output.summary:q} {output.done:q}

        export SMACA_COMMAND={params.command:q}
        export SMACA_EXTRA={params.extra:q}
        export SMACA_LOG={log:q}

        python - <<'PY'
import os
import shlex
import shutil
import subprocess
import sys

command = os.environ["SMACA_COMMAND"].strip()
if not command:
    raise SystemExit("SMAca command was empty")
args = shlex.split(command)
if shutil.which(args[0]) is None:
    raise SystemExit("SMAca command was not found on PATH: %s" % args[0])
extra = os.environ["SMACA_EXTRA"].strip()
cmd = args + [
    "--output",
    "{output.summary}",
    "--reference",
    "{params.reference}",
    "--ncpus",
    "{threads}",
]
if extra:
    cmd.extend(shlex.split(extra))
cmd.append("{input.cram}")
os.makedirs(os.path.dirname(os.environ["SMACA_LOG"]), exist_ok=True)
with open(os.environ["SMACA_LOG"], "wb") as log:
    log.write(("Running command: %s\\n" % " ".join(shlex.quote(part) for part in cmd)).encode())
    log.flush()
    proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if proc.returncode:
    sys.exit(proc.returncode)
PY

        test -s {output.summary:q}
        python - <<'PY'
import csv
from pathlib import Path

path = Path("{output.summary}")
with path.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.reader(handle, delimiter="\\t")
    header = next(reader, None)
if not header:
    raise SystemExit("SMAca summary has no header: %s" % path)
PY
        touch {output.done:q}
        """


localrules: produce_smaca

rule produce_smaca:  # TARGET : Produce SMAca results
    input:
        smn_short_read_alnr_ddup_inputs(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done"
        )
    output:
        "./logs/smaca.done"
    log:
        "./logs/produce_smaca.log"
    benchmark:
        "./logs/benchmarks/produce_smaca.bench.tsv"
    shell:
        "touch {output}"
