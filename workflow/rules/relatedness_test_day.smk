import os

configfile: "config/relatedness.yaml"

SAMPLES = list(config["samples"].keys())
SOM_SITES = config["somalier"]["sites_vcf"]
REF = config["ref_fasta"]
GENOME_BUILD = config["somalier"].get("genome_build", "GRCh38")
HAPMAP = config["picard"]["haplotype_map"]


def sample_input(sample):
    """Return the configured path and input type for a sample."""
    entry = config["samples"][sample]
    if "bam" in entry:
        return entry["bam"], "bam"
    if "vcf" in entry:
        return entry["vcf"], "vcf"
    raise ValueError(f"Sample {sample} must have 'bam' or 'vcf' path.")


SomExtract = expand("results/somalier/extract/{sample}.somalier", sample=SAMPLES)


rule relatedness_all:
    input:
        "results/somalier/cohort_pairs.tsv",
        "results/somalier/cohort_groups.tsv",
        "results/somalier/cohort.html",
        "results/picard/crosscheck/metrics.txt",
        "results/picard/crosscheck/matrix.txt",
        expand(
            "results/conpair/{a}__{b}/concordance.tsv",
            zip,
            a=[x["samples"][0] for x in config.get("expected", []) if x["relationship"] == "tumor_normal"],
            b=[x["samples"][1] for x in config.get("expected", []) if x["relationship"] == "tumor_normal"],
        ),
        *(
            ["results/peddy/peddy.html"]
            if config.get("peddy", {}).get("enabled", False)
            else []
        ),
        "results/relatedness_qc/relatedness_summary.tsv",
        "results/relatedness_qc/relatedness_report.html",


#######################################################################
# SOMALIER
#######################################################################

rule somalier_extract:
    """Build per-sample fingerprint from BAM/CRAM (preferred) or VCF."""

    output:
        "results/somalier/extract/{sample}.somalier"
    params:
        sites=SOM_SITES,
        build=GENOME_BUILD
    threads: 4
    conda: "../envs/somalier.yaml"
    shell:
        r"""
        if [[ "{sample_input(wildcards.sample)[1]}" == "bam" ]]; then
            somalier extract \
              --sites {params.sites} \
              --fasta {REF} \
              --genome-build {params.build} \
              -o results/somalier/extract/{wildcards.sample} \
              {sample_input(wildcards.sample)[0]}
        else
            somalier extract \
              --sites {params.sites} \
              --genome-build {params.build} \
              -o results/somalier/extract/{wildcards.sample} \
              {sample_input(wildcards.sample)[0]} \
              --unknown
        fi
        """


rule somalier_relate:
    input:
        SomExtract
    output:
        pairs="results/somalier/cohort_pairs.tsv",
        groups="results/somalier/cohort_groups.tsv",
        html="results/somalier/cohort.html"
    conda: "../envs/somalier.yaml"
    shell:
        r"""
        somalier relate results/somalier/extract/*.somalier -o results/somalier/cohort
        """


#######################################################################
# PICARD CrosscheckFingerprints
#######################################################################

rule picard_build_input_list:
    output:
        "results/picard/crosscheck/input.list"
    run:
        os.makedirs("results/picard/crosscheck", exist_ok=True)
        with open(output[0], "w") as handle:
            for sample in SAMPLES:
                path, _ = sample_input(sample)
                handle.write(path + "\n")


rule picard_crosscheck:
    input:
        "results/picard/crosscheck/input.list"
    output:
        metrics="results/picard/crosscheck/metrics.txt",
        matrix="results/picard/crosscheck/matrix.txt"
    params:
        hapmap=HAPMAP
    conda: "../envs/picard.yaml"
    shell:
        r"""
        picard CrosscheckFingerprints \
          INPUT_LIST={input} \
          HAPLOTYPE_MAP={params.hapmap} \
          CROSSCHECK_BY=FILE \
          OUTPUT={output.metrics} \
          MATRIX_OUTPUT={output.matrix} \
          EXPECT_ALL_GROUPS_TO_MATCH=false \
          MOLECULAR_INDEX_TAG= \
          VALIDATION_STRINGENCY=SILENT
        """


#######################################################################
# CONPAIR (only for declared tumor_normal expected pairs)
#######################################################################


def tn_pairs():
    return [
        entry["samples"]
        for entry in config.get("expected", [])
        if entry["relationship"] == "tumor_normal"
    ]


