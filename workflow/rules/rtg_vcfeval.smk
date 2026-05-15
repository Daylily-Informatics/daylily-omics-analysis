import os
import sys
import glob


# -----------------------------------------------------------------------------
# Helpers (kept compatible with the existing pipeline context)
# -----------------------------------------------------------------------------

def get_samp_concordance_truth_dir(wildcards):
    """Return the per-sample truthset directory (may be empty/NA)."""
    # Original code used [0] indexing; iloc is safer if the DF index is not 0..N.
    cntrl_dir = samples[samples["sample"] == wildcards.sample]["CONCORDANCE_CONTROL_PATH"].iloc[0]
    return cntrl_dir


def get_alt_sample_name(wildcards):
    """Truthset filenames are keyed on EXTERNAL_SAMPLE_ID."""
    return samples[samples["sample"] == wildcards.sample]["EXTERNAL_SAMPLE_ID"].iloc[0]


def get_snv_caller(wildcards):
    return wildcards.snv


def get_cdir(wildcards):
    """Directory where concordance outputs land for this sample+condition."""
    ret_d = MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/concordance/"
    # Preserve original Marigo-path hack.
    if ret_d.startswith("/marigo"):
        ret_d = "results" + ret_d
    return ret_d


def _norm_path(p):
    """Normalize potentially-missing sample-sheet values (None/NaN/'na'/etc)."""
    if p is None:
        return ""
    s = str(p).strip()
    if s == "":
        return ""
    if s.lower() in {"none", "nan", "na", "null"}:
        return ""
    return s.rstrip("/")


def get_concordance_footprints(wildcards):
    """
    Truthset directory can have 0..many ROI subdirectories.
    Each ROI directory name becomes cmpFootprint.
    """
    tdir = _norm_path(get_samp_concordance_truth_dir(wildcards))
    if not tdir:
        return []
    if not os.path.isdir(tdir):
        return []
    fps = []
    for name in sorted(os.listdir(tdir)):
        p = os.path.join(tdir, name)
        if os.path.isdir(p):
            fps.append(name)
    return fps


def get_truth_vcf(wildcards):
    tdir = _norm_path(get_samp_concordance_truth_dir(wildcards))
    alt = get_alt_sample_name(wildcards)
    return f"{tdir}/{wildcards.cmpfootprint}/{alt}.vcf.gz"


def get_truth_tbi(wildcards):
    return get_truth_vcf(wildcards) + ".tbi"


def get_truth_bed(wildcards):
    tdir = _norm_path(get_samp_concordance_truth_dir(wildcards))
    alt = get_alt_sample_name(wildcards)
    return f"{tdir}/{wildcards.cmpfootprint}/{alt}.bed"


# -----------------------------------------------------------------------------
# Input VCF (callset) compatibility layer
# -----------------------------------------------------------------------------
# NOTE: This preserves the existing DAYLILY_DRAGEN symlink behavior, but makes it
# safer under parallelism (ln -sf, no sleeps).
# A later cleanup would turn this into a proper rule to avoid side effects in
# input functions.

def get_in_rtg_vcf(wildcards):
    if os.environ.get("DAYLILY_DRAGEN", "false") == "true":
        r1 = get_raw_R1s(wildcards)[0]
        dvcfgz = (
            f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/"
            f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{wildcards.snv}.snv.sort.vcf.gz"
        )
        os.system(f"mkdir -p {os.path.dirname(dvcfgz)}")
        os.system(f"ln -sf {r1} {dvcfgz}")
        return dvcfgz
    return (
        f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/"
        f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{wildcards.snv}.snv.sort.vcf.gz"
    )


def get_in_rtg_tbi(wildcards):
    if os.environ.get("DAYLILY_DRAGEN", "false") == "true":
        r2 = get_raw_R2s(wildcards)[0]
        dvcfgztbi = (
            f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/"
            f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{wildcards.snv}.snv.sort.vcf.gz.tbi"
        )
        os.system(f"mkdir -p {os.path.dirname(dvcfgztbi)}")
        os.system(f"ln -sf {r2} {dvcfgztbi}")
        return dvcfgztbi
    return (
        f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/"
        f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{wildcards.snv}.snv.sort.vcf.gz.tbi"
    )


def concordance_mqc_outputs(wildcards):
    """
    Dynamic input function for the per-ROI MQC outputs.
    This drives instantiation of per-ROI rules without the old fofn|bash mess.
    """
    fps = get_concordance_footprints(wildcards)
    if not fps:
        return []
    return expand(
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{cmpfootprint}/snv_{sample}_{cmpfootprint}_concordance.mqc.tsv",
        sample=wildcards.sample,
        alnr=wildcards.alnr,
        ddup=wildcards.ddup,
        snv=wildcards.snv,
        cmpfootprint=fps,
    )


