import os

#  Approximating coverage eveness by norm cov stddev and coofvar
#  Early notes: https://docs.google.com/presentation/d/1b4_gStw5D8MDR89L95wvEuAr9I7Fm1Qn_LVREwNWrcM/edit#slide=id.gcd39261d0a_0_44
#  Math proof asserting NC stddev and/or coovar are good Evenness approximations:
#  paper: Evaluation of the evenness score in next-generation sequencing | Journal of Human Genetics
#     "the general evaluation presented in this paper reveals that in most circumstances the evenness score E of a NGS output can be predicted quite well by the standard deviation σ of the normalized data"
#



rule calc_coverage_evenness:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        # tsv=MDIR  + "{sample}/align/{alnr}/{ddup}/norm_cov_eveness/{sample}.{alnr}.{ddup}.norm_cov_eveness.mqc.tsv",
        mos_pre=MDIR   + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/{sample}.{alnr}.{ddup}.md",
        mqc=MDIR   + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/{sample}.{alnr}.{ddup}.md.norm_cov_eveness.mqc.tsv",
    container: None
    conda:
        "../envs/mosdepth_v0.1.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.norm_cov_eveness.bench.tsv"
    threads: config['calc_coverage_evenness']['threads']
    resources:
        vcpu=config['calc_coverage_evenness']['threads'],
        partition=config['calc_coverage_evenness']['partition'],
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/logs/norm_cov_eveness.mqc.log",
    params:
        cluster_sample=ret_sample,
        base_sample=lambda wildcards: wildcards.sample,
        stage_sample=lambda wildcards: day_stage_sample_id(
            wildcards.sample, wildcards.alnr, wildcards.ddup
        ),
        chrm_regions="1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22",
        l="{",
        r="}",
        chrm=GENOME_CHR_PREFIX,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        set +euo pipefail;
        rm -rf {output.mos_pre}* || echo nothingToDel;
        mkdir -p $( dirname {output.mos_pre} )/logs;
        touch {output.mos_pre};
        touch {log};
        echo "Sample\tbase_sample\tCHRM\tmeanRawCov\tmedianRawCov\tstdevRawCov\tRawCovCoefofvar\tNCmean\tNCmedian\tstdevNC\tNCcoefofvar\tpctEQ0\tpctLT5\tpctLT10\taligner\tdeduper" > {output.mqc};
        for i in {params.l}1..22{params.r};
        do
            echo "Processing {params.cluster_sample} Chrm:{params.chrm}$i";                            
            mosdepth -x  -Q 1 -T 0 -m -f {params.huref}  --by 50 -c {params.chrm}$i --threads 20 {output.mos_pre}.{params.chrm}$i {input.cram};
            touch {output.mos_pre}.{params.chrm}$i.regions.bed.gz;
            Rscript workflow/scripts/calc_norm_cov_sd.R {output.mos_pre}.{params.chrm}$i.regions.bed.gz "{params.base_sample}" "{params.stage_sample}.{params.chrm}$i" {params.chrm}$i {wildcards.alnr} {wildcards.ddup} | sed 's/\\"//g;' >> {output.mqc} ;
        done;
        ls {output};
        rm $(dirname {output.mos_pre})/*per-base* || echo 'rm perbase failed';
        """


localrules: 
    produce_cov_uniformity,

rule produce_cov_uniformity:  # TARGET: Produce cov eveness calcs, swapping out sambamba for mosdepth
    input:
        mqc=expand(MDIR       + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/{sample}.{alnr}.{ddup}.md.norm_cov_eveness.mqc.tsv", sample=SSAMPS, alnr=ALL_ALIGNERS, ddup=DDUP)
    container: None
    threads: 8
    output:
        mqc=MDIR+"other_reports/norm_cov_evenness_combo_mqc.tsv",
    shell:
        """
        set -euo pipefail;
        mkdir -p $(dirname {output});
        coverage_files=({input.mqc:q});
        if [[ "${#coverage_files[@]}" -eq 0 ]]; then
            echo "NO DATA FOUND" > {output.mqc};
        else
            first_file="${coverage_files[0]}";
            head -n 1 "$first_file" > {output.mqc};
            for source_path in "${coverage_files[@]}"; do
                tail -n +2 "$source_path" >> {output.mqc};
            done;
        fi;
        printf '%s\n' "${coverage_files[@]}";
        """
