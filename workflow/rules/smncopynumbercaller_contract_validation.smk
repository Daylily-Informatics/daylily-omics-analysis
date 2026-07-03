"""Manifest-driven SMNCopyNumberCaller whole-genome input contract validation.

Accepted production input class: whole_genome_wgs_bam_cram.
Strict preflight failure text: SMN12 input preflight failed required checks.
"""


SMNCOPY_CONTRACT_TARGETS = {
    "produce_smncopynumbercaller_contract_validation",
    "smncopynumbercaller_contract_results",
    "smncopynumbercaller_contract_validation",
}
SMNCOPY_CONTRACT_REQUIRED_COLUMNS = [
    "sample",
    "input_cram_or_bam",
    "input_index",
    "reference_fasta",
    "genome",
    "resource_dir",
    "expected_smn1",
    "expected_smn2",
    "source_analysis",
]
SMNCOPY_CONTRACT_DIR = MDIR + "other_reports/smncopynumbercaller_contract/"


def _smncopy_contract_requested():
    return bool(_requested_targets() & SMNCOPY_CONTRACT_TARGETS)


def _smncopy_contract_manifest_path():
    configured = config.get("smncopynumbercaller_contract_manifest", "")
    if not _filled(configured):
        if _smncopy_contract_requested():
            raise WorkflowError(
                "produce_smncopynumbercaller_contract_validation requires "
                "--config smncopynumbercaller_contract_manifest=config/smncopynumbercaller_contract_manifest.tsv"
            )
        return ""
    path = os.path.abspath(str(configured))
    if not os.path.exists(path):
        raise WorkflowError(
            f"SMNCopyNumberCaller contract manifest not found: {path}"
        )
    return path


