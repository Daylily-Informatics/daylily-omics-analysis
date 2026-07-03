"""Exploratory Paraphase-on-ONT SMN1/SMN2 calling."""


PARAPHASE_ONT_TARGETS = {
    "produce_paraphase_ont_exploratory",
    "paraphase_ont_exploratory_results",
    "paraphase_ont_exploratory",
}
PARAPHASE_ONT_REQUIRED_COLUMNS = [
    "sample",
    "ont_input_cram_or_bam",
    "input_index",
    "reference_fasta",
    "expected_smn1",
    "expected_smn2",
    "exploratory_label",
]
PARAPHASE_ONT_DIR = MDIR + "other_reports/paraphase_ont_exploratory/"


def _paraphase_ont_requested():
    return bool(_requested_targets() & PARAPHASE_ONT_TARGETS)


def _paraphase_ont_manifest_path():
    configured = config.get("paraphase_ont_manifest", "")
    if not _filled(configured):
        if _paraphase_ont_requested():
            raise WorkflowError(
                "produce_paraphase_ont_exploratory requires "
                "--config paraphase_ont_manifest=config/paraphase_ont_manifest.tsv"
            )
        return ""
    path = os.path.abspath(str(configured))
    if not os.path.exists(path):
        raise WorkflowError(f"Paraphase ONT manifest not found: {path}")
    return path


