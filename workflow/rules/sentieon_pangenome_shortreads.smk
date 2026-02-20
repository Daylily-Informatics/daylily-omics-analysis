# Sentieon pangenome (graph) short-read processing
# - Wraps: sentieon-cli pangenome
# - Inputs: Illumina short-read FASTQ (paired-end or single-end)
# - Outputs (by Sentieon-cli naming convention):
#     {output.vcf}                       -> final SNV/indel VCF (model-applied)
#     {output.aligned}                   -> pangenome-assisted, surjected + deduped CRAM aligned to GRCh38
#     {output.ploidy_json}               -> sex/ploidy estimate JSON
#     {output.svs_vcf}                   -> SV VCF produced by vg call (optional to consume downstream)
#
# Required config keys (mirrors your existing Sentieon rules style):
#   config['supporting_files']['files']['huref']['fasta']['name']
#   config['supporting_files']['files']['sentieon_env']['path']
#   config['supporting_files']['files']['sentieon_env']['jemalloc_path']
#   config['supporting_files']['files']['pangenome_gbz']['name']
#   config['supporting_files']['files']['pangenome_hapl']['name']
#   config['supporting_files']['files']['pangenome_xg']['name']
#   config['supporting_files']['files']['pangenome_snarls']['name']
#   config['supporting_files']['files']['pangenome_model_bundle']['name']
#
# Optional config keys:
#   config['supporting_files']['files']['dbsnp']['name']         (if present, passed as --dbsnp)
#   config['sentieon']['pangenome_threads']                      (else falls back to config['sentieon']['threads'])
#   config['sentieon']['pangenome_kmer_memory_gb']               (default 30)
#   config['sentieon']['pangenome_skip_cnv']                     (default True)
#   config['sentieon']['pangenome_pcr_free']                     (default True)
#
# FASTQ discovery:
#   This module tries, in order:
#     1) global helper fns: getR1s(wildcards) and getR2s(wildcards)
#     2) config-driven: config['samples'][sample]['r1'] and optional ['r2']
#     3) units.tsv parsing if config contains a path under one of:
#           config['units_tsv']
#           config['tables']['units_tsv']
#           config['tables']['units']
#
# If none are found, the rule errors with an actionable message.

import os
import csv
from pathlib import Path

MDIR = "{DIR}/tools/"

# -------------------------
# Helpers
# -------------------------

def _as_list(x):
    if x is None:
        return []
    if isinstance(x, (list, tuple)):
        return [str(i) for i in x if i not in (None, "")]
    return [str(x)]

_UNITS_ROWS = None
_UNITS_PATH = None
_UNITS_SAMPLE_CACHE = {}

def _get_units_path():
    # Try a few common config layouts.
    candidates = []
    if isinstance(config, dict):
        if config.get("units_tsv"):
            candidates.append(config["units_tsv"])
        tables = config.get("tables", {}) if isinstance(config.get("tables", {}), dict) else {}
        if tables.get("units_tsv"):
            candidates.append(tables["units_tsv"])
        if tables.get("units"):
            candidates.append(tables["units"])
    for p in candidates:
        if p and Path(p).exists():
            return str(p)
    return None

