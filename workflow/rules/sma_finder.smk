"""Rules for running Broad sma-finder."""


SMA_FINDER_REFERENCE_FLAG = (
    "--hg37-reference-fasta" if config["genome_build"] == "b37" else "--hg38-reference-fasta"
)


rule sma_finder:  # TARGET : Run Broad sma-finder affected-status screen.
    """Execute sma-finder on a short-read CRAM/CRAI pair."""
    input:
        cram=smn_short_cram,
        crai=smn_short_crai,
    output:
        tsv=MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.tsv",
        json=MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.json",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards: config.get("sma_finder", {}).get("command", "sma_finder"),
        reference_flag=SMA_FINDER_REFERENCE_FLAG,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        extra=lambda wildcards: config.get("sma_finder", {}).get("extra_args", ""),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/logs/{sample}.{alnr}.{ddup}.sma_finder.log",
    benchmark:
        MDIR + "benchmarks/sma_finder.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["sma_finder"]["threads"]
    conda:
        "../envs/sma_finder_v0.1.yaml"
    resources:
        partition=config["sma_finder"]["partition"],
        threads=config["sma_finder"]["threads"],
        vcpu=config["sma_finder"]["threads"],
        mem_mb=config["sma_finder"]["mem_mb"],
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.tsv:q}) $(dirname {log:q})
        rm -f {output.tsv:q} {output.json:q} {output.done:q}

        export SMA_FINDER_COMMAND={params.command:q}
        export SMA_FINDER_EXTRA={params.extra:q}
        export SMA_FINDER_LOG={log:q}

        python - <<'PY'
import os
import shlex
import shutil
import subprocess
import sys

command = os.environ["SMA_FINDER_COMMAND"].strip()
if not command:
    raise SystemExit("sma-finder command was empty")
args = shlex.split(command)
if shutil.which(args[0]) is None:
    raise SystemExit("sma-finder command was not found on PATH: %s" % args[0])
extra = os.environ["SMA_FINDER_EXTRA"].strip()
cmd = args + [
    "--verbose",
    "{params.reference_flag}",
    "{params.reference}",
    "-o",
    "{output.tsv}",
]
if extra:
    cmd.extend(shlex.split(extra))
cmd.append("{input.cram}")
os.makedirs(os.path.dirname(os.environ["SMA_FINDER_LOG"]), exist_ok=True)
with open(os.environ["SMA_FINDER_LOG"], "wb") as log:
    log.write(("Running command: %s\n" % " ".join(shlex.quote(part) for part in cmd)).encode())
    log.flush()
    proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if proc.returncode:
    sys.exit(proc.returncode)
PY

        test -s {output.tsv:q}
        python - <<'PY'
import csv
import json
from pathlib import Path

tsv = Path("{output.tsv}")
with tsv.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\\t")
    row = next(reader, None)
if not row:
    raise SystemExit("sma-finder summary has no data rows: %s" % tsv)
payload = dict(
    caller="sma_finder",
    sample="{wildcards.sample}",
    aligner="{wildcards.alnr}",
    deduper="{wildcards.ddup}",
    capability="affected_status_only",
    result=row,
)
Path("{output.json}").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\\n", encoding="utf-8")
PY
        test -s {output.json:q}
        touch {output.done:q}
        """


localrules: produce_sma_finder

rule produce_sma_finder:  # TARGET : Produce Broad sma-finder results
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.done",
            sample=SSAMPS,
            alnr=smn_short_read_aligners(),
            ddup=DDUP,
        )
    output:
        "./logs/sma_finder.done"
    log:
        "./logs/produce_sma_finder.log"
    benchmark:
        "./logs/benchmarks/produce_sma_finder.bench.tsv"
    shell:
        "touch {output}"
