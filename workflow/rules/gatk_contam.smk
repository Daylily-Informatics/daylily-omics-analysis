######### GATK CONTAMINATION SCREEN
# - Uses GATK GetPileupSummaries + CalculateContamination
# - Parallelizes pileups across chromosomes, then merges
# - Emits a VerifyBamID2-like selfSM/tsv for compatibility

rule gatk_contam:
    input:
        cram = MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        # common sites VCF (gnomAD/common SNPs) and its index
        sites_vcf = config["supporting_files"]["files"]["gatk"]["af_sites"],
        sites_vcf_tbi = lambda wildcards: config["supporting_files"]["files"]["gatk"]["af_sites"] + ".tbi",
        # reference FASTA and its index/dict should already exist in your ref bundle
        ref_fa   = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai  = lambda w: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        ref_dict = lambda w: os.path.splitext(config["supporting_files"]["files"]["huref"]["fasta"]["name"])[0] + ".dict",
    output:
        # per-tool prefix directory
        pile_merged = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.pileups.table",
        contam      = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.contam.tsv",
        selfSM      = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.gatk.selfSM",
        tsv         = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.gatk.tsv",
        mqc         = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.gatk_mqc.tsv",
        stamp       = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.gatk.done",
    log:
        MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/logs/{sample}.{alnr}.gatk_contam.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.gatk_contam.bench.tsv"
    conda:
        config["gatk_contam"]["env_yaml"]   # env must provide gatk, parallel, coreutils, awk
    threads: config["gatk_contam"]["threads"]
    resources:
        vcpu = config["gatk_contam"]["threads"],
        partition = config["gatk_contam"]["partition"]
    params:
        cluster_sample = ret_sample,
        alnr = get_alnr,
        chrm_prefix = GENOME_CHR_PREFIX,   # e.g., "" or "chr"
        # editable chromosome list; X only here, add Y/M if needed
        chroms = lambda w: " ".join([f"{GENOME_CHR_PREFIX}{c}" for c in list(range(1,23)) + ["X"]]),
        tmpdir = MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/tmp"
    shell:
        r"""
        set -euo pipefail;

        mkdir -p "$(dirname {output.pile_merged})"/logs {params.tmpdir};

        # 1) Pileups per chromosome (parallel)
        #    Note: GetPileupSummaries isn't multithreaded; we fan out by chrom.
        printf "%s\n" {params.chroms} | parallel -j {threads} --halt soon,fail=1 '
            gatk GetPileupSummaries \
              -I {input.cram} \
              -V {input.sites_vcf} \
              -R {input.ref_fa} \
              -L {input.sites_vcf} \
              -L {{}} \
              -O {params.tmpdir}/{wildcards.sample}.{wildcards.alnr}.{{}}.pileups.table \
              > {log}.{{}} 2>&1
        ';

        # 2) Merge per-chrom tables: keep header from the first, then append bodies
        first_tbl="$(ls -1 {params.tmpdir}/{wildcards.sample}.{wildcards.alnr}.*.pileups.table | head -n1)";
        if [[ -z "${{first_tbl:-}}" ]]; then
            echo "No pileup tables produced" >&2;
            exit 2;
        fi
        head -n 1 "${{first_tbl}}" > {output.pile_merged};
        # normalize SAMPLE field to sample.alnr for consistency
        for f in {params.tmpdir}/{wildcards.sample}.{wildcards.alnr}.*.pileups.table; do
            tail -n +2 "${{f}}" \
              | awk -v s="{params.cluster_sample}.{params.alnr}" 'BEGIN{{FS=OFS="\t"}} NR>0{{ sub(/^SAMPLE=.*/,"SAMPLE=" s, $1); print }}' \
              >> {output.pile_merged};
        done

        # 3) Calculate contamination
        gatk CalculateContamination \
          -I {output.pile_merged} \
          -O {output.contam} >> {log} 2>&1;

        # 4) Emit VerifyBamID2-like selfSM & copies for compatibility
        #    FREEMIX is col2 on the 2nd line of the .contam output
        contam_val="$(awk 'NR==2 {{print $2}}' {output.contam})";

        printf "SEQ_ID\tRG\tCHIP_ID\t#SNPS\t#READS\tAVG_DP\tFREEMIX\tFREELK1\tFREELK0\tFREE_RH\tFREE_RA\tCHIPMIX\tCHIPLK1\tCHIPLK0\tCHIP_RH\tCHIP_RA\tDPREF\tRDPHET\tRDPALT\n" > {output.selfSM};
        printf "{params.cluster_sample}.{params.alnr}\tNA\tNA\tNA\tNA\tNA\t%s\t-1\t-1\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\n" "${{contam_val:-NA}}" >> {output.selfSM};

        cp {output.selfSM} {output.tsv};
        cp {output.selfSM} {output.mqc};
        touch {output.stamp};

        # 5) Cleanup
        rm -f {params.tmpdir}/{wildcards.sample}.{wildcards.alnr}.*.pileups.table;
        """



localrules:
    produce_gatk_contam_estimate,

rule produce_gatk_contam_estimate:
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/alignqc/contam/gatk/{sample}.{alnr}.gatk.tsv",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
        )
