import os
import csv

# ##### PEDDY - Pedigree Tools
# ----------------------------
# ** ported from SUPERSONIC
# We are mostly using it for it's gender and ethnicity prediction
# capabilities
# github: https://github.com/brentp/peddy
# paper: http://dx.doi.org/10.1016/j.ajhg.2017.01.017

# ped file:  "family_id individual_id paternal_id maternal_id bio_sex phenotype"
def gen_ped_file(wildcards):
    require_qc_eligible_sample(wildcards, "Peddy")
    bio_sex = sample_sex_for_required_tool(wildcards, "Peddy")
    if bio_sex == "female":
        ped_sex = 2
    else:
        ped_sex = 1
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
        sex_assumption_log=lambda wildcards: sample_sex_assumption_log(
            wildcards, "Peddy"
        ),
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
        if [ -n {params.sex_assumption_log:q} ]; then
            printf '%s' {params.sex_assumption_log:q} >> "{log}"
        fi
        rm -f "{output.done}" "{output.prefix}"

        printf 'running peddy\n' >> "{log}"
        {params.ld_preload} peddy -p {threads} --plot --prefix "{output.prefix}" --loglevel DEBUG "{input.vcfgz}" "{input.ped_f}" >> "{log}" 2>&1 || {{
            peddy_status=$?
            if grep -q 'peddy: no hets found for sample' "{log}" && grep -q 'IndexError: index 0 is out of bounds for axis 0 with size 0' "{log}"; then
                printf 'WARNING: peddy reported no usable heterozygous variants; writing explicit low-data QC outputs\n' | tee -a "{log}" >&2
                python bin/util/write_peddy_low_data_outputs.py \
                    --prefix "{output.prefix}" \
                    --ped "{input.ped_f}" \
                    --sample-id "{wildcards.sample}" \
                    --reason "peddy_no_usable_heterozygous_variants" \
                    >> "{log}" 2>&1
            else
                printf 'ERROR: peddy exited with status %s\n' "$peddy_status" | tee -a "{log}" >&2
                exit "$peddy_status"
            fi
        }}

        for expected_output in \
            "{output.prefix}ped" \
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
    peddy_sample_qc_gather,
    produce_peddy,


rule peddy_sample_qc_gather:
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/{sample}.{alnr}.{ddup}.{snv}.peddy.done"
            for sample in QC_ELIGIBLE_SAMPLES
            for ddup in qc_variant_dedupers()
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
    output:
        MDIR + "other_reports/peddy_sample_qc_mqc.tsv",
    log:
        MDIR + "logs/peddy_sample_qc_gather.log"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "Sample",
            "base_sample",
            "aligner",
            "deduper",
            "snv_caller",
            "reported_sex",
            "predicted_sex",
            "sex_check_status",
            "het_check_status",
            "ped_check_status",
            "peddy_prefix",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for done_path in input:
                name = os.path.basename(str(done_path)).replace(".peddy.done", "")
                sample, aligner, deduper, caller = name.rsplit(".", 3)
                sample_id = day_stage_sample_id(sample, aligner, deduper, caller)
                prefix = str(done_path).replace(".peddy.done", ".peddy.")
                sex_file = prefix + "sex_check.csv"
                het_file = prefix + "het_check.csv"
                sex_row = {}
                if os.path.exists(sex_file):
                    with open(sex_file, newline="") as handle:
                        rows = list(csv.DictReader(handle))
                    sex_row = rows[0] if rows else {}
                het_row = {}
                if os.path.exists(het_file):
                    with open(het_file, newline="") as handle:
                        rows = list(csv.DictReader(handle))
                    het_row = rows[0] if rows else {}
                writer.writerow(
                    {
                        "Sample": sample_id,
                        "base_sample": sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "snv_caller": caller,
                        "reported_sex": sex_row.get("ped_sex", ""),
                        "predicted_sex": sex_row.get("predicted_sex", ""),
                        "sex_check_status": sex_row.get("dayoa_status") or sex_row.get("error", ""),
                        "het_check_status": het_row.get("dayoa_status") or "generated",
                        "ped_check_status": "generated",
                        "peddy_prefix": prefix,
                    }
                )

rule produce_peddy:  # TARGET: just produce peddy results
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/peddy/{sample}.{alnr}.{ddup}.{snv}.peddy.done"
            for sample in QC_ELIGIBLE_SAMPLES
            for ddup in qc_variant_dedupers()
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
        MDIR + "other_reports/peddy_sample_qc_mqc.tsv",
    output:
        "logs/peddy_gathered.done",
    log:
        MDIR + "logs/produce_peddy.log"
    benchmark:
        "logs/benchmarks/produce_peddy.bench.tsv"
    shell:
        "touch {output};"
