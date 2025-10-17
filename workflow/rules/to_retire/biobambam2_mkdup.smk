#########  biobambam2
# --------------------------
# name==biobambam2
# comment="pretty fast."  
# ref==https://gitlab.com/german.tischler/biobambam2
#



def get_dppl_inputs(wildcards):
    ret_files = []
    for samp in samples[samples['sample'] == wildcards.sample_lane ]['sample_lane']:
        ret_files.append( MDIR + f"{sample}/align/{wildcards.alnr}/{sample}.{wildcards.alnr}.sort.bam")
        ret_files.append( MDIR + f"{sample}/align/{wildcards.alnr}/{sample}.{wildcards.alnr}.sort.bam.bai")

    return ret_files


if "bbb2" in DDUP:


    rule biobambam2_mkdup:
        """Runs duplicate marking on the raw BAM."""
        input:
            bam=MDIR + "{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.sort.bam",
            bai=MDIR + "{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.sort.bam.bai",
        priority: 3
        output:
            bamo="{MDIR}{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.mrkdup.sort.bam",
            bami="{MDIR}{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.mrkdup.sort.bam.bai",
        threads: config["doppelmark_markdups"]["threads"]
        benchmark:
            repeat("{MDIR}{sample_lane}/benchmarks/{sample_lane}.{alnr}.dppl.mrkdup.bench.tsv", 0)
        container:
            "docker://daylilyinformatics/biobambam2:2.0.0"
        resources:
            threads=config["doppelmark_markdups"]["threads"],
            partition=config["doppelmark_markdups"]["partition"],
            vcpu=config["doppelmark_markdups"]["threads"],
        params:
            na=1,
            cluster_sample=ret_sample_lane, #
        log:
            "{MDIR}{sample_lane}/align/{alnr}/logs/dedupe.{sample_lane}.{alnr}.log",
        shell:
            """
            bammarkduplicates2 -@ {threads} \
            I={input.bam} \
            O={output.bamo} \
            colhashbits=22 \
            collistsize=2147483648 \
            fragbufsize=4294967296 \
            inputbuffersize=262144 \
            optminpixeldif=1000 \
            index=1;
            {latency_wait};
            """
