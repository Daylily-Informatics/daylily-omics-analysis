import os, yaml

configfile: "config/relatedness.yaml"

SAMPLES = list(config["samples"].keys())
SOM_SITES = config["somalier"]["sites_vcf"]
REF = config["ref_fasta"]
GENOME_BUILD = config["somalier"].get("genome_build", "GRCh38")
HAPMAP = config["picard"]["haplotype_map"]

# Decide input type for each sample
def sample_input(sample):
    ent = config["samples"][sample]
    if "bam" in ent:
        return ent["bam"], "bam"
    elif "vcf" in ent:
        return ent["vcf"], "vcf"
    else:
        raise ValueError(f"Sample {sample} must have 'bam' or 'vcf' path.")

# Somalier extract outputs
SomExtract = expand("results/somalier/extract/{samp}.somalier", samp=SAMPLES)

rule relatedness_all:
    input:
        # Somalier relatedness
        "results/somalier/cohort_pairs.tsv",
        "results/somalier/cohort_groups.tsv",
        "results/somalier/cohort.html",
        # Picard crosscheck (matrix + metrics)
        "results/picard/crosscheck/metrics.txt",
        "results/picard/crosscheck/matrix.txt",
        # Conpair for declared tumor/normal pairs (optional – created only for pairs in expected list)
        expand("results/conpair/{a}__{b}/concordance.tsv",
               zip, a=[x["samples"][0] for x in config["expected"] if x["relationship"]=="tumor_normal"],
                    b=[x["samples"][1] for x in config["expected"] if x["relationship"]=="tumor_normal"]),
        # Optional peddy
        *( ["results/peddy/peddy.html"] if config.get("peddy", {}).get("enabled", False) else [] ),
        # Final merged report
        "results/relatedness_qc/relatedness_summary.tsv",
        "results/relatedness_qc/relatedness_report.html"

#######################################################################
# SOMALIER
#######################################################################

rule somalier_extract:
    """
    Build per-sample fingerprint from BAM/CRAM (preferred) or VCF.
    """
    output: "results/somalier/extract/{samp}.somalier"
    params:
        sites=SOM_SITES,
        build=GENOME_BUILD
    threads: 4
    conda: "../envs/somalier_v0.1.yaml"
    shell:
        r"""
        if [[ "{sample_input(wildcards.samp)[1]}" == "bam" ]]; then
            somalier extract \
              --sites {params.sites} \
              --fasta {REF} \
              --genome-build {params.build} \
              -o results/somalier/extract/{wildcards.samp} \
              {sample_input(wildcards.samp)[0]}
        else
            somalier extract \
              --sites {params.sites} \
              --genome-build {params.build} \
              -o results/somalier/extract/{wildcards.samp} \
              {sample_input(wildcards.samp)[0]} \
              --unknown   # treat missing as hom-ref when VCF lacks some sites
        fi
        """

rule somalier_relate:
    input: SomExtract
    output:
        pairs="results/somalier/cohort_pairs.tsv",
        groups="results/somalier/cohort_groups.tsv",
        html="results/somalier/cohort.html"
    conda: "../envs/somalier_v0.1.yaml"
    shell:
        r"""
        somalier relate results/somalier/extract/*.somalier -o results/somalier/cohort
        """

#######################################################################
# PICARD CrosscheckFingerprints
#######################################################################

# Build a file list for picard (one input per line)
rule picard_build_input_list:
    output: "results/picard/crosscheck/input.list"
    run:
        os.makedirs("results/picard/crosscheck", exist_ok=True)
        with open(output[0], "w") as fh:
            for s in SAMPLES:
                path, typ = sample_input(s)
                fh.write(path + "\n")

