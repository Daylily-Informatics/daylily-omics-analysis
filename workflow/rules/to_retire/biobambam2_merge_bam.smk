import os

# #### fastqc
# -----------
# github: https://github.com/s-andrews/FastQC


  
def get_merge_samp_b2(wildcards):
    ret_files = []
    for sample in samples[samples['samp'] == wildcards.sample_lane ]['sample_lane']:
        ret_files.append( MDIR + f"{sample}/align/{wildcards.alnr}/{sample}.{wildcards.alnr}.sort.bam")
    return ret_files

 
def get_lane_from_samp(wildcards):

    return len(SSAMPS[wildcards.sample_lane])
    
    

rule merge_bam_b2:
    input:
        get_merge_samp_b2
        #bamo=expand(MDIR + "{sample}/align/{{alnr}}/{sample}.{{alnr}}.sort.bam", sample=get_merge_samp)
    output:
        bamo=MDIR+ "{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.sort.bam",
        baio=MDIR+ "{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.sort.bam.bai",
    log:
        MDIR+ "{sample_lane}/align/{alnr}/log_bammerge/{sample_lane}.{alnr}.sort.bam.log"
    benchmark:
        MDIR+ "{sample_lane}/benchmark/{sample_lane}.{alnr}.sort.bam.log"
    threads: config['bbb2_merge_bed']['threads']
    params:
        glfs=get_lane_from_samp,
        smem=config['bbb2_merge_bed']['smem'],
        mmem=config['bbb2_merge_bed']['mmem'],
        cluster_sample=ret_sample,
        mthreads=config['bbb2_merge_bed']['mthreads'],
        sthreads=config['bbb2_merge_bed']['sthreads'],
        othreads=config['bbb2_merge_bed']['othreads'],
    resources:
        threads=config['bbb2_merge_bed']['threads'],
        vcpu=config['bbb2_merge_bed']['threads'],
        partition=config['bbb2_merge_bed']['partition'],
    container:
        "docker://daylilyinformatics/biobambam2:2.0.0"
    shell:
        """
        echo 'I: {input}' > {log};
        echo 'O: {output}'>> {log};
        echo '{params.glfs}' >> {log};

        if [[ '{params.glfs}' == '1' ]]; then
            mv {input} {output.bamo} ;
            mv {input}.bai {output.baio};
            touch {input} {input}.bai;
        else
             bamcollate2 -@ {threads} \
             colhog=22 \
             colsbs=2342177280 \
             {input} | bamsort - -o {output.bamo} \
             outputthreads={params.mthreads} \
             inputbuffersize={params.imem} | \
             bamsort - {output.bamo} 
             level=-1 \
             SO=coordinate \
             verbose=1 \
             index={output.bamo} \
             indexfilename={output.baio} \
             outputthreads={params.othreads} \
             streaming=1;               

        fi;
        """

localrules:
    merge_all_bams_b2,


rule merge_all_bams_b2:  # TARGET merge_all_bams
    input:
        b=expand(MDIR+ "{sample_lane}/align/{alnr}/{sample_lane}.{alnr}.sort.bam", sample_lane=SSAMPS.keys(), alnr=ALIGNERS)
    output:
        "mg.done",
    shell:
        "touch {output}"