def _load_paraphase_ont_rows():
    manifest = _paraphase_ont_manifest_path()
    if not manifest:
        return []
    rows = []
    with open(manifest, encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        missing = [
            column
            for column in PARAPHASE_ONT_REQUIRED_COLUMNS
            if column not in (reader.fieldnames or [])
        ]
        if missing:
            raise WorkflowError(
                "Paraphase ONT manifest missing required columns: "
                + ",".join(missing)
            )
        for row in reader:
            normalized = {
                column: str(row.get(column, "") or "").strip()
                for column in PARAPHASE_ONT_REQUIRED_COLUMNS
            }
            for column, value in normalized.items():
                if not _filled(value):
                    raise WorkflowError(
                        f"Paraphase ONT manifest row for sample={normalized.get('sample', '<unknown>')} "
                        f"has blank required column {column}."
                    )
            if normalized["exploratory_label"] != "EXPLORATORY_ONT_PARAPHASE":
                raise WorkflowError(
                    "Paraphase ONT manifest exploratory_label must be EXPLORATORY_ONT_PARAPHASE "
                    f"for sample {normalized['sample']}."
                )
            if not re.match(r"^[A-Za-z0-9._-]+$", normalized["sample"]):
                raise WorkflowError(
                    f"Paraphase ONT sample has unsupported characters: {normalized['sample']!r}."
                )
            rows.append(normalized)
    if not rows and _paraphase_ont_requested():
        raise WorkflowError("Paraphase ONT manifest has no rows.")
    samples = [row["sample"] for row in rows]
    duplicated = sorted({sample for sample in samples if samples.count(sample) > 1})
    if duplicated:
        raise WorkflowError(
            "Paraphase ONT manifest has duplicate sample rows: "
            + ",".join(duplicated)
        )
    return rows


PARAPHASE_ONT_ROWS = _load_paraphase_ont_rows()
PARAPHASE_ONT_BY_SAMPLE = {row["sample"]: row for row in PARAPHASE_ONT_ROWS}


def paraphase_ont_samples():
    return [row["sample"] for row in PARAPHASE_ONT_ROWS]


def paraphase_ont_row(wildcards):
    try:
        return PARAPHASE_ONT_BY_SAMPLE[wildcards.sample]
    except KeyError as exc:
        raise WorkflowError(
            f"No Paraphase ONT manifest row for sample {wildcards.sample}."
        ) from exc


def paraphase_ont_alignment(wildcards):
    return paraphase_ont_row(wildcards)["ont_input_cram_or_bam"]


def paraphase_ont_index(wildcards):
    return paraphase_ont_row(wildcards)["input_index"]


def paraphase_ont_reference(wildcards):
    return paraphase_ont_row(wildcards)["reference_fasta"]


def paraphase_ont_sample_tsvs(wildcards=None):
    return expand(
        PARAPHASE_ONT_DIR + "{sample}/{sample}.paraphase_ont_exploratory.summary.tsv",
        sample=paraphase_ont_samples(),
    )


def paraphase_ont_sample_dones(wildcards=None):
    return expand(
        PARAPHASE_ONT_DIR + "{sample}/{sample}.paraphase_ont_exploratory.done",
        sample=paraphase_ont_samples(),
    )


rule paraphase_ont_exploratory:
    """Run PacBio Paraphase on ONT BAM/CRAM inputs under an explicit exploratory label."""
    input:
        alignment=paraphase_ont_alignment,
        index=paraphase_ont_index,
        reference=paraphase_ont_reference,
    output:
        work_dir=directory(PARAPHASE_ONT_DIR + "{sample}/work"),
        paraphase_dir=directory(PARAPHASE_ONT_DIR + "{sample}/paraphase_out"),
        summary_tsv=PARAPHASE_ONT_DIR + "{sample}/{sample}.paraphase_ont_exploratory.summary.tsv",
        checksum_tsv=PARAPHASE_ONT_DIR + "{sample}/{sample}.paraphase_ont_exploratory.checksums.tsv",
        done=PARAPHASE_ONT_DIR + "{sample}/{sample}.paraphase_ont_exploratory.done",
    params:
        cluster_sample=lambda wildcards: wildcards.sample,
        expected_smn1=lambda wildcards: paraphase_ont_row(wildcards)["expected_smn1"],
        expected_smn2=lambda wildcards: paraphase_ont_row(wildcards)["expected_smn2"],
        exploratory_label=lambda wildcards: paraphase_ont_row(wildcards)["exploratory_label"],
    log:
        PARAPHASE_ONT_DIR + "{sample}/logs/{sample}.paraphase_ont_exploratory.log",
    benchmark:
        MDIR + "benchmarks/paraphase_ont_exploratory.{sample}.bench.tsv"
    threads: config["paraphase_ont_exploratory"]["threads"]
    resources:
        partition=config["paraphase_ont_exploratory"]["partition"],
        threads=config["paraphase_ont_exploratory"]["threads"],
        vcpu=config["paraphase_ont_exploratory"]["threads"],
        mem_mb=config["paraphase_ont_exploratory"]["mem_mb"],
    container: None
    conda:
        "../envs/paraphase_v3.5.yaml"
    shell:
        r"""
        set -euo pipefail
        rm -rf {output.work_dir:q} {output.paraphase_dir:q}
        mkdir -p {output.work_dir:q} {output.paraphase_dir:q} $(dirname {log:q})
        rm -f {output.summary_tsv:q} {output.checksum_tsv:q} {output.done:q}

        reference={input.reference:q}
        if [[ "$reference" != /* ]]; then
          reference="$PWD/$reference"
        fi
        test -s "$reference"
        test -s "$reference.fai"
        test -s {input.alignment:q}
        test -s {input.index:q}

        input_for_paraphase={input.alignment:q}
        input_class="ONT_BAM_FOR_PARAPHASE"
        case "$input_for_paraphase" in
          *.cram)
            input_class="ONT_CRAM_CONVERTED_TO_BAM_FOR_PARAPHASE"
            converted_bam="{output.work_dir}/{wildcards.sample}.paraphase_input.bam"
            samtools view -@ {threads} -T "$reference" -b -o "$converted_bam" "$input_for_paraphase" >> {log:q} 2>&1
            samtools index -@ {threads} "$converted_bam" >> {log:q} 2>&1
            input_for_paraphase="$converted_bam"
            ;;
        esac

        paraphase \
          -b "$input_for_paraphase" \
          -r "$reference" \
          -o {output.paraphase_dir:q} \
          -p {wildcards.sample:q} \
          -g smn1 \
          --genome 38 \
          -t {threads} \
          --samtools "$(command -v samtools)" \
          --minimap2 "$(command -v minimap2)" \
          >> {log:q} 2>&1

        json_path="{output.paraphase_dir}/{wildcards.sample}.paraphase.json"
        test -s "$json_path"
        python workflow/scripts/paraphase_ont_exploratory_summary.py \
          --sample {wildcards.sample:q} \
          --input {input.alignment:q} \
          --reference "$reference" \
          --expected-smn1 {params.expected_smn1:q} \
          --expected-smn2 {params.expected_smn2:q} \
          --exploratory-label {params.exploratory_label:q} \
          --input-class "$input_class" \
          --json-path "$json_path" \
          --output {output.summary_tsv:q} \
          >> {log:q} 2>&1
        {
          printf 'path\tsha256\n'
          sha256sum {input.alignment:q}
          sha256sum {input.index:q}
          sha256sum "$reference"
          sha256sum "$json_path"
        } | awk 'NR == 1 {print; next} {print $2 "\t" $1}' > {output.checksum_tsv:q}
        touch {output.done:q}
        """


localrules:
    paraphase_ont_exploratory_results,
    produce_paraphase_ont_exploratory,


rule paraphase_ont_exploratory_results:
    input:
        paraphase_ont_sample_tsvs,
        paraphase_ont_sample_dones,
    output:
        PARAPHASE_ONT_DIR + "paraphase_ont_results.tsv"
    log:
        PARAPHASE_ONT_DIR + "logs/paraphase_ont_results.log"
    benchmark:
        MDIR + "benchmarks/paraphase_ont_exploratory_results.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        first=1
        : > {output:q}
        for tsv in {input:q}; do
          case "$tsv" in
            *.summary.tsv)
              if [ "$first" -eq 1 ]; then
                cat "$tsv" >> {output:q}
                first=0
              else
                tail -n +2 "$tsv" >> {output:q}
              fi
              ;;
          esac
        done > {log:q} 2>&1
        """


rule produce_paraphase_ont_exploratory:  # TARGET : Run exploratory Paraphase SMN1/SMN2 on ONT alignments
    input:
        results=PARAPHASE_ONT_DIR + "paraphase_ont_results.tsv",
    output:
        "logs/paraphase_ont_exploratory.done"
    log:
        MDIR + "logs/produce_paraphase_ont_exploratory.log"
    benchmark:
        MDIR + "benchmarks/produce_paraphase_ont_exploratory.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        test -s {input.results:q}
        touch {output:q}
        """
