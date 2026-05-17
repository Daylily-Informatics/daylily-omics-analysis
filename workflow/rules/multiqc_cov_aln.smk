# ##### Multiqc For Alignment and Cov metrics#


rule multiqc_cov_aln:  # TARGET : Run Alignment and Generate Alignment and Coverage Multiqc Report. No Variant Calling Happens, Progress Stops Here.
    input:
        f"{MDIR}other_reports/norm_cov_evenness_combo_mqc.tsv",
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/cov_calcs_complete.done",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
    output:
        html=f"{MDIRreportsd}ALNandSeqQC_{RU[0]}_{EX[0]}.multiqc.html",
    threads: 7  # config["multiqc"]["threads"]
    benchmark:
        MDIR + "benchmarks/all.mqc_cov_aln.bench.tsv"
    log:
        MDIR + "logs/multiqc_cov_aln.log",
    params:
        fn=f"ALNandSeqQC_{RU[0]}_{EX[0]}.multiqc.html",
        odir=MDIRreportsd,
        macro_cfg=config["multiqc"]["config_yaml"],
        micro_cfg=config["multiqc"]["aln_qc"]["config_yaml"],
        gtag=config["gittag"],
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        cluster_sample=f"{RU[0]}_{EX[0]}",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        "(multiqc --version > {log} 2>&1 || true; multiqc --interactive -x '*.js' -x '*bench.tsv' -x '*.bam' -x '*.fastq.gz' -x '*multiqc*' -x '*pyc' -x '*.fastq.gz'  -x  '*impute*glm*' -f -i 'SEQQC / COVERAGE & ALIGNMENT REPORT' -p  -b '{RU[0]}_{EX[0]} ___ {params.gbranch} {params.gtag} {params.ghash}' --sample-filters config/external_tools/multiqc_samplebtn_lcwgs.tsv -n {params.fn} -o {params.odir} --profile-runtime -c {params.micro_cfg} -c {params.macro_cfg} {MDIR} >> {log} 2>&1) || (echo 'Multiqc Exited With: '$? && time sleep 1 && echo done) "


localrules:
    cov_aln_qc,


rule cov_aln_qc:
    input:
        expand(MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.complete",
               sample=SSAMPS,
               alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/{sample}.{alnr}.{ddup}.md",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.json",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.tsv",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
        #expand(
        #    MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2.tsv",
        #    sample=SSAMPS,
        #    alnr=ALL_ALIGNERS,
        #),
        f"{MDIR}other_reports/alignstats_bsummary.tsv",
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.sort.bed",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/goleft.done",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
            ddup=DDUP,
        ),
	#        expand(
        #    MDIR + "{sample}/align/{alnr}/alignqc/sentmetrics/sm/{sample}.{alnr}.mrkdup.metrics.complete",
        #    sample=SSAMPS,
        #    alnr=ALL_ALIGNERS
        #),
	#        expand(MDIR + "{sample}/seqqc/fastv/{sample}.fastv.html", sample=SSAMPS),
        #expand(MDIR + "{sample}/seqqc/fastqc/{sample}.fastqc.done", sample=SSAMPS),
        #expand(MDIR + "{sample}/seqqc/kat/{sample}.kat.done", sample=SSAMPS),
        #expand(MDIR + "{sample}/seqqc/fastp/{sample}.fastp.done", sample=SSAMPS),
        #MDIR+"logs/seqfu.done",
    output:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/cov_calcs_complete.done",
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/logs/",
    conda:
        config["vanilla"]["env_yaml"]
    shell:
        "echo 'Coverage Calcs Complete' > {log} 2>&1;"
        "touch {output};"
        "ls {output};"
