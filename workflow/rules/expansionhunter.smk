import csv
import os

from snakemake.exceptions import WorkflowError


EXPANSIONHUNTER_CFG = config["expansionhunter"]
EXPANSIONHUNTER_ALIGNERS = {"sent", "sentcg", "ug"}
EXPANSIONHUNTER_DEDUP_ALIGNERS = {"sent", "sentcg"}
EXPANSIONHUNTER_CATALOG_KEY = "disease_loci_hg38_stranger_json"


def _expansionhunter_selected_aligners():
    return sorted(a for a in ALIGNERS if a in EXPANSIONHUNTER_ALIGNERS)


def _expansionhunter_sample_row(sample):
    row = samples[samples["sample"] == sample]
    if row.empty:
        raise WorkflowError(f"ExpansionHunter could not find sample metadata for {sample}.")
    return row.iloc[0]


def _expansionhunter_clean_manifest_value(value):
    text = str(value or "").strip()
    if text.lower() in {"", "na", "none"}:
        return ""
    return text


def _expansionhunter_sample_supports_aligner(sample, alnr):
    row = _expansionhunter_sample_row(sample)
    seq_vendor = _expansionhunter_clean_manifest_value(row.get("SEQ_VENDOR", "")).upper()
    seq_platform = _expansionhunter_clean_manifest_value(row.get("SEQ_PLATFORM", "")).upper()
    ilmn_r1 = _expansionhunter_clean_manifest_value(row.get("ILMN_R1_PATH", ""))
    ultima_cram = _expansionhunter_clean_manifest_value(row.get("ULTIMA_CRAM", ""))
    ultima_cram_aligner = _expansionhunter_clean_manifest_value(
        row.get("ULTIMA_CRAM_ALIGNER", "")
    ).lower()

    if alnr == "sent":
        return bool(ilmn_r1 and seq_vendor in {"ILMN", "ILLUMINA"})
    if alnr == "sentcg":
        return bool(ilmn_r1 and (seq_vendor in {"CG", "MGI"} or "T7" in seq_platform))
    if alnr == "ug":
        return bool(ultima_cram and ultima_cram_aligner == "ug")
    return False


def _expansionhunter_catalog_path(wildcards=None):
    try:
        return config["supporting_files"]["files"]["strchive"][EXPANSIONHUNTER_CATALOG_KEY]["name"]
    except KeyError as exc:
        raise WorkflowError(
            "ExpansionHunter requires supporting_files.files.strchive."
            f"{EXPANSIONHUNTER_CATALOG_KEY}.name for this genome build."
        ) from exc


def _expansionhunter_target_paths(suffix):
    selected = _expansionhunter_selected_aligners()
    if not selected:
        raise WorkflowError(
            "produce_expansionhunter requires at least one of aligners=['sent','sentcg','ug']."
        )

    paths = []
    non_na_dedupers = sorted(d for d in DDUP if d != "na")
    for alnr in selected:
        if alnr in EXPANSIONHUNTER_DEDUP_ALIGNERS:
            if not non_na_dedupers:
                raise WorkflowError(
                    f"ExpansionHunter for {alnr} requires a non-na deduper; set dedupers=['dmd'] or another real deduper."
                )
            for ddup in non_na_dedupers:
                for sample in SSAMPS:
                    if not _expansionhunter_sample_supports_aligner(sample, alnr):
                        continue
                    paths.extend(
                        expand(
                            MDIR
                            + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh."
                            + suffix,
                            sample=[sample],
                            alnr=[alnr],
                            ddup=[ddup],
                        )
                    )
        elif alnr == "ug":
            for sample in SSAMPS:
                if not _expansionhunter_sample_supports_aligner(sample, alnr):
                    continue
                paths.extend(
                    expand(
                        MDIR
                        + "{sample}/align/ug/na/htd/expansionhunter/{sample}.ug.na.eh."
                        + suffix,
                        sample=[sample],
                    )
                )
    if not paths:
        raise WorkflowError(
            "ExpansionHunter found no manifest-compatible sample/aligner pairs for "
            f"aligners={selected}. Check SEQ_VENDOR, SEQ_PLATFORM, and ULTIMA_CRAM_ALIGNER."
        )
    return paths


def _expansionhunter_sample_sex(wildcards):
    sex = str(
        config["sample_info"].get(wildcards.sample, {}).get("biological_sex", "na")
    ).strip().lower()
    if sex not in {"male", "female"}:
        raise WorkflowError(
            f"ExpansionHunter requires biological sex for sample {wildcards.sample}; "
            f"missing or unknown value '{sex}'."
        )
    return sex


def _expansionhunter_validate_pair(wildcards):
    if wildcards.alnr not in EXPANSIONHUNTER_ALIGNERS:
        raise WorkflowError(
            f"ExpansionHunter supports alnr sent, sentcg, or ug; found {wildcards.alnr}."
        )
    if wildcards.alnr in EXPANSIONHUNTER_DEDUP_ALIGNERS and wildcards.ddup == "na":
        raise WorkflowError(
            f"ExpansionHunter for {wildcards.alnr} must consume deduped CRAMs; ddup=na is invalid."
        )
    if wildcards.alnr == "ug" and wildcards.ddup != "na":
        raise WorkflowError(
            f"ExpansionHunter for ug must consume the normalized no-dedup CRAM; found ddup={wildcards.ddup}."
        )
    return "ok"


