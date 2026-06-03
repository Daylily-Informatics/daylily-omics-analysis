##### MANTA A VENERABLE sv CALLER
# -------------------------------
# The defacto standard SV caller, if there can be said to be one
# it hits f-scores of .6 +/- .2 depending how the truth set is framed
# which is better tha most.  It locked in python 2.6, and is a huge
# pain to get running even with conda helping.
# github: https://github.com/Illumina/manta
# a paper: https://doi.org/10.1093/bioinformatics/btv710

rule manta_get_centos_env:
    priority: 30
    conda:
        "../envs/vanilla_v0.1.yaml"  #  "../envs/manta_uge_v0.2.yaml"
    log:
        MDIR + "logs/manta_get_centos_env.log"
    benchmark:
        MDIR + "benchmarks/manta_get_centos_env.bench.tsv"
    params:
        cluster_sample="manta_get_centos_env",
    shell:
        "echo got it"


rule manta:
    """https://github.com/Illumina/manta"""
    input:
        bam=rules.legacy_cram_compat_bam.output.bam,
        bai=rules.legacy_cram_compat_bam.output.bai,
    output:
        vcf=f"{MDIR}" + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.vcf",
    threads: config["manta"]["threads"]
    priority: 36
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.manta.bench.tsv"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/logs/{sample}.{alnr}.manta.log",
    resources:
        vcpu=config["manta"]["threads"],
        threads=config["manta"]["threads"],
        mem_mb=config["manta"].get("mem_mb", 128000),
        partition=config["manta"]["partition"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        work_dir=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/manta_work/",
        mdir=MDIR,
        log=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/logs/{sample}.{alnr}.manta.log",
        tb=os.popen("which tabix").readline().rstrip(),
        bg=os.popen("which bgzip").readline().rstrip(),
        cluster_sample=ret_sample_alnr,
    conda:
        "../envs/manta_v0.1.yaml"  #config["manta"]["env_yaml"]
    shell:
        """
        set -euo pipefail

        timestamp=$(date +%Y%m%d%H%M%S)_$$
        export TMPDIR=/fsx/scratch/manta_tmp_$timestamp
        mkdir -p $TMPDIR
        export APPTAINER_HOME=$TMPDIR
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

        mkdir -p $(dirname {log})

        # --- Run Manta (may legitimately fail on some inputs) ---
        rm -rf {params.work_dir} 2>/dev/null || true
        mkdir -p {params.work_dir}

        MANTA_OK=true
        configManta.py --bam {input.bam} --reference {params.huref} --runDir {params.work_dir} >> {log} 2>&1 || {{
            echo "ERROR: configManta.py failed" >> {log}
            MANTA_OK=false
        }}

        if [ "$MANTA_OK" = "true" ]; then
            python {params.work_dir}/runWorkflow.py -j {threads} >> {log} 2>&1 || {{
                echo "WARNING: Manta runWorkflow.py exited non-zero" >> {log}
                MANTA_OK=false
            }}
        fi

        # --- Validate Manta produced expected outputs ---
        DIPLOID_VCF="{params.work_dir}/results/variants/diploidSV.vcf.gz"
        CANDIDATE_VCF="{params.work_dir}/results/variants/candidateSV.vcf.gz"

        if [ "$MANTA_OK" = "false" ] || [ ! -s "$DIPLOID_VCF" ] || [ ! -s "$CANDIDATE_VCF" ]; then
            echo "ERROR: Manta did not produce expected output files. Aborting." >> {log}
            echo "  diploidSV exists/non-empty: $([ -s $DIPLOID_VCF ] && echo YES || echo NO)" >> {log}
            echo "  candidateSV exists/non-empty: $([ -s $CANDIDATE_VCF ] && echo YES || echo NO)" >> {log}
            ls -la {params.work_dir}/results/variants/ >> {log} 2>&1 || true
            exit 1
        fi

        # --- Merge VCFs (write to temp, then move — prevents empty output on crash) ---
        TMPVCF="$TMPDIR/manta_merged.vcf"
        python workflow/scripts/manta_uniter.py "$DIPLOID_VCF" "$CANDIDATE_VCF" > "$TMPVCF" 2>> {log}

        if [ ! -s "$TMPVCF" ]; then
            echo "ERROR: manta_uniter.py produced empty output" >> {log}
            exit 1
        fi

        mv "$TMPVCF" {output.vcf}
        echo "Manta completed successfully at $(date)" >> {log}

        rm -rf {params.work_dir}/workspace 2>/dev/null || true
        """


rule manta_sort_and_index:
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.vcf",
    priority:37
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.sort.vcf.gz.tbi",
    log:
        MDIR+ "{sample}/align/{alnr}/{ddup}/sv/manta/logs/{sample}.{alnr}.manta.sv.sort.vcf.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.manta_sort_and_index.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    params:
        cluster_sample=ret_sample
    threads: 16
    resources:
        vcpu=16
    shell:
        """( (rm {output}) || echo noRm > {log};
        echo 0Index >> {log};
        bedtools sort -header -i {input.vcf} > {output.vcfsort};
        bgzip -f {output.vcfsort} ;
        tabix -f -p vcf {output.vcfgz};
        touch {output.vcfsort}; ) >> {log} 2>&1;
        ls {output};"""

localrules: produce_manta,

rule produce_manta:   # DEPRECATED TARGET: use produce_manta_sv_vcf
    priority: 38
    input:
        expand(MDIR + "{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.manta.sv.sort.vcf.gz.tbi",sample=SSAMPS,alnr=ALIGNERS,ddup=DDUP)
    log:
        MDIR + "logs/produce_manta.log"
    benchmark:
        MDIR + "benchmarks/produce_manta.bench.tsv"
