rule sentieon_gatk_gvcf:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram.crai",
    output:
        gvcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.g.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.g.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/logs/{sample}.{alnr}.{ddup}.gvcf.log",
    threads: config["sentieon_gatk"]["threads"]
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        dbsnp=config["supporting_files"]["files"]["gatk"]["dbsnp_vcf"],
    shell:
        """
        sentieon driver \
            -t {threads} \
            -r {params.ref} \
            -i {input.cram} \
            --algo Haplotyper \
            --emit_mode gvcf \
            --pcr_indel_model NONE \
            --dbsnp {params.dbsnp} \
            {output.gvcf} >> {log} 2>&1

        tabix -f -p vcf {output.gvcf}
        """

rule sentieon_gatk_joint:
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.g.vcf.gz",
            sample=SAMPS, alnr=ALIGNERS, ddup=DDUP
        )
    output:
        vcf=MDIR + "cohort/gatk/joint.raw.vcf.gz",
        tbi=MDIR + "cohort/gatk/joint.raw.vcf.gz.tbi",
    log:
        MDIR + "cohort/gatk/logs/joint.log",
    threads: config["sentieon_gatk"]["threads"]
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        sentieon driver \
            -t {threads} \
            -r {params.ref} \
            --algo GVCFtyper \
            {input} \
            {output.vcf} >> {log} 2>&1

        tabix -f -p vcf {output.vcf}
        """

rule sentieon_gatk_snp_vqsr:
    input:
        vcf=MDIR + "cohort/gatk/joint.raw.vcf.gz"
    output:
        recal=MDIR + "cohort/gatk/snp.recal",
        tranches=MDIR + "cohort/gatk/snp.tranches",
    log:
        MDIR + "cohort/gatk/logs/snp_vqsr.log",
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        hapmap="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/hapmap_3.3.hg38.vcf.gz",
        omni="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/1000G_omni2.5.hg38.vcf.gz",
        onekg="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/1000G_phase1.snps.high_confidence.hg38.vcf.gz",
        dbsnp="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/Homo_sapiens_assembly38.dbsnp138.vcf.gz",
    shell:
        """
        sentieon driver \
            -r {params.ref} \
            -v {input.vcf} \
            --algo VarCal \
            --mode SNP \
            --resource hapmap,known=false,training=true,truth=true,prior=15.0 {params.hapmap} \
            --resource omni,known=false,training=true,truth=true,prior=12.0 {params.omni} \
            --resource 1000G,known=false,training=true,truth=false,prior=10.0 {params.onekg} \
            --resource dbsnp,known=true,training=false,truth=false,prior=2.0 {params.dbsnp} \
            {output.recal} \
            {output.tranches} >> {log} 2>&1
        """

rule sentieon_gatk_apply_snp:
    input:
        vcf=MDIR + "cohort/gatk/joint.raw.vcf.gz",
        recal=MDIR + "cohort/gatk/snp.recal",
        tranches=MDIR + "cohort/gatk/snp.tranches",
    output:
        vcf=MDIR + "cohort/gatk/joint.snp.recal.vcf.gz",
        tbi=MDIR + "cohort/gatk/joint.snp.recal.vcf.gz.tbi",
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        sentieon driver \
            -r {params.ref} \
            -v {input.vcf} \
            --algo ApplyVarCal \
            --mode SNP \
            --recal {input.recal} \
            --tranches {input.tranches} \
            --ts_filter_level 99.5 \
            {output.vcf}

        tabix -f -p vcf {output.vcf}
        """

rule sentieon_gatk_indel_vqsr:
    input:
        vcf=MDIR + "cohort/gatk/joint.snp.recal.vcf.gz"
    output:
        recal=MDIR + "cohort/gatk/indel.recal",
        tranches=MDIR + "cohort/gatk/indel.tranches",
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mills="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz",
        dbsnp="/fsx/data/genomic_data/organism_annotations/H_sapiens/hg38/gatk/Homo_sapiens_assembly38.dbsnp138.vcf.gz",
    shell:
        """
        sentieon driver \
            -r {params.ref} \
            -v {input.vcf} \
            --algo VarCal \
            --mode INDEL \
            --resource mills,known=false,training=true,truth=true,prior=12.0 {params.mills} \
            --resource dbsnp,known=true,training=false,truth=false,prior=2.0 {params.dbsnp} \
            {output.recal} \
            {output.tranches}
        """

rule sentieon_gatk_apply_indel:
    input:
        vcf=MDIR + "cohort/gatk/joint.snp.recal.vcf.gz",
        recal=MDIR + "cohort/gatk/indel.recal",
        tranches=MDIR + "cohort/gatk/indel.tranches",
    output:
        vcf=MDIR + "cohort/gatk/joint.final.vcf.gz",
        tbi=MDIR + "cohort/gatk/joint.final.vcf.gz.tbi",
    params:
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        sentieon driver \
            -r {params.ref} \
            -v {input.vcf} \
            --algo ApplyVarCal \
            --mode INDEL \
            --recal {input.recal} \
            --tranches {input.tranches} \
            --ts_filter_level 99.0 \
            {output.vcf}

        tabix -f -p vcf {output.vcf}
        """

