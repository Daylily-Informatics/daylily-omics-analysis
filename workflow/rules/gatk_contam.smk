######### GATK CONTAMINATION SCREEN
# - Uses GATK GetPileupSummaries + CalculateContamination
# - Simplified to a single GetPileupSummaries invocation
# - Emits GATK-specific TSV output consumed by the aggregate MultiQC custom table

rule gatk_contam:
    input:
        cram = MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        # common sites VCF (gnomAD/common SNPs) and its index
        sites_vcf = config["supporting_files"]["files"]["gatk"]["af_sites"],
        sites_vcf_tbi = lambda wildcards: config["supporting_files"]["files"]["gatk"]["af_sites"] + ".tbi",
        # reference FASTA and its index/dict should already exist in your ref bundle
        ref_fa   = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai  = lambda w: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        ref_dict = lambda w: os.path.splitext(config["supporting_files"]["files"]["huref"]["fasta"]["name"])[0] + ".dict",
    output:
        # per-tool prefix directory
        pile_merged = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.pileups.table",
        contam      = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.contam.tsv",
        tsv         = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.tsv",
        stamp       = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.done",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/logs/{sample}.{alnr}.{ddup}.gatk_contam.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk_contam.bench.tsv"
    conda:
        config["gatk_contam"]["env_yaml"]   # env must provide gatk and coreutils
    threads: config["gatk_contam"]["threads"]
    resources:
        vcpu = config["gatk_contam"]["threads"],
        partition = config["gatk_contam"]["partition"],
        mem_mb = config["gatk_contam"].get("mem_mb", 80000),
        exclusive = config["gatk_contam"].get("exclusive", "--exclusive")
    params:
        cluster_sample = ret_sample,
        alnr = get_alnr,
        java_heap_mb = config["gatk_contam"].get("java_heap_mb", 64000)
    shell:
        r"""
        set -euo pipefail;

        mkdir -p "$(dirname {output.pile_merged})"/logs;
        rm -f "$(dirname {output.tsv})/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.gatk_mqc.tsv";

        SAFE_IN="$(bin/util/gatk_cram_compat.sh --in {input.cram} --ref {input.ref_fa} --mode bam --threads {threads} 2>> {log})";
        echo "gatk_contam SAFE_IN=${{SAFE_IN}}" >> {log};

        gatk --java-options "-Xmx{params.java_heap_mb}m -Djava.io.tmpdir=${{TMPDIR:-/tmp}}" GetPileupSummaries \
          -I "${{SAFE_IN}}" \
          -V {input.sites_vcf} \
          -R {input.ref_fa} \
          -L {input.sites_vcf} \
          --interval-merging-rule OVERLAPPING_ONLY \
          --disable-bam-index-caching \
          -O {output.pile_merged} \
          >> {log} 2>&1;

        gatk --java-options "-Xmx{params.java_heap_mb}m -Djava.io.tmpdir=${{TMPDIR:-/tmp}}" CalculateContamination \
          -I {output.pile_merged} \
          -O {output.contam} \
          >> {log} 2>&1;

        gatk_sample="$(awk -F'\t' 'NR==1 {{for (i=1; i<=NF; i++) if ($i=="sample") s=i}} NR==2 {{if (s) print $s}}' {output.contam})";
        contam_val="$(awk -F'\t' 'NR==1 {{for (i=1; i<=NF; i++) if ($i=="contamination") c=i; if (!c) exit 2}} NR==2 {{print $c}}' {output.contam})";
        gatk_error="$(awk -F'\t' 'NR==1 {{for (i=1; i<=NF; i++) if ($i=="error") e=i}} NR==2 {{if (e) print $e}}' {output.contam})";
        if [[ -n "${{contam_val:-}}" && "${{contam_val}}" != "NA" ]]; then
            status="ok";
            contam_pct="$(awk -v c="${{contam_val}}" 'BEGIN {{printf "%.12g", c * 100.0}}')";
        else
            status="no_call";
            contam_val="NA";
            contam_pct="NA";
        fi;

        printf "sample_id\texternal_sample_id\taligner\tdeduper\ttool\tmethod\tcontamination_fraction\tcontamination_pct\tgatk_sample_id\tgatk_error_fraction\tsource_path\tstatus\n" > {output.tsv};
        printf "{params.cluster_sample}.{params.alnr}.{wildcards.ddup}\t{params.cluster_sample}\t{params.alnr}\t{wildcards.ddup}\tgatk\tcalculate_contamination\t%s\t%s\t%s\t%s\t{output.contam}\t%s\n" "${{contam_val}}" "${{contam_pct}}" "${{gatk_sample:-}}" "${{gatk_error:-}}" "${{status}}" >> {output.tsv};
        touch {output.stamp};
        """


localrules:
    produce_gatk_contam_estimate,

rule produce_gatk_contam_estimate:  # TARGET : Produce GATK contamination estimates
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_alignment_dedupers(),
        )
