"""Rules for running the Gauchian GBA caller."""

rule gauchian:
    """Run the Gauchian caller on an input CRAM/CRAI pair."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        manifest=temp(MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/{sample}.{alnr}.{ddup}.gauchian.manifest"),
        results_dir=directory(MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/results/{sample}.{alnr}"),
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/{sample}.{alnr}.{ddup}.gauchian.done",
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        genome="37" if config["genome_build"] == "b37" else "38",
        prefix=lambda wildcards: f"{wildcards.sample}.{wildcards.alnr}.gauchian",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gauchian.benchmark.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/logs/gauchian.log",
    threads: config["go_left"]["threads"]
    conda:
         "workflow/envs/gba_v0.1.yaml"
    shell:
        """
        set -euo pipefail

        manifest_dir=$(dirname {output.manifest})
        log_dir=$(dirname {log})
        out_dir={output.results_dir}

        rm -rf "${{out_dir}}"
        mkdir -p "${{manifest_dir}}" "${{log_dir}}" "${{out_dir}}"

        # --- Validate input CRAM contains aligned data ---
        echo "Validating CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check: {input.cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: CRAM has no @SQ headers (unaligned?): {input.cram}" | tee -a {log};
            exit 11;
        fi
        echo "CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        cat <<'MANIFEST' > {output.manifest}
SampleId\tCram\tCrai
{wildcards.sample}.{wildcards.alnr}\t{input.cram}\t{input.crai}
MANIFEST

        gauchian \
            -m {output.manifest} \
            --reference {params.huref} \
            -g {params.genome} \
            -o "${{out_dir}}" \
            -p {params.prefix} \
            &> {log}

        touch {output.done}
        """


localrules: produce_gauchian

rule produce_gauchian:  # TARGET : Produce Gauchian results
    """Aggregate completion for all Gauchian runs."""
    input:
        expand(MDIR + "{sample}/align/{alnr}/htd/gauchian/{sample}.{alnr}.gauchian.done", sample=SSAMPS, alnr=ALIGNERS)
    output:
        "./logs/gauchian.done"
    shell:
        "touch {output}"


localrules: produce_all_htd

rule produce_all_htd:  # TARGET : Produce all HTD results (Gauchian, SMN, CYP2D6, Parascopy)
    input:
        "./logs/gauchian.done",
        "./logs/smn12.done",
        "./logs/cyp2d6.done",
        "./logs/parascopy.done"
        "./logs/smaca.done"
        "./logs/genetocn.done"
    output:
        "./logs/all_htd_cmp_readsy"
    shell:
        "touch {output}"
