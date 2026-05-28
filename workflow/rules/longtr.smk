"""LongTR tandem-repeat genotyping for ONT CRAM evidence."""

from snakemake.exceptions import WorkflowError


LONGTR_CATALOG_KEYS = ("all", "diseaser")
LONGTR_ALLOWED_ALIGNERS = {"ont", "sentmm2ont"}


def _longtr_config():
    cfg = config.get("longtr")
    if not isinstance(cfg, dict):
        raise WorkflowError("LongTR requires an explicit config['longtr'] block.")
    return cfg


def _longtr_required(key):
    cfg = _longtr_config()
    value = cfg.get(key)
    if str(value).strip() in {"", "None", "none", "na", "NA"}:
        raise WorkflowError(f"LongTR requires explicit config['longtr']['{key}'].")
    return value


def _longtr_catalog_config(catalog_key):
    catalogs = _longtr_config().get("catalogs")
    if not isinstance(catalogs, dict):
        raise WorkflowError("LongTR requires explicit config['longtr']['catalogs'].")
    if catalog_key not in catalogs or not isinstance(catalogs[catalog_key], dict):
        raise WorkflowError(
            f"LongTR catalog {catalog_key!r} is not configured. "
            f"Supported catalog keys: {', '.join(LONGTR_CATALOG_KEYS)}."
        )
    return catalogs[catalog_key]


def _longtr_catalog_regions_bed(catalog_key):
    value = _longtr_catalog_config(catalog_key).get("regions_bed")
    if str(value).strip() in {"", "None", "none", "na", "NA"}:
        raise WorkflowError(
            f"LongTR catalog {catalog_key!r} requires explicit regions_bed."
        )
    return str(value)


def _longtr_catalog_name(catalog_key):
    return str(_longtr_catalog_config(catalog_key).get("name", catalog_key))


def _longtr_aligners(*, require_non_empty=False):
    aligners = _as_config_list(_longtr_required("aligners"))
    invalid = sorted(set(aligners) - LONGTR_ALLOWED_ALIGNERS)
    if invalid:
        raise WorkflowError(
            "LongTR aligners must be ONT CRAM aligners only; invalid value(s): "
            + ", ".join(invalid)
            + ". Supported values: "
            + ", ".join(sorted(LONGTR_ALLOWED_ALIGNERS))
        )
    active = [aligner for aligner in aligners if aligner in ALL_ALIGNERS]
    if require_non_empty and not active:
        raise WorkflowError(
            "The requested LongTR target has no active ONT aligners. "
            "Set manifest ONT_CRAM_ALIGNER=ont or ONT_BAM_ALIGNER=sentmm2ont, "
            "or adjust config['longtr']['aligners']."
        )
    return active


def _longtr_deduper():
    deduper = str(_longtr_required("deduper"))
    if deduper not in DDUP:
        raise WorkflowError(
            f"LongTR deduper {deduper!r} is not in configured dedupers {DDUP!r}."
        )
    return deduper


def _longtr_extra_args():
    value = _longtr_config().get("extra_args", "")
    return "" if value is None else str(value)


def _longtr_threads(wildcards):
    return int(_longtr_required("threads"))


def _longtr_mem_mb(wildcards):
    return int(_longtr_required("mem_mb"))


def _longtr_partition(wildcards):
    return str(_longtr_required("partition"))


def _longtr_outputs(catalog_key, *, require_non_empty=False):
    return expand(
        [
            MDIR
            + "{sample}/align/{alnr}/{ddup}/tr/longtr/{catalog_key}/"
            + "{sample}.{alnr}.{ddup}.longtr.{catalog_key}.vcf.gz",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/tr/longtr/{catalog_key}/"
            + "{sample}.{alnr}.{ddup}.longtr.{catalog_key}.vcf.gz.tbi",
        ],
        sample=SSAMPS,
        alnr=_longtr_aligners(require_non_empty=require_non_empty),
        ddup=[_longtr_deduper()],
        catalog_key=[catalog_key],
    )


