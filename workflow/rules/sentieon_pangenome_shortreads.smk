import os

####### Sentieon Pangenome (full) – short-read pipeline
#
# Uses sentieon-cli pangenome which performs:
#   1. Pangenome graph alignment (GBZ + XG + snarls)
#   2. Surjection + dedup onto linear GRCh38
#   3. SNV/indel calling with model bundle
#   4. SV calling via vg call
#   5. Ploidy estimation
#
# Outputs per sample:
#   {sample}.pangenome_sr.snv.vcf.gz               - SNV/indel VCF (model-applied)
#   {sample}.pangenome_sr_pangenome-aligned.cram    - surjected + deduped CRAM
#   {sample}.pangenome_sr_ploidy.json               - sex/ploidy estimate
#   {sample}.pangenome_sr_svs.vcf.gz               - SV VCF from vg call
#

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
