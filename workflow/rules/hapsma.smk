"""Native DayOA port of the HapSMA bam_single_remap path."""


def _hapsma_cfg():
    return config.get("hapsma", {})


def _hapsma_required(key):
    value = _hapsma_cfg().get(key, "")
    if not _filled(value):
        raise WorkflowError(
            f"HapSMA is dev_exploratory and requires config.hapsma.{key}."
        )
    return str(value)


def _hapsma_optional(key, default=""):
    value = _hapsma_cfg().get(key, default)
    if not _filled(value):
        return ""
    return str(value)


def _hapsma_mode(wildcards):
    mode = _hapsma_required("start")
    if mode != "bam_single_remap":
        raise WorkflowError(
            "DayOA native HapSMA currently supports only config.hapsma.start="
            f"bam_single_remap; observed {mode!r}."
        )
    return mode


rule hapsma:  # TARGET : Run native HapSMA exploratory ONT SMN analysis.
    """Execute a native Snakemake port of HapSMA on an ONT/HiOMR long-read CRAM."""
    input:
        cram=smn_long_cram,
        crai=smn_long_crai,
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/results/{sample}.{alnr}.{ddup}"),
        coverage=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.smn_region_coverage.tsv",
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.summary.tsv",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
    params:
        cluster_sample=ret_sample,
        start=_hapsma_mode,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ploidy=lambda wildcards: _hapsma_required("ploidy"),
        smn_region=lambda wildcards: _hapsma_required("smn_region"),
        min_cov=lambda wildcards: str(_hapsma_cfg().get("min_smn_region_mean_coverage", 4)),
        calling_target_bed=lambda wildcards: _hapsma_required("calling_target_bed"),
        calling_target_region=lambda wildcards: _hapsma_required("calling_target_region"),
        phaseset_region=lambda wildcards: _hapsma_required("phaseset_region"),
        homopolymer_bed=lambda wildcards: _hapsma_required("homopolymer_bed"),
        clair3model=lambda wildcards: _hapsma_required("clair3model"),
        clair3_optional=lambda wildcards: _hapsma_required("clair3_optional"),
        minimap_index=lambda wildcards: _hapsma_required("minimap_index"),
        minimap_param=lambda wildcards: _hapsma_required("minimap_param"),
        fastq_tags=lambda wildcards: _hapsma_required("fastq_tags"),
        min_read_length=lambda wildcards: _hapsma_required("min_read_length"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/logs/{sample}.{alnr}.{ddup}.hapsma.log",
    benchmark:
        MDIR + "benchmarks/hapsma.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["hapsma"]["threads"]
    conda:
        "../envs/hapsma_v0.1.yaml"
    resources:
        partition=config["hapsma"]["partition"],
        threads=config["hapsma"]["threads"],
        vcpu=config["hapsma"]["threads"],
        mem_mb=config["hapsma"]["mem_mb"],
    shell:
        r"""
        set -euo pipefail

        rm -rf {output.results_dir:q}
        mkdir -p {output.results_dir:q} $(dirname {output.summary:q}) $(dirname {log:q})
        rm -f {output.coverage:q} {output.summary:q} {output.done:q}
        touch {log:q}

        for required_path in \
          {params.reference:q} \
          {params.minimap_index:q} \
          {params.calling_target_bed:q} \
          {params.homopolymer_bed:q} \
          {input.cram:q} \
          {input.crai:q}
        do
          test -s "$required_path" || (echo "Missing required HapSMA path: $required_path" >> {log:q}; exit 1)
        done

        ref_path={params.reference:q}
        ref_no_ext="${{ref_path%.*}}"
        test -s "$ref_path.fai" || (echo "Missing FASTA index: $ref_path.fai" >> {log:q}; exit 1)
        if [[ -s "$ref_path.dict" ]]; then
          :
        elif [[ -s "$ref_no_ext.dict" ]]; then
          :
        else
          echo "Missing FASTA dictionary for HapSMA reference: $ref_path" >> {log:q}
          exit 1
        fi

        export TMPDIR="{output.results_dir}/tmp"
        mkdir -p "$TMPDIR"

        smn_bam="{output.results_dir}/input.smn_region.bam"
        condition_bam="{output.results_dir}/input.smn_region.condition.bam"
        fastq="{output.results_dir}/input.smn_region.condition.fastq"
        remap_sam="{output.results_dir}/input.smn_region.remap.sam"
        remap_bam="{output.results_dir}/input.smn_region.remap.sort.bam"
        rg_bam="{output.results_dir}/input.smn_region.remap.rg.bam"
        rg_id="{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.hapsma"
        rg_line="@RG\tID:${{rg_id}}\tSM:{wildcards.sample}\tPL:ONT\tLB:${{rg_id}}"
        clair3_model={params.clair3model:q}
        clair3_model="${{clair3_model//'$CONDA_PREFIX'/$CONDA_PREFIX}}"
        clair3_model="${{clair3_model//'${{CONDA_PREFIX}}'/$CONDA_PREFIX}}"
        test -d "$clair3_model" || (echo "Missing required HapSMA Clair3 model directory: $clair3_model" >> {log:q}; exit 1)

        samtools depth -r {params.smn_region:q} -a {input.cram:q} > {output.coverage:q}
        awk '{{sum += $3; n += 1}} END {{if (n == 0) {{print 0}} else {{printf "%.6f\n", sum / n}}}}' \
          {output.coverage:q} > "{output.results_dir}/smn_region.mean_coverage.txt"

        python - <<'PY'
from pathlib import Path

mean_cov = float(Path("{output.results_dir}/smn_region.mean_coverage.txt").read_text().strip())
min_cov = float("{params.min_cov}")
if mean_cov < min_cov:
    reason = f"mean_smn_region_coverage {{mean_cov:.3f}} < required {{min_cov:.3f}}"
    rows = [
        "sample\taligner\tdeduper\tcaller\tcaller_class\tdev_status\tevidence_source\tploidy\tsmn_region\tmean_smn_region_coverage\tbed_phase_set\tbed_phase_status\tbed_phase_reason\tregion_phase_set\tregion_phase_status\tregion_phase_reason\toutput_dir",
        "{wildcards.sample}\t{wildcards.alnr}\t{wildcards.ddup}\thapsma\tlong_read_haplotype\tdev_exploratory\tONT_long_read_cram\t{params.ploidy}\t{params.smn_region}\t"
        + f"{{mean_cov:.6f}}"
        + "\tNA\tno_call_low_coverage\t"
        + reason
        + "\tNA\tno_call_low_coverage\t"
        + reason
        + "\t{output.results_dir}",
    ]
    Path("{output.summary}").write_text("\n".join(rows) + "\n", encoding="utf-8")
    Path("{output.done}").touch()
    with Path("{log}").open("a", encoding="utf-8") as handle:
        handle.write(
            f"HapSMA no-call low coverage for {wildcards.sample}: {{reason}}.\n"
        )
PY
        if [[ -s {output.summary:q} && -e {output.done:q} ]]; then
          exit 0
        fi

        echo "HapSMA native path start: sample={wildcards.sample} alnr={wildcards.alnr} ddup={wildcards.ddup}" >> {log:q}
        echo "Extracting SMN region: {params.smn_region}" >> {log:q}
        samtools view -@ {threads} -b -T {params.reference:q} {input.cram:q} {params.smn_region:q} > "$smn_bam" 2>> {log:q}
        samtools index -@ {threads} "$smn_bam" >> {log:q} 2>&1

        echo "Filtering reads by sequence_length >= {params.min_read_length}" >> {log:q}
        sambamba view -t {threads} -f bam \
          -F "sequence_length >= {params.min_read_length}" \
          -o "$condition_bam" "$smn_bam" >> {log:q} 2>&1
        sambamba index -t {threads} "$condition_bam" "$condition_bam.bai" >> {log:q} 2>&1

        echo "Converting filtered BAM to FASTQ with tags {params.fastq_tags}" >> {log:q}
        samtools fastq -@ {threads} -T {params.fastq_tags:q} "$condition_bam" > "$fastq" 2>> {log:q}

        echo "Remapping with minimap2 {params.minimap_param}" >> {log:q}
        minimap2 -t {threads} {params.minimap_param} -R "$rg_line" {params.minimap_index:q} "$fastq" > "$remap_sam" 2>> {log:q}
        samtools view -@ {threads} -S -b "$remap_sam" 2>> {log:q} \
          | samtools sort -@ {threads} -m 4G -o "$remap_bam" - 2>> {log:q}
        samtools index -@ {threads} "$remap_bam" >> {log:q} 2>&1
        samtools addreplacerg -@ {threads} -w -r "$rg_line" "$remap_bam" -o "$rg_bam" >> {log:q} 2>&1
        samtools index -@ {threads} "$rg_bam" >> {log:q} 2>&1

        run_approach() {{
          local approach="$1"
          local intervals="$2"
          local phase_region="$3"
          local outdir="{output.results_dir}/${{approach}}"
          mkdir -p "$outdir"/{{vcf,bam,clair3,sniffles,logs}}

          local raw_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.gatk.raw.vcf.gz"
          local snv_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.gatk.snv.vcf"
          local wh_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.whatshap.vcf"
          local wh_vcfgz="$wh_vcf.gz"
          local hp_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.whatshap.homopolymer.vcf"
          local hp_vcfgz="$hp_vcf.gz"
          local snp_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.filter.snp.vcf.gz"
          local indel_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.filter.indel.vcf.gz"
          local snp_filter_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.filter.snp.filtered.vcf.gz"
          local indel_filter_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.filter.indel.filtered.vcf.gz"
          local filter_vcf="$outdir/vcf/{wildcards.sample}.${{approach}}.filter.vcf.gz"
          local tagged_bam="$outdir/bam/{wildcards.sample}.${{approach}}.whatshap.tagged.bam"
          local ps_file="$outdir/{wildcards.sample}.${{approach}}.phaseset.txt"
          local ps_status="$outdir/{wildcards.sample}.${{approach}}.phaseset.status.tsv"

          echo "Running HapSMA $approach approach intervals=$intervals phase_region=$phase_region" >> {log:q}
          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" HaplotypeCaller \
            --reference {params.reference:q} \
            --input "$rg_bam" \
            --output "$raw_vcf" \
            --ploidy {params.ploidy:q} \
            --intervals "$intervals" \
            --dont-use-soft-clipped-bases \
            --pair-hmm-implementation LOGLESS_CACHING \
            --tmp-dir "$TMPDIR" >> {log:q} 2>&1
          tabix -f -p vcf "$raw_vcf" >> {log:q} 2>&1

          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" SelectVariants \
            --reference {params.reference:q} \
            -V "$raw_vcf" \
            --select-type-to-include SNP \
            -O "$snv_vcf" \
            --tmp-dir "$TMPDIR" >> {log:q} 2>&1

          whatshap polyphase \
            "$snv_vcf" "$rg_bam" \
            --ploidy {params.ploidy:q} \
            --reference {params.reference:q} \
            --ignore-read-groups \
            -o "$wh_vcf" >> {log:q} 2>&1
          bgzip -f -@ {threads} "$wh_vcf" >> {log:q} 2>&1
          tabix -f -p vcf "$wh_vcfgz" >> {log:q} 2>&1

          echo '##INFO=<ID=RegionRef,Number=1,Type=String,Description="Variant is within specific region in reference genome">' \
            | bcftools annotate \
                -a {params.homopolymer_bed:q} \
                -c CHROM,FROM,TO,RegionRef \
                -h /dev/stdin \
                "$wh_vcfgz" > "$hp_vcf" 2>> {log:q}
          bgzip -f -@ {threads} "$hp_vcf" >> {log:q} 2>&1
          tabix -f -p vcf "$hp_vcfgz" >> {log:q} 2>&1

          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" SelectVariants \
            --reference {params.reference:q} \
            --variant "$hp_vcfgz" \
            --output "$snp_vcf" \
            --select-type-to-exclude INDEL \
            --tmp-dir "$TMPDIR" >> {log:q} 2>&1
          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" SelectVariants \
            --reference {params.reference:q} \
            --variant "$hp_vcfgz" \
            --output "$indel_vcf" \
            --select-type-to-include INDEL \
            --tmp-dir "$TMPDIR" >> {log:q} 2>&1
          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" VariantFiltration \
            --reference {params.reference:q} \
            --variant "$snp_vcf" \
            --output "$snp_filter_vcf" \
            --tmp-dir "$TMPDIR" \
            --filter-name SNP_LowQualityDepth --filter-expression 'QD < 2.0' \
            --filter-name SNP_MappingQuality --filter-expression 'MQ < 40.0' \
            --filter-name SNP_StrandBias --filter-expression 'FS > 10.0' \
            --filter-name Ref_Homopolymer --filter-expression 'vc.hasAttribute("RegionRef")' \
            --cluster-size 3 --cluster-window-size 35 >> {log:q} 2>&1
          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" VariantFiltration \
            --reference {params.reference:q} \
            --variant "$indel_vcf" \
            --output "$indel_filter_vcf" \
            --tmp-dir "$TMPDIR" \
            --filter-name INDEL_LowQualityDepth --filter-expression 'QD < 2.0' \
            --filter-name INDEL_StrandBias --filter-expression 'FS > 200.0' \
            --filter-name INDEL_ReadPosRankSum --filter-expression 'ReadPosRankSum < -20.0' >> {log:q} 2>&1
          gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" MergeVcfs \
            --INPUT "$snp_filter_vcf" \
            --INPUT "$indel_filter_vcf" \
            --OUTPUT "$filter_vcf" \
            --TMP_DIR "$TMPDIR" >> {log:q} 2>&1
          tabix -f -p vcf "$filter_vcf" >> {log:q} 2>&1

          local whatshap_status=0
          set +e
          whatshap haplotag \
            "$filter_vcf" "$rg_bam" \
            -o "$tagged_bam" \
            --reference {params.reference:q} \
            --ploidy {params.ploidy:q} \
            --ignore-read-groups >> {log:q} 2>&1
          whatshap_status=$?
          set -e

          python - "$filter_vcf" "$phase_region" "$ps_file" "$ps_status" <<'PY'
import sys
from collections import Counter
from pathlib import Path

import vcfpy

vcf_path, region, ps_path, status_path = sys.argv[1:5]


def write_status(status, phase_set, reason):
    Path(ps_path).write_text(phase_set + "\n", encoding="utf-8")
    Path(status_path).write_text(
        "status\tphase_set\treason\n"
        + f"{{status}}\t{{phase_set}}\t{{reason}}\n",
        encoding="utf-8",
    )


reader = vcfpy.Reader.from_path(vcf_path)
phasesets = []
try:
    records = reader.fetch(region)
except ValueError as exc:
    if "not found in index" in str(exc):
        write_status(
            "no_call_no_phase_set",
            "NO_PHASE_SET",
            f"No HapSMA PhaseSet was detected within {{region}}; {{exc}}",
        )
        sys.exit(0)
    raise

for record in records:
    if record.calls:
        ps = record.calls[0].data.get("PS")
        if ps:
            phasesets.append(str(ps))
if not phasesets:
    write_status(
        "no_call_no_phase_set",
        "NO_PHASE_SET",
        f"No HapSMA PhaseSet was detected within {{region}}",
    )
    sys.exit(0)
counts = Counter(phasesets)
phase_set, count = counts.most_common(1)[0]
if len(counts) > 1 and count / sum(counts.values()) <= 0.65:
    write_status(
        "no_call_no_dominant_phase_set",
        "NO_DOMINANT_PHASE_SET",
        f"No dominant HapSMA PhaseSet in {{region}}: {{dict(counts)}}",
    )
    sys.exit(0)
write_status(
    "phased",
    phase_set,
    f"dominant_phase_set={{phase_set}};count={{count}};total={{sum(counts.values())}}",
)
PY
          local phase_set
          phase_set=$(cat "$ps_file")
          local phase_status
          phase_status=$(awk -F '\t' 'NR == 2 {{print $1}}' "$ps_status")
          if [[ "$phase_status" != "phased" ]]; then
            echo "HapSMA $approach no-call: $(awk -F '\t' 'NR == 2 {{print $3}}' "$ps_status"); whatshap_exit=$whatshap_status" >> {log:q}
            return 0
          fi
          if [[ "$whatshap_status" -ne 0 ]]; then
            echo "whatshap haplotag failed for phased HapSMA $approach approach: exit $whatshap_status" >> {log:q}
            return "$whatshap_status"
          fi
          test -s "$tagged_bam" || (echo "whatshap haplotag did not produce $tagged_bam" >> {log:q}; return 1)
          samtools index -@ {threads} "$tagged_bam" >> {log:q} 2>&1

          for hp in $(seq 1 {params.ploidy:q}); do
            local hap_bam="$outdir/bam/{wildcards.sample}.${{approach}}.hap${{hp}}.ps${{phase_set}}.bam"
            sambamba view -t {threads} -f bam \
              -F "[HP] == $hp and [PS] == $phase_set" \
              -o "$hap_bam" \
              "$tagged_bam" >> {log:q} 2>&1
            sambamba index -t {threads} "$hap_bam" "$hap_bam.bai" >> {log:q} 2>&1

            local clair_dir="$outdir/clair3/hap${{hp}}"
            mkdir -p "$clair_dir"
            run_clair3.sh \
              --bam_fn="$hap_bam" \
              --ref_fn={params.reference:q} \
              --output="$clair_dir" \
              --model_path="$clair3_model" \
              --sample_name="{wildcards.sample}.${{approach}}.hap${{hp}}" \
              --threads={threads} \
              {params.clair3_optional} >> {log:q} 2>&1
            if [[ -s "$clair_dir/merge_output.vcf.gz" ]]; then
              mv "$clair_dir/merge_output.vcf.gz" "$outdir/clair3/{wildcards.sample}.${{approach}}.hap${{hp}}.clair3.vcf.gz"
              if [[ -s "$clair_dir/merge_output.vcf.gz.tbi" ]]; then
                mv "$clair_dir/merge_output.vcf.gz.tbi" "$outdir/clair3/{wildcards.sample}.${{approach}}.hap${{hp}}.clair3.vcf.gz.tbi"
              else
                tabix -f -p vcf "$outdir/clair3/{wildcards.sample}.${{approach}}.hap${{hp}}.clair3.vcf.gz" >> {log:q} 2>&1
              fi
            else
              echo "Clair3 did not produce merge_output.vcf.gz for $approach hap$hp" >> {log:q}
              exit 1
            fi

            sniffles \
              -i "$hap_bam" \
              -v "$outdir/sniffles/{wildcards.sample}.${{approach}}.hap${{hp}}.sniffles.vcf" \
              --threads={threads} >> {log:q} 2>&1
          done
        }}

        run_approach "bed" {params.calling_target_bed:q} {params.phaseset_region:q}
        run_approach "region" {params.calling_target_region:q} {params.phaseset_region:q}

        python - <<'PY'
from pathlib import Path

results = Path("{output.results_dir}")
mean_cov = (results / "smn_region.mean_coverage.txt").read_text().strip()
bed_ps = (results / "bed" / "{wildcards.sample}.bed.phaseset.txt").read_text().strip()
region_ps = (results / "region" / "{wildcards.sample}.region.phaseset.txt").read_text().strip()


def read_status(path):
    rows = path.read_text(encoding="utf-8").strip().splitlines()
    if len(rows) < 2:
        return "missing_phase_status", "", f"Missing HapSMA phase status file: {{path}}"
    fields = rows[1].split("\t")
    while len(fields) < 3:
        fields.append("")
    return fields[0], fields[1], fields[2]


bed_status, _, bed_reason = read_status(
    results / "bed" / "{wildcards.sample}.bed.phaseset.status.tsv"
)
region_status, _, region_reason = read_status(
    results / "region" / "{wildcards.sample}.region.phaseset.status.tsv"
)
rows = [
    "sample\taligner\tdeduper\tcaller\tcaller_class\tdev_status\tevidence_source\tploidy\tsmn_region\tmean_smn_region_coverage\tbed_phase_set\tbed_phase_status\tbed_phase_reason\tregion_phase_set\tregion_phase_status\tregion_phase_reason\toutput_dir",
    "{wildcards.sample}\t{wildcards.alnr}\t{wildcards.ddup}\thapsma\tlong_read_haplotype\tdev_exploratory\tONT_long_read_cram\t{params.ploidy}\t{params.smn_region}\t"
    + mean_cov
    + "\t"
    + bed_ps
    + "\t"
    + bed_status
    + "\t"
    + bed_reason
    + "\t"
    + region_ps
    + "\t"
    + region_status
    + "\t"
    + region_reason
    + "\t{output.results_dir}",
]
Path("{output.summary}").write_text("\n".join(rows) + "\n", encoding="utf-8")
PY
        test -s {output.summary:q}
        touch {output.done:q}
        """


localrules: produce_hapsma

rule produce_hapsma:  # TARGET : Produce native HapSMA exploratory ONT SMN results
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
            sample=SSAMPS,
            alnr=smn_long_read_aligners(),
            ddup=DDUP,
        )
    output:
        "./logs/hapsma.done"
    log:
        "./logs/produce_hapsma.log"
    benchmark:
        "./logs/benchmarks/produce_hapsma.bench.tsv"
    shell:
        "touch {output}"