def all_concordance_mqc_outputs():
    """
    Static ordered list of per-ROI concordance MQC TSVs for the final aggregate.
    """
    paths = []
    for sample in SSAMPS:
        for ddup in DDUP:
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS):
                wildcards = type(
                    "ConcordanceWildcards",
                    (),
                    {"sample": sample, "alnr": alnr, "ddup": ddup, "snv": snv},
                )()
                for cmpfootprint in get_concordance_footprints(wildcards):
                    paths.append(
                        MDIR
                        + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/"
                        + f"_{cmpfootprint}/snv_{sample}_{cmpfootprint}_concordance.mqc.tsv"
                    )
    return sorted(paths)


# -----------------------------------------------------------------------------
# Concordance rules
# -----------------------------------------------------------------------------

if len(CONCORDANCE_SAMPLES.keys()) > 0:

    rule rtg_vcfeval_roi:
        """
        Run rtg vcfeval for a single (sample, condition, cmpFootprint).
        """
        input:
            cvcf=get_in_rtg_vcf,
            ctbi=get_in_rtg_tbi,
            truth_vcf=get_truth_vcf,
            truth_tbi=get_truth_tbi,
            bed=get_truth_bed,
        output:
            summary=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{cmpfootprint}/summary.txt",
        log:
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/logs/{sample}.{alnr}.{ddup}.{snv}.{cmpfootprint}.rtg_vcfeval.log",
        benchmark:
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.{cmpfootprint}.rtg_vcfeval.bench.tsv",
        threads:
            int(config["rtg_vcfeval"].get("sub_threads", 7)),
        resources:
            vcpu=int(config["rtg_vcfeval"].get("sub_threads", 7)),
            threads=int(config["rtg_vcfeval"].get("sub_threads", 7)),
            mem_mb=config["rtg_vcfeval"].get("mem_mb", 64000),
            partition=config["rtg_vcfeval"]["partition_other"],
        conda:
            config["rtg_vcfeval"]["env_yaml"]
        params:
            sdf=config["supporting_files"]["files"]["huref"]["rtg_tools_genome"]["name"],
            cluster_sample=ret_sample,
        shell:
            r"""
            set -euo pipefail
            export TMPDIR="/fsx/scratch/"
            outdir="$(dirname {output.summary})"
            rm -rf "$outdir"

            rtg vcfeval \
              --decompose \
              --squash-ploidy \
              --ref-overlap \
              -e {input.bed} \
              -b {input.truth_vcf} \
              -c {input.cvcf} \
              -o "$outdir" \
              -t {params.sdf} \
              --threads {threads} \
              > {log} 2>&1
            """


    rule parse_vcfeval_summary_roi:
        """
        Parse rtg summary + classify TP/FP/FN into the existing per-class MQC TSV.
        """
        input:
            summary=rules.rtg_vcfeval_roi.output.summary,
            bed=get_truth_bed,
        output:
            mqc=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{cmpfootprint}/snv_{sample}_{cmpfootprint}_concordance.mqc.tsv",
        log:
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/logs/{sample}.{alnr}.{ddup}.{snv}.{cmpfootprint}.parse_vcfeval_summary.log",
        benchmark:
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.{cmpfootprint}.parse_vcfeval_summary.bench.tsv",
        # Increased threads to 16 for faster bcftools processing and VCF parsing
        threads: 16
        resources:
            vcpu=16,
            threads=16,
            mem_mb=config["rtg_vcfeval"].get("parse_mem_mb", 16000),
            partition=config["rtg_vcfeval"]["partition_other"],
        conda:
            config["rtg_vcfeval"]["env_yaml"]
        params:
            # Preserve existing metadata behavior
            alt_name=get_alt_sample_name,
            cluster_sample=ret_sample,
        shell:
            r"""
            set -euo pipefail

            outdir="$(dirname {input.summary})"
            # This file is legacy/debug; parse-vcfeval-summary.py uses its dirname to place the MQC TSV.
            legacy_parsed="$outdir/vcfeval_summary.parsed.tsv"

            # Keep mean depth behavior identical to the current rule (effectively NA/-1).
            allvar_mean_dp="na"

            # Prevent parse script from over-threading bcftools when many ROIs run concurrently.
            export DAYLILY_BCFTOOLS_THREADS="{threads}"

            python workflow/scripts/parse-vcfeval-summary.py \
              {input.summary} \
              {wildcards.sample} \
              {input.bed} \
              {wildcards.cmpfootprint} \
              {params.alt_name} \
              "$legacy_parsed" \
              "$allvar_mean_dp" \
              {wildcards.alnr} \
              {wildcards.ddup} \
              {wildcards.snv} \
              > {log} 2>&1

            # Hard check: the legacy script should have written the MQC output where we declared it.
            test -s {output.mqc}
            """


    rule prep_for_concordance_check:
        """
        Sample-level sentinel rule (drop-in replacement).
        - Produces concordance.done (as before)
        - Produces concordance.fofn + concordance.fin.cmds (kept for compatibility; now informational)
        - Drives per-ROI parallelism via input expansion
        """
        input:
            cvcf=get_in_rtg_vcf,
            ctbi=get_in_rtg_tbi,
            mqcs=concordance_mqc_outputs,
        priority: 48
        output:
            s=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.done"),
            fofn=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.fofn"),
            fin_cmds=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.fin.cmds"),
        log:
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/logs/{sample}.{alnr}.{ddup}.{snv}.concordance.log",
        benchmark:
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.concordance.bench.tsv",
        # Keep the rule-level threads/resources for backwards cluster configs that key off them.
        threads: 8 #config["rtg_vcfeval"]["threads"]
        resources:
            vcpu=config["rtg_vcfeval"]["threads"],
            threads=config["rtg_vcfeval"]["threads"],
            partition=config["rtg_vcfeval"]["partition_other"]
        conda:
            config["rtg_vcfeval"]["env_yaml"]
        params:
            tdir=get_samp_concordance_truth_dir,
            alt_name=get_alt_sample_name,
            cluster_sample=ret_sample,
            footprints=lambda wc: ",".join(get_concordance_footprints(wc)),
            nmqcs=lambda wc, input: len(input.mqcs),
        shell:
            """
            set +euo pipefail;

            mkdir -p $(dirname {output.s});
            mkdir -p $(dirname {log});

            utc_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ);

            # Write informational fofn
            {{
                echo "# Refactor: per-ROI jobs are scheduled by Snakemake; this file is informational.";
                echo "# generated_at_utc=$utc_ts";
                echo "# truth_dir={params.tdir}";
                echo "# footprints={params.footprints}";
                for mqc in {input.mqcs}; do
                    echo "$mqc";
                done;
            }} > {output.fofn};

            # Write informational fin.cmds
            {{
                echo "# Refactor: see Snakemake DAG for exact commands.";
                echo "# generated_at_utc=$utc_ts";
            }} > {output.fin_cmds};

            # SKIPPED sentinel if no mqcs
            if [ "{params.nmqcs}" -eq 0 ]; then
                echo "No truthset ROI directories found; concordance skipped." > {output.s}.SKIPPED;
            fi;

            # Log
            echo "Concordance sentinel complete. footprints={params.footprints} mqcs={params.nmqcs}" >> {log};
            """


