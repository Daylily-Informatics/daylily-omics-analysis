######### GENOTYPE-FREE SITE MIX CONTAMINATION SCREEN
# - Estimates same-species contamination without target genotype.
# - Optional donor attribution uses a candidate BAM/CRAM/VCF manifest.

rule site_mix_contam:
    input:
        cram = MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai = MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        sites_vcf = config["site_mix_contam"]["sites_vcf"],
        sites_vcf_tbi = lambda wildcards: config["site_mix_contam"]["sites_vcf"] + ".tbi",
        ref_fa = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai = lambda wildcards: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        tsv = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
        donors = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix_donors.tsv",
        stamp = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.done",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/logs/{sample}.{alnr}.{ddup}.site_mix.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.site_mix_contam.bench.tsv"
    conda:
        config["site_mix_contam"]["env_yaml"]
    threads: config["site_mix_contam"]["threads"]
    resources:
        vcpu = config["site_mix_contam"]["threads"],
        partition = config["site_mix_contam"]["partition"],
    params:
        cluster_sample = ret_sample,
        candidate_manifest = config["site_mix_contam"]["candidate_manifest"],
        min_depth = config["site_mix_contam"]["min_depth"],
        max_depth = config["site_mix_contam"]["max_depth"],
        min_sites = config["site_mix_contam"]["min_sites"],
        min_af = config["site_mix_contam"]["min_af"],
        max_af = config["site_mix_contam"]["max_af"],
        max_sites = config["site_mix_contam"]["max_sites"],
        min_base_quality = config["site_mix_contam"]["min_base_quality"],
        min_mapping_quality = config["site_mix_contam"]["min_mapping_quality"],
        donor_min_depth = config["site_mix_contam"]["donor_min_depth"],
        max_contamination = config["site_mix_contam"]["max_contamination"],
        grid_step = config["site_mix_contam"]["grid_step"],
        max_candidate_sources = config["site_mix_contam"]["max_candidate_sources"],
    shell:
        r"""
        set -euo pipefail

        outdir="$(dirname {output.tsv})"
        mkdir -p "${{outdir}}" "${{outdir}}/logs"

        candidate_args=()
        if [[ -n "{params.candidate_manifest}" ]]; then
            candidate_args=(--candidate-manifest "{params.candidate_manifest}")
        fi

        bin/util/genotype_free_contam_estimator.py \
          --sample-id "{params.cluster_sample}" \
          --bam {input.cram} \
          --reference {input.ref_fa} \
          --sites-vcf {input.sites_vcf} \
          --output {output.tsv} \
          --donor-output {output.donors} \
          --min-depth {params.min_depth} \
          --max-depth {params.max_depth} \
          --min-sites {params.min_sites} \
          --min-af {params.min_af} \
          --max-af {params.max_af} \
          --max-sites {params.max_sites} \
          --min-base-quality {params.min_base_quality} \
          --min-mapping-quality {params.min_mapping_quality} \
          --donor-min-depth {params.donor_min_depth} \
          --max-contamination {params.max_contamination} \
          --grid-step {params.grid_step} \
          --max-candidate-sources {params.max_candidate_sources} \
          "${{candidate_args[@]}}" \
          > {log} 2>&1

        test -s {output.tsv}
        test -s {output.donors}
        touch {output.stamp}
        """


localrules:
    produce_site_mix_contam_estimate,

rule produce_site_mix_contam_estimate:  # TARGET: Produce genotype-free site-mix contamination estimates
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        )