def _load_smncopy_contract_rows():
    manifest = _smncopy_contract_manifest_path()
    if not manifest:
        return []
    rows = []
    with open(manifest, encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        missing = [
            column
            for column in SMNCOPY_CONTRACT_REQUIRED_COLUMNS
            if column not in (reader.fieldnames or [])
        ]
        if missing:
            raise WorkflowError(
                "SMNCopyNumberCaller contract manifest missing required columns: "
                + ",".join(missing)
            )
        for row in reader:
            normalized = {
                column: str(row.get(column, "") or "").strip()
                for column in SMNCOPY_CONTRACT_REQUIRED_COLUMNS
            }
            for column, value in normalized.items():
                if not _filled(value):
                    raise WorkflowError(
                        f"SMNCopyNumberCaller contract manifest row for sample={normalized.get('sample', '<unknown>')} "
                        f"has blank required column {column}."
                    )
            sample = normalized["sample"]
            if not re.match(r"^[A-Za-z0-9._-]+$", sample):
                raise WorkflowError(
                    f"SMNCopyNumberCaller contract sample has unsupported characters: {sample!r}."
                )
            if normalized["genome"] not in {"37", "38"}:
                raise WorkflowError(
                    "SMNCopyNumberCaller contract manifest genome must be 37 or 38; "
                    f"observed {normalized['genome']!r} for sample {sample}."
                )
            rows.append(normalized)
    if not rows and _smncopy_contract_requested():
        raise WorkflowError("SMNCopyNumberCaller contract manifest has no rows.")
    samples = [row["sample"] for row in rows]
    duplicated = sorted({sample for sample in samples if samples.count(sample) > 1})
    if duplicated:
        raise WorkflowError(
            "SMNCopyNumberCaller contract manifest has duplicate sample rows: "
            + ",".join(duplicated)
        )
    return rows


SMNCOPY_CONTRACT_ROWS = _load_smncopy_contract_rows()
SMNCOPY_CONTRACT_BY_SAMPLE = {
    row["sample"]: row for row in SMNCOPY_CONTRACT_ROWS
}


def smncopy_contract_samples():
    return [row["sample"] for row in SMNCOPY_CONTRACT_ROWS]


def smncopy_contract_row(wildcards):
    try:
        return SMNCOPY_CONTRACT_BY_SAMPLE[wildcards.sample]
    except KeyError as exc:
        raise WorkflowError(
            f"No SMNCopyNumberCaller contract manifest row for sample {wildcards.sample}."
        ) from exc


def smncopy_contract_alignment(wildcards):
    return smncopy_contract_row(wildcards)["input_cram_or_bam"]


def smncopy_contract_index(wildcards):
    return smncopy_contract_row(wildcards)["input_index"]


def smncopy_contract_reference(wildcards):
    return smncopy_contract_row(wildcards)["reference_fasta"]


def smncopy_contract_resource_files(wildcards):
    row = smncopy_contract_row(wildcards)
    resource_dir = row["resource_dir"]
    genome = row["genome"]
    return [
        os.path.join(resource_dir, f"SMN_region_{genome}.bed"),
        os.path.join(resource_dir, f"SMN_SNP_{genome}.txt"),
        os.path.join(resource_dir, f"SMN_target_variant_{genome}.txt"),
        os.path.join(resource_dir, "SMN_gmm.txt"),
    ]


def smncopy_contract_sample_tsvs():
    return expand(
        SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.summary.tsv",
        sample=smncopy_contract_samples(),
    )


def smncopy_contract_sample_dones():
    return expand(
        SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.done",
        sample=smncopy_contract_samples(),
    )


rule smncopynumbercaller_contract_validation:
    """Run SMNCopyNumberCaller against manifest-declared whole-genome BAM/CRAM inputs only."""
    input:
        alignment=smncopy_contract_alignment,
        index=smncopy_contract_index,
        reference=smncopy_contract_reference,
        resources=smncopy_contract_resource_files,
    output:
        input_qc=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.input_qc.tsv",
        region_depth=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.region_depth.tsv",
        required_status=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.required_regions_status.tsv",
        alignment_flags=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.alignment_flags.tsv",
        mqc=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.preflight_mqc.tsv",
        summary_json=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.summary.json",
        summary_tsv=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.summary.tsv",
        checksum_tsv=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.checksums.tsv",
        done=SMNCOPY_CONTRACT_DIR + "{sample}/{sample}.smncopynumbercaller_contract.done",
    params:
        cluster_sample=lambda wildcards: wildcards.sample,
        genome=lambda wildcards: smncopy_contract_row(wildcards)["genome"],
        resource_dir=lambda wildcards: smncopy_contract_row(wildcards)["resource_dir"],
        expected_smn1=lambda wildcards: smncopy_contract_row(wildcards)["expected_smn1"],
        expected_smn2=lambda wildcards: smncopy_contract_row(wildcards)["expected_smn2"],
        source_analysis=lambda wildcards: smncopy_contract_row(wildcards)["source_analysis"],
        max_sample_records=lambda wildcards: config.get("smn12_input_qc", {}).get(
            "max_sample_records", 200000
        ),
        min_norm_bin_present_fraction=lambda wildcards: config.get(
            "smn12_input_qc", {}
        ).get("min_norm_bin_present_fraction", 0.95),
    log:
        SMNCOPY_CONTRACT_DIR + "{sample}/logs/{sample}.smncopynumbercaller_contract.log",
    benchmark:
        MDIR + "benchmarks/smncopynumbercaller_contract_validation.{sample}.bench.tsv"
    threads: config["smncopynumbercaller_contract_validation"]["threads"]
    resources:
        partition=config["smncopynumbercaller_contract_validation"]["partition"],
        threads=config["smncopynumbercaller_contract_validation"]["threads"],
        vcpu=config["smncopynumbercaller_contract_validation"]["threads"],
        mem_mb=config["smncopynumbercaller_contract_validation"]["mem_mb"],
    container: None
    conda:
        "../envs/smn12_v0.1.yaml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.input_qc:q}) $(dirname {log:q})
        rm -f {output.input_qc:q} {output.region_depth:q} {output.required_status:q} \
              {output.alignment_flags:q} {output.mqc:q} {output.summary_json:q} \
              {output.summary_tsv:q} {output.checksum_tsv:q} {output.done:q}

        resource_dir={params.resource_dir:q}
        if [[ "$resource_dir" != /* ]]; then
          resource_dir="$PWD/$resource_dir"
        fi
        reference={input.reference:q}
        if [[ "$reference" != /* ]]; then
          reference="$PWD/$reference"
        fi
        test -s "$reference"
        test -s "$reference.fai"
        test -s {input.alignment:q}
        test -s {input.index:q}
        test -s "$resource_dir/SMN_region_{params.genome}.bed"
        test -s "$resource_dir/SMN_SNP_{params.genome}.txt"
        test -s "$resource_dir/SMN_target_variant_{params.genome}.txt"
        test -s "$resource_dir/SMN_gmm.txt"

        python workflow/scripts/smn12_input_qc.py \
          --input {input.alignment:q} \
          --reference "$reference" \
          --regions-bed "$resource_dir/SMN_region_{params.genome}.bed" \
          --snp-file "$resource_dir/SMN_SNP_{params.genome}.txt" \
          --target-variant-file "$resource_dir/SMN_target_variant_{params.genome}.txt" \
          --sample {wildcards.sample:q} \
          --aligner smncopy_contract \
          --deduper whole_genome_input \
          --input-qc {output.input_qc:q} \
          --region-depth {output.region_depth:q} \
          --required-status {output.required_status:q} \
          --alignment-flags {output.alignment_flags:q} \
          --mqc {output.mqc:q} \
          --max-sample-records {params.max_sample_records:q} \
          --min-norm-bin-present-fraction {params.min_norm_bin_present_fraction:q} \
          > {log:q} 2>&1

        manifest=$(mktemp)
        smn_workdir=$(mktemp -d)
        trap 'rm -f "$manifest"; rm -rf "$smn_workdir"' EXIT
        realpath {input.alignment:q} > "$manifest"
        cp "$(command -v smn_caller.py)" "$smn_workdir/smn_caller.py"
        ln -s "$resource_dir" "$smn_workdir/data"
        "$CONDA_PREFIX/bin/python" "$smn_workdir/smn_caller.py" \
          --manifest "$manifest" \
          --genome {params.genome:q} \
          --outDir $(dirname {output.summary_json:q}) \
          --prefix {wildcards.sample}.smncopynumbercaller_contract.summary \
          --reference "$reference" \
          --threads {threads} \
          >> {log:q} 2>&1
        test -s {output.summary_json:q}
        "$CONDA_PREFIX/bin/python" -m json.tool {output.summary_json:q} >/dev/null

        python workflow/scripts/smncopynumbercaller_contract_summary.py \
          --sample {wildcards.sample:q} \
          --input {input.alignment:q} \
          --reference "$reference" \
          --resource-dir "$resource_dir" \
          --genome {params.genome:q} \
          --expected-smn1 {params.expected_smn1:q} \
          --expected-smn2 {params.expected_smn2:q} \
          --source-analysis {params.source_analysis:q} \
          --summary-json {output.summary_json:q} \
          --input-qc {output.input_qc:q} \
          --required-status {output.required_status:q} \
          --output {output.summary_tsv:q} \
          >> {log:q} 2>&1

        {
          printf 'path\tsha256\n'
          sha256sum {input.alignment:q}
          sha256sum {input.index:q}
          sha256sum "$reference"
          sha256sum "$resource_dir/SMN_region_{params.genome}.bed"
          sha256sum "$resource_dir/SMN_SNP_{params.genome}.txt"
          sha256sum "$resource_dir/SMN_target_variant_{params.genome}.txt"
          sha256sum "$resource_dir/SMN_gmm.txt"
        } | awk 'NR == 1 {print; next} {print $2 "\t" $1}' > {output.checksum_tsv:q}
        touch {output.done:q}
        """


localrules:
    smncopynumbercaller_contract_results,
    produce_smncopynumbercaller_contract_validation,


rule smncopynumbercaller_contract_results:
    input:
        smncopy_contract_sample_tsvs,
        smncopy_contract_sample_dones,
    output:
        SMNCOPY_CONTRACT_DIR + "smncopy_contract_results.tsv"
    log:
        SMNCOPY_CONTRACT_DIR + "logs/smncopy_contract_results.log"
    benchmark:
        MDIR + "benchmarks/smncopynumbercaller_contract_results.bench.tsv"
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


rule produce_smncopynumbercaller_contract_validation:  # TARGET : Validate SMNCopyNumberCaller whole-genome WGS input contract
    input:
        results=SMNCOPY_CONTRACT_DIR + "smncopy_contract_results.tsv",
    output:
        "logs/smncopynumbercaller_contract_validation.done"
    log:
        MDIR + "logs/produce_smncopynumbercaller_contract_validation.log"
    benchmark:
        MDIR + "benchmarks/produce_smncopynumbercaller_contract_validation.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        test -s {input.results:q}
        touch {output:q}
        """