rule picard_crosscheck:
    input: "results/picard/crosscheck/input.list"
    output:
        metrics="results/picard/crosscheck/metrics.txt",
        matrix="results/picard/crosscheck/matrix.txt"
    params:
        hapmap=HAPMAP
    conda: "../envs/picard_relatedness_v0.1.yaml"
    shell:
        r"""
        # CROSSCHECK_BY=FILE => all-vs-all across inputs in list
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
    return [x["samples"] for x in config["expected"] if x["relationship"]=="tumor_normal"]

rule conpair_mpileup:
    input:
        tumor=lambda wc: sample_input(wc.t)[0],
        normal=lambda wc: sample_input(wc.n)[0]
    output:
        tumor="results/conpair/{t}__{n}/tumor.mpileup",
        normal="results/conpair/{t}__{n}/normal.mpileup"
    params:
        bed=config["conpair"]["snp_positions_bed"],
        mapq=config["conpair"]["min_mapq"],
        baseq=config["conpair"]["min_baseq"]
    conda: "../envs/conpair_v0.1.yaml"
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
    conda: "../envs/conpair_v0.1.yaml"
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
    conda: "../envs/conpair_v0.1.yaml"
    shell:
        r"""
        compare.py -t {input.tparsed} -n {input.nparsed} -o results/conpair/{wildcards.t}__{wildcards.n}/res
        # Conpair writes multiple files; normalize to our outputs:
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
rule conpair_mpileup_all:
    input:
        expand(
            "results/conpair/{t}__{n}/tumor.mpileup",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        ),
        expand(
            "results/conpair/{t}__{n}/normal.mpileup",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        )

rule conpair_parse_all:
    input:
        expand(
            "results/conpair/{t}__{n}/tumor.parsed",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        ),
        expand(
            "results/conpair/{t}__{n}/normal.parsed",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        )

rule conpair_compare_all:
    input:
        expand(
            "results/conpair/{t}__{n}/concordance.tsv",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        ),
        expand(
            "results/conpair/{t}__{n}/summary.txt",
            t=[p[0] for p in tn_pairs()],
            n=[p[1] for p in tn_pairs()]
        )

rule peddy_relatedness:
    input:
        vcf=lambda wc: config["peddy"]["joint_vcf"],
        ped=lambda wc: config["peddy"]["ped"]
    output:
        html="results/peddy/peddy.html"
    conda: "../envs/peddy_relatedness_v0.1.yaml"
    threads: 4
    shell:
        r"""
        mkdir -p results/peddy
        if [ "{config[peddy][enabled]}" = "False" ] || [ -z "{config[peddy][enabled]}" ]; then
            echo "<html><body>Peddy disabled</body></html>" > {output.html}
        else
            peddy -p {threads} --plot --prefix results/peddy/peddy {input.vcf} {input.ped}
        fi
        """


#######################################################################
# FINAL MERGED REPORT
#######################################################################

rule relatedness_report:
    input:
        som_pairs="results/somalier/cohort_pairs.tsv",
        som_groups="results/somalier/cohort_groups.tsv",
        picard_metrics="results/picard/crosscheck/metrics.txt",
        picard_matrix="results/picard/crosscheck/matrix.txt",
        conpair=expand("results/conpair/{a}__{b}/concordance.tsv",
                       zip, a=[x["samples"][0] for x in config["expected"] if x["relationship"]=="tumor_normal"],
                            b=[x["samples"][1] for x in config["expected"] if x["relationship"]=="tumor_normal"]),
    output:
        tsv="results/relatedness_qc/relatedness_summary.tsv",
        html="results/relatedness_qc/relatedness_report.html"
    params:
        cfg="config/relatedness.yaml"
    conda: "../envs/relatedness_report_v0.1.yaml"
    script:
        "../scripts/relatedness_report.py"

rule relatedness:  # TARGET:  relatedness_report
    """
    Convenience entry point — call this rule to build the full relatedness
    report and all required intermediate outputs.
    """
    input:
        "results/relatedness_qc/relatedness_summary.tsv",
        "results/relatedness_qc/relatedness_report.html"