def _load_units_rows():
    global _UNITS_ROWS, _UNITS_PATH
    if _UNITS_ROWS is not None:
        return _UNITS_ROWS
    units_path = _get_units_path()
    _UNITS_PATH = units_path
    if not units_path:
        _UNITS_ROWS = []
        return _UNITS_ROWS
    rows = []
    with open(units_path, "r", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            rows.append(row)
    _UNITS_ROWS = rows
    return _UNITS_ROWS

def _units_rows_for_sample(sample):
    # Cache per sample because Snakemake calls input functions repeatedly.
    if sample in _UNITS_SAMPLE_CACHE:
        return _UNITS_SAMPLE_CACHE[sample]
    rows = _load_units_rows()
    sample_rows = [r for r in rows if (r.get("SAMPLEID") == sample)]
    _UNITS_SAMPLE_CACHE[sample] = sample_rows
    return sample_rows

def _fastqs_from_helpers_or_config_or_units(wildcards):
    sample = wildcards.sample

    # 1) Global helper functions (your workflow already uses these)
    if "getR1s" in globals():
        r1 = _as_list(globals()["getR1s"](wildcards))
        r2 = _as_list(globals()["getR2s"](wildcards)) if "getR2s" in globals() else []
        if not r1:
            raise ValueError(f"getR1s({sample}) returned no FASTQs")
        return (r1, r2, None)

    # 2) config['samples'][sample] mapping
    samples = config.get("samples", {}) if isinstance(config, dict) else {}
    if isinstance(samples, dict) and sample in samples and isinstance(samples[sample], dict):
        r1 = _as_list(samples[sample].get("r1") or samples[sample].get("R1"))
        r2 = _as_list(samples[sample].get("r2") or samples[sample].get("R2"))
        if not r1:
            raise ValueError(f"config['samples'][{sample}]['r1'] is missing/empty")
        return (r1, r2, None)

    # 3) units.tsv
    rows = _units_rows_for_sample(sample)
    if rows:
        r1 = []
        r2 = []
        lane_meta = []
        for row in rows:
            r1p = (row.get("ILMN_R1_PATH") or "").strip()
            r2p = (row.get("ILMN_R2_PATH") or "").strip()
            if not r1p:
                continue
            r1.append(r1p)
            if r2p:
                r2.append(r2p)
            lane_meta.append(row)
        if not r1:
            raise ValueError(
                f"units.tsv ({_UNITS_PATH}) has SAMPLEID={sample} rows but no ILMN_R1_PATH values"
            )
        return (r1, r2, lane_meta)

    raise ValueError(
        "Unable to resolve FASTQs for sample '{s}'. Provide either:\n"
        "  - helper functions getR1s()/getR2s(), or\n"
        "  - config['samples'][sample]['r1'] (+ optional ['r2']), or\n"
        "  - a units.tsv path in config['units_tsv'] (or config['tables']['units_tsv'] / ['units'])\n"
        "and ensure it contains ILMN_R1_PATH (+ optional ILMN_R2_PATH) for that SAMPLEID.".format(s=sample)
    )

def pangenome_r1_fastqs(wildcards):
    r1, r2, _ = _fastqs_from_helpers_or_config_or_units(wildcards)
    return r1

def pangenome_r2_fastqs(wildcards):
    r1, r2, _ = _fastqs_from_helpers_or_config_or_units(wildcards)
    return r2

def pangenome_readgroups(wildcards):
    """
    Build one readgroup per R1 fastq, as required by sentieon-cli pangenome:
      len(r1_fastq) must equal len(readgroups).
    """
    sample = wildcards.sample
    r1, r2, lane_meta = _fastqs_from_helpers_or_config_or_units(wildcards)

    rgs = []
    if lane_meta:
        # Use RUNID/LANEID/BARCODEID if present in units.tsv to make stable RG IDs
        for i, row in enumerate(lane_meta):
            runid = (row.get("RUNID") or "").strip()
            laneid = (row.get("LANEID") or "").strip()
            barcode = (row.get("BARCODEID") or "").strip()
            rgid_parts = [p for p in [sample, runid, laneid, barcode] if p]
            rgid = ".".join(rgid_parts) if rgid_parts else f"{sample}.{i+1}"
            lb = (row.get("LIBPREP") or sample).strip() or sample
            # PL is the sequencing platform family; for Illumina data, use ILLUMINA
            rgs.append(f"@RG\\tID:{rgid}\\tSM:{sample}\\tLB:{lb}\\tPL:ILLUMINA")
    else:
        for i in range(len(r1)):
            rgid = f"{sample}.{i+1}"
            rgs.append(f"@RG\\tID:{rgid}\\tSM:{sample}\\tLB:{sample}\\tPL:ILLUMINA")

    if len(rgs) != len(r1):
        raise ValueError(
            f"Internal error: generated {len(rgs)} readgroups for {len(r1)} R1 FASTQs (sample={sample})"
        )
    return rgs

def _cfg(path, default=None):
    cur = config
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

# -------------------------
# Rules
# -------------------------

localrules: sentieon_pangenome_shortreads

rule sentieon_pangenome_shortreads:
    input:
        r1=pangenome_r1_fastqs,
        r2=pangenome_r2_fastqs,
    output:
        vcf=MDIR + "align/pangenome/{sample}.vcf.gz",
        aligned=MDIR + "align/pangenome/{sample}_pangenome-aligned.cram",
        ploidy_json=MDIR + "align/pangenome/{sample}_ploidy.json",
        svs_vcf=MDIR + "align/pangenome/{sample}_svs.vcf.gz",
    log:
        MDIR + "align/pangenome/{sample}.pangenome.log",
    threads:
        config.get("sentieon", {}).get("pangenome_threads", config.get("sentieon", {}).get("threads", 16))
    params:
        ref=_cfg(["supporting_files","files","huref","fasta","name"]),
        sentieon_env=_cfg(["supporting_files","files","sentieon_env","path"]),
        jemalloc=_cfg(["supporting_files","files","sentieon_env","jemalloc_path"]),
        gbz=_cfg(["supporting_files","files","pangenome_gbz","name"]),
        hapl=_cfg(["supporting_files","files","pangenome_hapl","name"]),
        xg=_cfg(["supporting_files","files","pangenome_xg","name"]),
        snarls=_cfg(["supporting_files","files","pangenome_snarls","name"]),
        model_bundle=_cfg(["supporting_files","files","pangenome_model_bundle","name"]),
        dbsnp=_cfg(["supporting_files","files","dbsnp","name"], default=""),
        kmer_memory_gb=config.get("sentieon", {}).get("pangenome_kmer_memory_gb", 30),
        skip_cnv=config.get("sentieon", {}).get("pangenome_skip_cnv", True),
        pcr_free=config.get("sentieon", {}).get("pangenome_pcr_free", True),
        readgroups=pangenome_readgroups,
    shell:
        """
        set -euo pipefail

        # Activate env (mirrors your existing Sentieon rules style)
        source /fsx/data/cached_envs/miniconda3/bin/activate {MDIR}{params.sentieon_env}/bin

        if [ -z "${{SENTIEON_LICENSE:-}}" ]; then
            echo "SENTIEON_LICENSE is not set." >&2
            exit 1
        fi

        # jemalloc: keep consistent with your Sentieon rules
        export LD_PRELOAD={params.jemalloc}
        export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:30000,muzzy_decay_ms:30000

        # Per-sample tmpdir for sentieon-cli (uses SENTIEON_TMPDIR)
        ts="$(date +%s)"
        TMPROOT="/dev/shm"
        TMPDIR="${{TMPROOT}}/sentieon_pangenome_{wildcards.sample}_${{ts}}"
        mkdir -p "${{TMPDIR}}"
        export SENTIEON_TMPDIR="${{TMPDIR}}"

        mkdir -p "$(dirname {output.vcf})"

        # Optional args
        R2_ARGS=""
        if [ -n "{input.r2}" ]; then
            R2_ARGS="--r2_fastq {input.r2}"
        fi

        DBSNP_ARGS=""
        if [ -n "{params.dbsnp}" ]; then
            DBSNP_ARGS="--dbsnp {params.dbsnp}"
        fi

        PCRFREE_ARGS=""
        if [ "{params.pcr_free}" = "True" ]; then
            PCRFREE_ARGS="--pcr_free"
        fi

        SKIP_CNV_ARGS=""
        if [ "{params.skip_cnv}" = "True" ]; then
            SKIP_CNV_ARGS="--skip_cnv"
        fi

        # Run Sentieon CLI pangenome pipeline
        # Output naming is driven by the positional output_vcf path
        sentieon-cli pangenome \
            --reference {params.ref} \
            --cores {threads} \
            --gbz {params.gbz} \
            --hapl {params.hapl} \
            --xg {params.xg} \
            --snarls {params.snarls} \
            -m {params.model_bundle} \
            --kmer_memory {params.kmer_memory_gb} \
            --r1_fastq {input.r1} \
            $R2_ARGS \
            --readgroups {params.readgroups} \
            $DBSNP_ARGS \
            $PCRFREE_ARGS \
            $SKIP_CNV_ARGS \
            {output.vcf} \
            > {log} 2>&1

        # Cleanup
        rm -rf "${{TMPDIR}}"
        """
