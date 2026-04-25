import os

# ##### PEDDY - Pedigree Tools
# ----------------------------
# ** ported from SUPERSONIC
# We are mostly using it for it's gender and ethnicity prediction
# capabilities
# github: https://github.com/brentp/peddy
# paper: http://dx.doi.org/10.1016/j.ajhg.2017.01.017

# ped file:  "family_id individual_id paternal_id maternal_id bio_sex phenotype"
def gen_ped_file(wildcards):
    bio_sex = config["sample_info"][wildcards.sample]["biological_sex"].lower() 
    ped_sex = 0
    if bio_sex in ["female"]:
        ped_sex = 2
    elif bio_sex in ["male"]:
        ped_sex = 1
    else:
        ped_sex = 0
    ped_f = f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{wildcards.snv}/peddy/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{wildcards.snv}.peddy.ped"
    os.system(f"mkdir -p $(dirname {ped_f});")
    ped_fh = open(ped_f, "w")
    ped_fh.write(f"{wildcards.sample}\t{wildcards.sample}\t0\t0\t{ped_sex}\t0\n")
    ped_fh.close()
    return ped_f


rule peddy:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
        # Generalize this for other var callers
        ped_f=gen_ped_file,
    output:
        prefix=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/{sample}.{alnr}.{ddup}.{snv}.peddy.",
        done=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/{sample}.{alnr}.{ddup}.{snv}.peddy.done",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/log/{sample}.{alnr}.{ddup}.{snv}.peddy.log",
    threads: config["peddy"]["threads"]
    resources:
        vcpu=config["peddy"]["threads"],
        partition=config["peddy"]["partition"],
    params:
        cluster_sample=ret_sample,
        ld_preload=config["malloc_alt"]["ld_preload"],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.peddy.bench.tsv"
    container:
        None
    conda:
        config["peddy"]["env_yaml"]
    shell:
        """
        set -euo pipefail;

        mkdir -p "$(dirname "{log}")" "$(dirname "{output.done}")"
        : > "{log}"
        rm -f "{output.done}" "{output.prefix}"

        printf 'running peddy\n' >> "{log}"
        {params.ld_preload} peddy -p {threads} --plot --prefix "{output.prefix}" --loglevel DEBUG "{input.vcfgz}" "{input.ped_f}" >> "{log}" 2>&1 || {{
            peddy_status=$?
            printf 'ERROR: peddy exited with status %s\n' "$peddy_status" | tee -a "{log}" >&2
            exit "$peddy_status"
        }}

        for expected_output in \
            "{output.prefix}peddy.ped" \
            "{output.prefix}ped_check.csv" \
            "{output.prefix}sex_check.csv" \
            "{output.prefix}het_check.csv" \
            "{output.prefix}background_pca.json" \
            "{output.prefix}html" \
            "{output.prefix}vs.html" \
            "{output.prefix}ped_check.png" \
            "{output.prefix}het_check.png" \
            "{output.prefix}sex_check.png"
        do
            if [[ ! -s "$expected_output" ]]; then
                printf 'ERROR: peddy completed but expected output is missing or empty: %s\n' "$expected_output" | tee -a "{log}" >&2
                exit 1
            fi
        done

        printf 'reallydone\n' > "{output.done}"
        printf 'reallydone\n' > "{output.prefix}"
        printf 'DONE\n' >> "{log}"
        """


localrules:
    produce_peddy,

rule produce_peddy:  # TARGET: just produce peddy results
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/{sample}.{alnr}.{ddup}.{snv}.peddy.done"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
    output:
        "logs/peddy_gathered.done",
    shell:
        "touch {output};"
