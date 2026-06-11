"""Rules for running HapSMA as a dev/exploratory ONT caller."""


def _hapsma_cfg():
    return config.get("hapsma", {})


def _hapsma_required(key):
    value = _hapsma_cfg().get(key, "")
    if not _filled(value):
        raise WorkflowError(
            f"HapSMA is dev_exploratory and requires config.hapsma.{key}."
        )
    return str(value)


def _hapsma_optional(key):
    value = _hapsma_cfg().get(key, "")
    if not _filled(value):
        return ""
    return str(value)


rule hapsma:  # TARGET : Run HapSMA exploratory ONT SMN analysis.
    """Execute HapSMA on an ONT/HiOMR long-read CRAM after an SMN coverage gate."""
    input:
        cram=smn_long_cram,
        crai=smn_long_crai,
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/results/{sample}.{alnr}.{ddup}"),
        coverage=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.smn_region_coverage.tsv",
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.summary.tsv",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
    params:
        cluster_sample=ret_sample,
        nextflow_command=lambda wildcards: _hapsma_required("nextflow_command"),
        workflow_path=lambda wildcards: _hapsma_required("workflow_path"),
        config_path=lambda wildcards: _hapsma_required("config_path"),
        email=lambda wildcards: _hapsma_required("email"),
        ploidy=lambda wildcards: _hapsma_required("ploidy"),
        smn_region=lambda wildcards: _hapsma_required("smn_region"),
        min_cov=lambda wildcards: str(_hapsma_cfg().get("min_smn_region_mean_coverage", 8)),
        start=lambda wildcards: str(_hapsma_cfg().get("start", "bam_single_remap")),
        single_bam_type=lambda wildcards: str(_hapsma_cfg().get("single_bam_type", "path")),
        clair3model=lambda wildcards: _hapsma_optional("clair3model"),
        extra=lambda wildcards: _hapsma_optional("extra_args"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/logs/{sample}.{alnr}.{ddup}.hapsma.log",
    benchmark:
        MDIR + "benchmarks/hapsma.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["hapsma"]["threads"]
    conda:
        "../envs/hapsma_v0.1.yaml"
    resources:
        partition=config["hapsma"]["partition"],
        threads=config["hapsma"]["threads"],
        vcpu=config["hapsma"]["threads"],
        mem_mb=config["hapsma"]["mem_mb"],
    shell:
        """
        set -euo pipefail
        rm -rf {output.results_dir:q}
        mkdir -p {output.results_dir:q} $(dirname {output.summary:q}) $(dirname {log:q})
        rm -f {output.coverage:q} {output.summary:q} {output.done:q}

        smn_bam="{output.results_dir}/input.smn_region.bam"
        mean_cov_file="{output.results_dir}/smn_region.mean_coverage.txt"

        samtools depth -r {params.smn_region:q} -a {input.cram:q} > {output.coverage:q}
        awk '{{sum += $3; n += 1}} END {{if (n == 0) {{print 0}} else {{printf "%.6f\\n", sum / n}}}}' \
            {output.coverage:q} > "$mean_cov_file"

        python - <<'PY'
from pathlib import Path

mean_cov = float(Path("{output.results_dir}/smn_region.mean_coverage.txt").read_text().strip())
min_cov = float("{params.min_cov}")
if mean_cov < min_cov:
    raise SystemExit(
        f"HapSMA coverage gate failed for {wildcards.sample}: "
        f"mean SMN region coverage {mean_cov:.3f} < required {min_cov:.3f}."
    )
PY

        samtools view -@ {threads} -b {input.cram:q} {params.smn_region:q} > "$smn_bam"
        samtools index -@ {threads} "$smn_bam"

        export HAPSMA_NEXTFLOW={params.nextflow_command:q}
        export HAPSMA_WORKFLOW_PATH={params.workflow_path:q}
        export HAPSMA_CONFIG_PATH={params.config_path:q}
        export HAPSMA_EMAIL={params.email:q}
        export HAPSMA_PLOIDY={params.ploidy:q}
        export HAPSMA_START={params.start:q}
        export HAPSMA_SINGLE_BAM_TYPE={params.single_bam_type:q}
        export HAPSMA_CLAIR3MODEL={params.clair3model:q}
        export HAPSMA_EXTRA={params.extra:q}
        export HAPSMA_INPUT_BAM="$smn_bam"
        export HAPSMA_OUTDIR={output.results_dir:q}
        export HAPSMA_LOG={log:q}

        python - <<'PY'
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

nextflow = os.environ["HAPSMA_NEXTFLOW"].strip()
if not nextflow:
    raise SystemExit("HapSMA nextflow command was empty")
nf_args = shlex.split(nextflow)
if shutil.which(nf_args[0]) is None:
    raise SystemExit(f"HapSMA nextflow command was not found on PATH: {nf_args[0]}")
workflow_path = Path(os.environ["HAPSMA_WORKFLOW_PATH"])
workflow_nf = workflow_path / "SMA.nf"
config_path = Path(os.environ["HAPSMA_CONFIG_PATH"])
for path in (workflow_path, workflow_nf, config_path, Path(os.environ["HAPSMA_INPUT_BAM"])):
    if not path.exists():
        raise SystemExit(f"HapSMA required path does not exist: {path}")
cmd = nf_args + [
    "run",
    str(workflow_nf),
    "-c",
    str(config_path),
    "--input_path",
    os.environ["HAPSMA_INPUT_BAM"],
    "--outdir",
    os.environ["HAPSMA_OUTDIR"],
    "--start",
    os.environ["HAPSMA_START"],
    "--single_bam_type",
    os.environ["HAPSMA_SINGLE_BAM_TYPE"],
    "--ploidy",
    os.environ["HAPSMA_PLOIDY"],
    "--sample_id",
    "{wildcards.sample}",
    "--email",
    os.environ["HAPSMA_EMAIL"],
]
clair3model = os.environ["HAPSMA_CLAIR3MODEL"].strip()
if clair3model:
    cmd.extend(["--clair3model", clair3model])
extra = os.environ["HAPSMA_EXTRA"].strip()
if extra:
    cmd.extend(shlex.split(extra))
with open(os.environ["HAPSMA_LOG"], "ab") as log:
    log.write(("Running command: %s\n" % " ".join(shlex.quote(part) for part in cmd)).encode())
    log.flush()
    proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
if proc.returncode:
    sys.exit(proc.returncode)
PY

        python - <<'PY'
from pathlib import Path

mean_cov = Path("{output.results_dir}/smn_region.mean_coverage.txt").read_text().strip()
rows = [
    "sample\\taligner\\tdeduper\\tcaller\\tcaller_class\\tdev_status\\tevidence_source\\tploidy\\tsmn_region\\tmean_smn_region_coverage\\toutput_dir",
    "{wildcards.sample}\\t{wildcards.alnr}\\t{wildcards.ddup}\\thapsma\\tlong_read_haplotype\\tdev_exploratory\\tONT_long_read_cram\\t{params.ploidy}\\t{params.smn_region}\\t"
    + mean_cov
    + "\\t{output.results_dir}",
]
Path("{output.summary}").write_text("\\n".join(rows) + "\\n", encoding="utf-8")
PY
        test -s {output.summary:q}
        touch {output.done:q}
        """


localrules: produce_hapsma

rule produce_hapsma:  # TARGET : Produce HapSMA exploratory ONT SMN results
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
            sample=SSAMPS,
            alnr=smn_long_read_aligners(),
            ddup=DDUP,
        )
    output:
        "./logs/hapsma.done"
    log:
        "./logs/produce_hapsma.log"
    benchmark:
        "./logs/benchmarks/produce_hapsma.bench.tsv"
    shell:
        "touch {output}"