rule expansionhunter_call:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        json=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.json",
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.vcf",
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.bam",
    params:
        pair_ok=_expansionhunter_validate_pair,
        sex=_expansionhunter_sample_sex,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        variant_catalog=_expansionhunter_catalog_path,
        output_prefix=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh",
        analysis_mode=EXPANSIONHUNTER_CFG["analysis_mode"],
        region_extension_length=EXPANSIONHUNTER_CFG["region_extension_length"],
        extra_args=EXPANSIONHUNTER_CFG.get("extra_args", ""),
        realigned_bam=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh_realigned.bam",
        cluster_sample=ret_sample,
    threads: EXPANSIONHUNTER_CFG["threads"]
    resources:
        threads=EXPANSIONHUNTER_CFG["threads"],
        vcpu=EXPANSIONHUNTER_CFG["threads"],
        mem_mb=EXPANSIONHUNTER_CFG["mem_mb"],
        partition=EXPANSIONHUNTER_CFG["partition"],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.expansionhunter.bench.tsv"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/logs/{sample}.{alnr}.{ddup}.expansionhunter.log"
    conda:
        EXPANSIONHUNTER_CFG["env_yaml"]
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.json:q}) $(dirname {log:q})
        : > {log:q}
        test {params.pair_ok:q} = ok
        test -s {input.cram:q}
        test -s {input.crai:q}
        test -s {params.huref:q}
        test -s {params.variant_catalog:q}
        unset LD_PRELOAD
        ExpansionHunter \
          --reads {input.cram:q} \
          --reference {params.huref:q} \
          --variant-catalog {params.variant_catalog:q} \
          --output-prefix {params.output_prefix:q} \
          --sex {params.sex:q} \
          --threads {threads} \
          --region-extension-length {params.region_extension_length} \
          --analysis-mode {params.analysis_mode:q} \
          {params.extra_args} \
          >> {log:q} 2>&1
        test -s {params.realigned_bam:q}
        mv {params.realigned_bam:q} {output.bam:q}
        test -s {output.json:q}
        test -s {output.vcf:q}
        test -s {output.bam:q}
        """


rule expansionhunter_json_to_tsv:
    input:
        json=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.json",
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.vcf",
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.bam",
    output:
        tsv=MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/{sample}.{alnr}.{ddup}.eh.tsv",
    params:
        catalog=_expansionhunter_catalog_path,
        cluster_sample=ret_sample,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/expansionhunter/logs/{sample}.{alnr}.{ddup}.expansionhunter_parse.log"
    threads: 1
    resources:
        threads=1,
        vcpu=1,
        mem_mb=2000,
        partition=EXPANSIONHUNTER_CFG["partition"],
    conda:
        config["vanilla"]["env_yaml"]
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.tsv:q}) $(dirname {log:q})
        python bin/util/parse_expansionhunter_json.py \
          {input.json:q} \
          {params.catalog:q} \
          --sample-id {wildcards.sample:q} \
          --aligner {wildcards.alnr:q} \
          --deduper {wildcards.ddup:q} \
          --output {output.tsv:q} \
          > {log:q} 2>&1
        test -s {output.tsv:q}
        """


localrules:
    expansionhunter_gather,
    expansionhunter_multiqc,
    produce_expansion_hunter,
    produce_expansionhunter,
    produce_expansionhunter_multiqc,


rule expansionhunter_gather:
    input:
        lambda wildcards: _expansionhunter_target_paths("tsv")
    output:
        MDIR + "other_reports/expansionhunter_mqc.tsv"
    log:
        MDIR + "other_reports/logs/expansionhunter_gather.log"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        os.makedirs(os.path.dirname(str(log[0])), exist_ok=True)
        with open(log[0], "w") as log_fh:
            fieldnames = None
            wrote_header = False
            with open(output[0], "w", newline="") as out_fh:
                for path in input:
                    with open(path) as in_fh:
                        reader = csv.DictReader(in_fh, delimiter="\t")
                        if fieldnames is None:
                            fieldnames = reader.fieldnames
                            writer = csv.DictWriter(
                                out_fh, fieldnames=fieldnames, delimiter="\t"
                            )
                            writer.writeheader()
                            wrote_header = True
                        for row in reader:
                            writer.writerow(row)
                    log_fh.write(f"gathered {path}\n")
            if not wrote_header:
                raise WorkflowError("ExpansionHunter gather had no TSV inputs to write.")


rule expansionhunter_multiqc:
    input:
        aggregate=MDIR + "other_reports/expansionhunter_mqc.tsv",
        config="config/external_tools/multiqc_config.yaml",
    output:
        html=MDIR + "reports/expansionhunter.multiqc.html"
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    benchmark:
        MDIR + "benchmarks/all.expansionhunter_multiqc.bench.tsv"
    log:
        MDIR + "reports/logs/expansionhunter_multiqc.log"
    params:
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        gtag=config["gittag"],
        cluster_sample="expansionhunter_multiqc",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        : > {log:q}
        python workflow/scripts/multiqc_log_guard.py --log-dir {MDIR:q}other_reports/logs >> {log:q} 2>&1
        multiqc --version >> {log:q} 2>&1 || true
        multiqc --interactive -m custom_content -f \
          --config {input.config:q} \
          --filename $(basename {output.html:q}) \
          -o $(dirname {output.html:q}) \
          -i 'ExpansionHunter MultiQC Report' \
          -b 'https://github.com/Daylily-Informatics/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          $(dirname {input.aggregate:q})/.. >> {log:q} 2>&1
        """


rule produce_expansion_hunter:  # TARGET: run ExpansionHunter for ILMN, Complete Genomics/MGI, and Ultima short-read CRAMs
    input:
        lambda wildcards: _expansionhunter_target_paths("tsv")


rule produce_expansionhunter:  # TARGET: alias for produce_expansion_hunter
    input:
        lambda wildcards: _expansionhunter_target_paths("tsv")


rule produce_expansionhunter_multiqc:  # TARGET: run ExpansionHunter and focused MultiQC report
    input:
        MDIR + "reports/expansionhunter.multiqc.html"