rule conpair_mpileup:
    input:
        tumor=lambda wildcards: sample_input(wildcards.t)[0],
        normal=lambda wildcards: sample_input(wildcards.n)[0]
    output:
        tumor="results/conpair/{t}__{n}/tumor.mpileup",
        normal="results/conpair/{t}__{n}/normal.mpileup"
    params:
        bed=config["conpair"]["snp_positions_bed"],
        mapq=config["conpair"]["min_mapq"],
        baseq=config["conpair"]["min_baseq"]
    conda: "../envs/conpair.yaml"
    threads: 4
    shell:
        r"""
        mkdir -p results/conpair/{wildcards.t}__{wildcards.n}
        samtools mpileup -l {params.bed} -q {params.mapq} -Q {params.baseq} -f {REF} {input.tumor} > {output.tumor}
        samtools mpileup -l {params.bed} -q {params.mapq} -Q {params.baseq} -f {REF} {input.normal} > {output.normal}
        """


rule conpair_parse:
    input:
        tumor="results/conpair/{t}__{n}/tumor.mpileup",
        normal="results/conpair/{t}__{n}/normal.mpileup"
    output:
        tparsed="results/conpair/{t}__{n}/tumor.parsed",
        nparsed="results/conpair/{t}__{n}/normal.parsed"
    conda: "../envs/conpair.yaml"
    shell:
        r"""
        parse_pileup.py -i {input.tumor} -o {output.tparsed}
        parse_pileup.py -i {input.normal} -o {output.nparsed}
        """


rule conpair_compare:
    input:
        tparsed="results/conpair/{t}__{n}/tumor.parsed",
        nparsed="results/conpair/{t}__{n}/normal.parsed"
    output:
        conctsv="results/conpair/{t}__{n}/concordance.tsv",
        summary="results/conpair/{t}__{n}/summary.txt"
    conda: "../envs/conpair.yaml"
    shell:
        r"""
        compare.py -t {input.tparsed} -n {input.nparsed} -o results/conpair/{wildcards.t}__{wildcards.n}/res
        if [[ -f results/conpair/{wildcards.t}__{wildcards.n}/res_concordance_summary.txt ]]; then
            cp results/conpair/{wildcards.t}__{wildcards.n}/res_concordance_summary.txt {output.summary}
        fi
        if [[ -f results/conpair/{wildcards.t}__{wildcards.n}/res_concordance_details.txt ]]; then
            cp results/conpair/{wildcards.t}__{wildcards.n}/res_concordance_details.txt {output.conctsv}
        fi
        """


#######################################################################
# PEDDY (optional; requires a joint VCF)
#######################################################################


rule peddy:
    input:
        vcf=lambda wildcards: config.get("peddy", {}).get("joint_vcf", ""),
        ped=lambda wildcards: config.get("peddy", {}).get("ped", "")
    output:
        html="results/peddy/peddy.html"
    conda: "../envs/peddy.yaml"
    threads: 4
    run:
        if not config.get("peddy", {}).get("enabled", False):
            os.makedirs("results/peddy", exist_ok=True)
            with open(output.html, "w", encoding="utf-8") as handle:
                handle.write("<html><body>Peddy disabled</body></html>")
        else:
            shell(
                """
                mkdir -p results/peddy
                peddy -p {threads} --plot --prefix results/peddy/peddy {input.vcf} {input.ped}
                """
            )


#######################################################################
# FINAL MERGED REPORT
#######################################################################


rule relatedness_report:
    input:
        som_pairs="results/somalier/cohort_pairs.tsv",
        som_groups="results/somalier/cohort_groups.tsv",
        picard_metrics="results/picard/crosscheck/metrics.txt",
        picard_matrix="results/picard/crosscheck/matrix.txt",
        conpair=expand(
            "results/conpair/{a}__{b}/concordance.tsv",
            zip,
            a=[x["samples"][0] for x in config.get("expected", []) if x["relationship"] == "tumor_normal"],
            b=[x["samples"][1] for x in config.get("expected", []) if x["relationship"] == "tumor_normal"],
        ),
    output:
        tsv="results/relatedness_qc/relatedness_summary.tsv",
        html="results/relatedness_qc/relatedness_report.html"
    params:
        cfg="config/relatedness.yaml"
    conda: "../envs/report.yaml"
    script:
        "../scripts/relatedness_report.py"


rule produce_relatedness:  # TARGET : Produce relatedness analysis
    input:
        "results/relatedness_qc/relatedness_summary.tsv",
        "results/relatedness_qc/relatedness_report.html"
