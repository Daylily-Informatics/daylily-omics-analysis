import os

# #### seqfu
# -----------
#   Super efficent fasta/q manipulations
#
# github:  https://github.com/telatin/seqfu2
# paper: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8148589/


rule seqfu:
    input:
        #DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        #fqs=get_raw_fastqs,
        #f1=getR1sS,  # method defined in fastp.smk
        #f2=getR2sS,  # method defined in fastp.smk
        f1=get_raw_fastq_qc_R1s,
        f2=get_raw_fastq_qc_R2s,
    output:
        mqc_r1=f"{MDIR}" + "{sample}/seqqc/seqfu/{sample}.seqfuR1.mqc.tsv",
        mqc_r2=f"{MDIR}" + "{sample}/seqqc/seqfu/{sample}.seqfuR2.mqc.tsv",
        sent=MDIR + "{sample}/seqqc/seqfu/{sample}.seqfu.done",
    benchmark:
        f"{MDIR}" + "{sample}/benchmarks/{sample}.seqfu.bench.tsv"
    threads: config["seqfu"]["threads"]
    params:
        cluster_sample=ret_sample,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["seqfu"]
        else config["seqfu"]["ld_preload"],
    log:
        f"{MDIR}" + "{sample}/seqqc/seqfu/{sample}.seqfu.log",
    conda:
        config["seqfu"]["env_yaml"]
    shell:
        """
        mkdir -p $(dirname {output.mqc_r1});
        r1_inputs=({input.f1:q})
        r2_inputs=({input.f2:q})
        if [[ "${{#r1_inputs[@]}}" -eq 0 && "${{#r2_inputs[@]}}" -eq 0 ]]; then
            printf 'SKIP: seqfu found no paired FASTQ inputs for %s; likely CRAM/BAM-only or manifest FASTQ path is na.\n' "{wildcards.sample}" > {log}
            printf 'NO DATA FOUND\n' > {output.mqc_r1}
            printf 'NO DATA FOUND\n' > {output.mqc_r2}
            touch {output.sent}
            exit 0
        fi
        ( cat  <(gzip -dc -- {input.f1} ) | env {params.ld_preload} seqfu stats --nice -b  --verbose --multiqc ./{output.mqc_r1} - &
        cat <(gzip -dc -- {input.f2} ) | env {params.ld_preload} seqfu stats --nice -b  --verbose --multiqc ./{output.mqc_r2} - &
        wait;
        touch {output.sent};) > {log}
        ls {output};
        """


localrules:
    compile_seqfu,


rule compile_seqfu:
    input:
        expand(MDIR + "{sample}/seqqc/seqfu/{sample}.seqfu.done", sample=FASTQ_QC_SAMPS),
    container:
        None
    output:
        mqc1=MDIR + "other_reports/seqfu1.mqc.tsv",
        mqc2=MDIR + "other_reports/seqfu2.mqc.tsv",
        mqc=MDIR + "other_reports/seqfu_mqc.tsv",
        d=MDIR + "logs/seqfu.done",
    log:
        MDIR + "logs/compile_seqfu.log"
    benchmark:
        MDIR + "benchmarks/compile_seqfu.bench.tsv"
    params:
        mdir=MDIR,
    shell:
        """mkdir -p {MDIR}other_reports $(dirname {output.d});
        mapfile -t r1_files < <(find {params.mdir} -name '*seqfuR1.mqc.tsv' -print | sort);
        if [[ "${{#r1_files[@]}}" -eq 0 ]]; then
            echo "NO DATA FOUND" > {output.mqc1};
        else
            single_file="${{r1_files[0]}}";
            head -n 35 "$single_file" > {output.mqc1};
            for source_path in "${{r1_files[@]}}"; do
                tail -n 1 "$source_path" >> {output.mqc1};
            done;
        fi;

        mapfile -t r2_files < <(find {params.mdir} -name '*seqfuR2.mqc.tsv' -print | sort);
        if [[ "${{#r2_files[@]}}" -eq 0 ]]; then
            echo "NO DATA FOUND" > {output.mqc2};
        else
            single_file2="${{r2_files[0]}}";
            head -n 35 "$single_file2" > {output.mqc2};
            for source_path in "${{r2_files[@]}}"; do
                tail -n 1 "$source_path" >> {output.mqc2};
            done;
        fi;
        printf "Sample\\tbase_sample\\tread\\tsource_path\\n" > {output.mqc};
        for source_path in "${{r1_files[@]}}"; do
            base_sample=$(basename "$source_path" .seqfuR1.mqc.tsv);
            printf "%s.R1\\t%s\\tR1\\t%s\\n" "$base_sample" "$base_sample" "$source_path" >> {output.mqc};
        done;
        for source_path in "${{r2_files[@]}}"; do
            base_sample=$(basename "$source_path" .seqfuR2.mqc.tsv);
            printf "%s.R2\\t%s\\tR2\\t%s\\n" "$base_sample" "$base_sample" "$source_path" >> {output.mqc};
        done;
        touch {output.d};

        """


localrules:
    produce_seqfu,


rule produce_seqfu:  # TARGET: seqfu output
    input:
        MDIR + "logs/seqfu.done",
    log:
        MDIR + "logs/produce_seqfu.log"
    benchmark:
        "logs/benchmarks/produce_seqfu.bench.tsv"
    container:
        None