else:

    localrules: no_concordance_data,

    rule no_concordance_data:
        input:
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz.tbi",
        output:
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.done",
        threads: 1
        shell:
            "touch {output};"


localrules: produce_snv_concordances
rule produce_snv_concordances:  # TARGET:  produce snv concordances
    input:
        dones=[
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.done"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
        mqcs=all_concordance_mqc_outputs(),
    priority: 48
    params:
        cluster_sample="aggregate",
        mdir=MDIR,
        genome_build=config["genome_build"],
        pc=print_wildcards_etc,
    output:
        mqc=MDIR + "other_reports/giab_concordance_mqc.tsv",
    threads: 1
    run:
        import csv
        from pathlib import Path

        out_path = Path(str(output.mqc))
        out_path.parent.mkdir(parents=True, exist_ok=True)
        fieldnames = None
        rows = []
        for mqc in [Path(str(path)) for path in input.mqcs]:
            with mqc.open(newline="", encoding="utf-8") as in_handle:
                reader = csv.DictReader(in_handle, delimiter="\t")
                if reader.fieldnames is None:
                    continue
                if fieldnames is None:
                    fieldnames = list(reader.fieldnames)
                elif fieldnames != list(reader.fieldnames):
                    raise ValueError(
                        f"Concordance MQC header mismatch in {mqc}: {reader.fieldnames}"
                    )
                rows.extend(reader)

        if fieldnames is None:
            fieldnames = [
                "Sample",
                "VariantClass",
                "InputSample",
                "TgtRegionSize",
                "TN",
                "FN",
                "TP",
                "FP",
                "Fscore",
                "Sensitivity-Recall",
                "Specificity",
                "FDR",
                "PPV",
                "Precision",
                "AltId",
                "ROI",
                "AllVarMeanDP",
                "CovBin",
                "Aligner",
                "Deduper",
                "SNVCaller",
            ]

        with out_path.open("w", newline="", encoding="utf-8") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