rule longtr:
    """Run LongTR for one ONT CRAM and one configured repeat catalog."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        regions_bed=lambda wildcards: _longtr_catalog_regions_bed(wildcards.catalog_key),
    output:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/tr/longtr/{catalog_key}/"
        + "{sample}.{alnr}.{ddup}.longtr.{catalog_key}.vcf.gz",
        tbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/tr/longtr/{catalog_key}/"
        + "{sample}.{alnr}.{ddup}.longtr.{catalog_key}.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/tr/longtr/{catalog_key}/logs/"
        + "{sample}.{alnr}.{ddup}.longtr.{catalog_key}.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.longtr.{catalog_key}.bench.tsv",
    conda:
        config["longtr"]["env_yaml"]
    threads: _longtr_threads
    resources:
        threads=_longtr_threads,
        vcpu=_longtr_threads,
        mem_mb=_longtr_mem_mb,
        partition=_longtr_partition,
    wildcard_constraints:
        alnr="|".join(sorted(LONGTR_ALLOWED_ALIGNERS)),
        catalog_key="|".join(LONGTR_CATALOG_KEYS),
    params:
        cluster_sample=ret_sample,
        catalog_name=lambda wildcards: _longtr_catalog_name(wildcards.catalog_key),
        command=lambda wildcards: str(_longtr_required("command")),
        reference=lambda wildcards: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        sample_name=lambda wildcards: wildcards.sample,
        extra_args=lambda wildcards: _longtr_extra_args(),
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {log:q})
        mkdir -p $(dirname {output.vcf:q})

        test -s {input.cram:q} || (echo "ERROR: missing LongTR CRAM: {input.cram:q}" | tee {log:q}; exit 1)
        test -s {input.crai:q} || (echo "ERROR: missing LongTR CRAI: {input.crai:q}" | tee {log:q}; exit 1)
        test -s {input.regions_bed:q} || (echo "ERROR: missing LongTR regions BED: {input.regions_bed:q}" | tee {log:q}; exit 1)
        test -s {params.reference:q} || (echo "ERROR: missing LongTR reference FASTA: {params.reference:q}" | tee {log:q}; exit 1)

        tmp_dir=$(mktemp -d)
        trap 'rm -rf "${tmp_dir}"' EXIT

        regions="${tmp_dir}/regions.bed"
        case {input.regions_bed:q} in
            *.gz)
                gzip -dc -- {input.regions_bed:q} > "${regions}"
                ;;
            *)
                cp -- {input.regions_bed:q} "${regions}"
                ;;
        esac
        test -s "${regions}" || (echo "ERROR: LongTR regions BED expanded to an empty file: {input.regions_bed:q}" | tee -a {log:q}; exit 1)

        extra_args=()
        if [[ -n "{params.extra_args}" ]]; then
            read -r -a extra_args <<< "{params.extra_args}"
        fi

        {params.command:q} \
            --bams {input.cram:q} \
            --fasta {params.reference:q} \
            --regions "${regions}" \
            --tr-vcf "${tmp_dir}/calls.vcf.gz" \
            --bam-samps {params.sample_name:q} \
            --bam-libs {params.sample_name:q} \
            --log {log:q} \
            "${extra_args[@]}"

        test -s "${tmp_dir}/calls.vcf.gz" || (echo "ERROR: LongTR did not create output VCF for {wildcards.sample} {wildcards.catalog_key}" | tee -a {log:q}; exit 1)
        mv "${tmp_dir}/calls.vcf.gz" {output.vcf:q}
        tabix -f -p vcf {output.vcf:q}
        """


localrules:
    longtr_all,
    longtr_diseaser,


rule longtr_all:  # TARGET: run LongTR with the genome-wide TRExplorer catalog
    input:
        lambda wildcards: _longtr_outputs("all", require_non_empty=True)
    output:
        touch(MDIR + "other_reports/longtr_all.done")
    shell:
        "touch {output}"


rule longtr_diseaser:  # TARGET: run LongTR with the disease-repeat catalog
    input:
        lambda wildcards: _longtr_outputs("diseaser", require_non_empty=True)
    output:
        touch(MDIR + "other_reports/longtr_diseaser.done")
    shell:
        "touch {output}"
