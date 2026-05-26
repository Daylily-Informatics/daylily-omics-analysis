> **Historical design note.** This file captures an earlier RTG concordance refactor discussion. Verify implementation details against `workflow/rules/rtg_vcfeval.smk` and current tests before using it as guidance.

You’re right: this is “old bash grown around a pipeline” code. The slowness and gnarliness are mostly structural, not algorithmic.

What’s actually being used right now

In the Snakemake you attached, the rule builds fin_cmd like this:

env python workflow/scripts/parse-vcfeval-summary.py ...

So parse-vcfeval-summary.py is the one actually referenced. The parse-vcfeval-summary.new.py file is currently dead code unless something else calls it. (Also: the .new.py adds columns like MCC/Fbeta etc, so it would change output anyway.)

Why this is slow + hard to maintain (the real culprits)
1) One Snakemake job hides N ROI jobs

Inside prep_for_concordance_check you’re doing:

enumerate truth ROI subdirs with ls -d truth/*

build a pile of commands into a .fofn

cat fofn | bash

with GNU parallel forced to --jobs 1, so serial.

That means Snakemake cannot schedule each ROI as its own job. You lose:

parallelism across ROI footprints

per-ROI logging/benchmarking

correct failure semantics (one ROI failing shouldn’t silently “touch done”)

2) Output tracking is basically fake

The “real” outputs (per-ROI snv_{sample}_{cmpfootprint}_concordance.mqc.tsv) are not declared as Snakemake outputs at all. The rule always ends with touch {output} (the .done sentinel), even if vcfeval/parse failed earlier (and set +euo pipefail ensures it’ll keep going).

 

So the pipeline can look “complete” while producing partial/missing concordance data.

3) Side effects in input functions

get_in_rtg_vcf() and get_in_rtg_tbi() do os.system("ln -s ...") and sleep 2.

 

That’s a maintainability nightmare:

it breaks Snakemake’s DAG purity assumptions

it produces race conditions under parallel scheduling

it makes reruns non-deterministic

4) The Python script is a glue bomb

parse-vcfeval-summary.py does all of this in one run:

parse summary.txt

compute bed size via cat|awk

run bcftools annotate 3 times + tabix 3 times

run another Python script 3 times

parse the count files

write the MQC TSV

run perl -pi to patch the header

And it uses os.cpu_count() // 4 for bcftools threads, which can oversubscribe on shared nodes or under Snakemake thread limits (often a hidden slowdown).

 

There are also a couple of “this is probably not doing what you think” issues:

the mean depth calculation is commented out in the Snakefile, so AllVarMeanDP is basically always -1 and CovBin=-2 in practice.

the output filename passed as sys.argv[6] in the Snakefile uses $subdb_summary which is almost certainly a bash variable-name bug (greedy expansion): it likely expands to empty and you get ALTID_.txt. It “works” only because each ROI has its own directory.

One refactor path I’d actually endorse (big wins, minimal risk)
Goal

Keep bitwise identical per-ROI MQC TSV outputs (and the aggregate), but make the system:

schedulable (ROI-level jobs)

testable

extensible (configurable SNP classes later)

faster (parallelism + remove oversubscription + optional optimizations)

Phase 1: Fix the Snakemake structure (largest speed + maintainability gain)
A) Discover ROI footprints explicitly (checkpoint or scan)

Because truth directories can have 0..many subdirs per sample, use a checkpoint so the DAG can expand after discovery.

 

Checkpoint: discover footprints

input: truthset directory for sample (from sample sheet)

output: a footprints.txt containing one ROI subdir per line (sorted)

Pseudo-Snakemake:

checkpoint discover_footprints:
    input:
        tdir=lambda wc: samples.loc[samples.sample==wc.sample, "CONCORDANCE_CONTROL_PATH"].iloc[0]
    output:
        rois=MDIR + "{sample}/concordance/footprints.txt"
    run:
        import os
        tdir = input.tdir
        rois = []
        if tdir and os.path.isdir(tdir):
            rois = sorted([d for d in os.listdir(tdir) if os.path.isdir(os.path.join(tdir, d))])
        os.makedirs(os.path.dirname(output.rois), exist_ok=True)
        with open(output.rois, "w") as f:
            for r in rois:
                f.write(r + "\n")

If concordance not requested or tdir missing: write an empty file. That’s your “0 ROI” case handled cleanly.

B) One rule per ROI: rtg_vcfeval_roi

Make the ROI (cmpFootprint) a wildcard, and make the rtg output directory explicit.

 

Outputs to track:

{conc_dir}/_{footprint}/summary.txt (or a .done inside that dir)

Per-ROI logs/bench:

rule rtg_vcfeval_roi:
    input:
        call_vcf=get_in_rtg_vcf,   # but remove side effects in Phase 1.5, see below
        call_tbi=get_in_rtg_tbi,
        truth_vcf=lambda wc: f"{get_samp_concordance_truth_dir(wc)}/{wc.footprint}/{get_alt_sample_name(wc)}.vcf.gz",
        truth_tbi=lambda wc: f"{get_samp_concordance_truth_dir(wc)}/{wc.footprint}/{get_alt_sample_name(wc)}.vcf.gz.tbi",
        bed=lambda wc: f"{get_samp_concordance_truth_dir(wc)}/{wc.footprint}/{get_alt_sample_name(wc)}.bed",
    output:
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{footprint}/summary.txt",
    threads: config["rtg_vcfeval"]["sub_threads"]
    conda: config["rtg_vcfeval"]["env_yaml"]
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/logs/{sample}.{alnr}.{ddup}.{snv}.{footprint}.rtg.log"
    shell:
        r"""
        set -euo pipefail
        outdir=$(dirname {output.summary})
        rm -rf "$outdir"
        mkdir -p "$outdir"
        rtg vcfeval --decompose --squash-ploidy --ref-overlap \
            -e {input.bed} \
            -b {input.truth_vcf} \
            -c {input.call_vcf} \
            -o "$outdir" \
            -t {config[supporting_files][files][huref][rtg_tools_genome][name]} \
            --threads {threads} \
            > {log} 2>&1
        """

Now Snakemake can parallelize ROI jobs across CPU and cluster nodes.

C) One rule per ROI: vcfeval_report_roi

This calls your existing parse-vcfeval-summary.py unchanged initially, but makes outputs explicit:

the per-ROI MQC TSV: snv_{sample}_{footprint}_concordance.mqc.tsv

(optionally) the legacy “parsed summary” file *.txt that the script writes as argv[6]

rule vcfeval_report_roi:
    input:
        summary=rules.rtg_vcfeval_roi.output.summary,
        bed=lambda wc: f"{get_samp_concordance_truth_dir(wc)}/{wc.footprint}/{get_alt_sample_name(wc)}.bed",
    output:
        mqc=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{footprint}/snv_{sample}_{footprint}_concordance.mqc.tsv",
        legacy=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{footprint}/legacy_summary.txt",
    threads: 2
    conda: config["rtg_vcfeval"]["env_yaml"]
    params:
        alt_id=get_alt_sample_name,
        # cluster_sample currently passed as {params.cluster_sample} in old code
        # If that is actually different from sample, keep it. Otherwise, just use wc.sample.
        cluster_sample=get_samp_name,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/logs/{sample}.{alnr}.{ddup}.{snv}.{footprint}.report.log"
    shell:
        r"""
        set -euo pipefail
        python workflow/scripts/parse-vcfeval-summary.py \
            {input.summary} \
            {params.cluster_sample} \
            {input.bed} \
            {wildcards.footprint} \
            {params.alt_id} \
            {output.legacy} \
            na \
            {wildcards.alnr} \
            {wildcards.snv} \
            > {log} 2>&1

        # parse script writes the mqc file itself; enforce it exists where we expect
        test -s {output.mqc}
        """

Note: we pass na for mean depth because that’s what your Snakefile effectively does right now.

D) Sample-level sentinel: concordance.done

Now make the .done depend on all per-ROI MQC outputs discovered by the checkpoint:

def roi_list(wc):
    ck = checkpoints.discover_footprints.get(sample=wc.sample)
    with open(ck.output.rois) as f:
        return [l.strip() for l in f if l.strip()]

def mqc_inputs(wc):
    rois = roi_list(wc)
    return expand(
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/_{footprint}/snv_{sample}_{footprint}_concordance.mqc.tsv",
        sample=wc.sample, alnr=wc.alnr, ddup=wc.ddup, snv=wc.snv, footprint=rois
    )

rule concordance_done:
    input: mqc_inputs
    output:
        touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/concordance/concordance.done")
    shell:
        "touch {output}"

For “0 ROI” samples, mqc_inputs returns [], and Snakemake will just touch concordance.done quickly.

 

This keeps your current high-level semantics but stops lying about completion.

E) Aggregation rule: stop using find | perl for logic

You can keep the exact same output, but implement it in a small Python aggregator so it’s deterministic and testable.

 

Your current aggregation does:

take header from first .mqc.tsv

append all other rows (skip headers)

reorder columns with perl

rewrite mqc_id to include VariantClass when subset None

All of that is straightforward in pandas or csv module.

 

Even if you don’t change it now, the per-ROI refactor makes the “find” step stable because all expected outputs are now tracked and exist.

Phase 1.5: Kill the side effects in input functions (necessary for correctness)

Replace the DRAGEN symlink hack with an explicit rule, so “the existence of the input VCF at path X” is an output produced by Snakemake, not an input function side effect.

 

Example:

rule normalize_call_vcf:
    input:
        src=lambda wc: get_raw_R1s(wc)[0]  # whatever this really is
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz.tbi",
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.vcf})
        ln -sf {input.src} {output.vcf}
        ln -sf {input.src}.tbi {output.tbi}
        """

Then rtg_vcfeval_roi uses those as inputs.

 

This is a massive “future you will thank you” change.

Phase 2: Refactor the Python report generator without changing output

You can keep the same output but make the code sane by doing pure refactors first:

Changes that should not change output (but improve maintainability)

Wrap in main() + argparse, no top-level side effects.

Replace os.system with subprocess.run(..., check=True) so failures are real failures.

Replace cat bed | awk with a Python bed-length function.

Replace perl -pi 's/^\t/VariantClass\t/' with to_csv(index_label="VariantClass") (same bytes on that line).

Stop using os.cpu_count()//4 and accept --threads (default 1). In Snakemake, pass {threads}.

Split into functions:

parse_rtg_summary(summary_path) -> tp/fp/fn/fscore/...

run_strip_and_classify(tp/fp/fn vcfs) -> count dicts

build_mqc_dataframe(counts, tgt_region_size, metadata) -> df

write_outputs(df, out_mqc)

Changes that likely speed things up (but you must validate output)

Stop writing “stripped VCFs” if classification doesn’t depend on INFO fields.

Right now you do 3x bcftools annotate + 3x tabix.

If classify_var_by_type_size.py only uses REF/ALT/TYPE/LEN, those INFO drops are irrelevant.

Validation path: run classification on original vs stripped once and diff *.count. If identical, delete _proc_vcf() entirely.

If you keep stripping, cache it:

if stripped exists and is newer than input, skip re-strip.

If classify_var_by_type_size.py is simple, fold it into this script (see Phase 3).

A note on reproducibility

Right now, this script’s numeric formatting is “whatever pandas decides”. If you change dtypes you can accidentally change formatting (e.g., 1 vs 1.0). To keep output identical, be careful:

don’t change numeric types unless you lock formatting (float_format=...)

preserve row order explicitly (your current order comes from dict insertion order)

Phase 3: Make SNP classes configurable (without turning the pipeline into spaghetti)

This is the part you asked for (“cool if classes configurable”), and it’s also where you can remove the extra script + bcftools calls and get real speedups.

Recommended design

Create a small YAML that defines classes as predicates on a normalized variant representation.

Example config (default reproduces current behavior):

classes:
  - name: SNPts
    type: snp
    snp_kind: transition
  - name: SNPtv
    type: snp
    snp_kind: transversion
  - name: INS_50
    type: ins
    size_max: 50
  - name: INS_gt50
    type: ins
    size_min: 51
  - name: DEL_50
    type: del
    size_max: 50
  - name: DEL_gt50
    type: del
    size_min: 51
  - name: Indel_50
    type: indel
    size_max: 50
  - name: Indel_gt50
    type: indel
    size_min: 51

Then your report script:

reads tp.vcf.gz/fp.vcf.gz/fn.vcf.gz directly via pysam.VariantFile

for each record, emits one or more “events” (for multiallelic, count each ALT)

classifies each event through the config predicates

produces counts identical to your current .count outputs (once validated)

builds the same MQC TSV

This removes:

bcftools annotate

tabix on stripped files

classify_var_by_type_size.py as a separate process

…and gives you a clean hook for adding new classes later.

“Standardized concordance reports”

Once you’re counting classes in-process, add outputs that are actually nice to consume:

 

Per ROI directory:

report.mqc.tsv (legacy exact output)

report.json (machine-readable schema)

report.parquet (optional, for fast meta analysis)

inputs.json (paths + tool versions + parameters, for provenance)

Workflow-level:

concordance_manifest.tsv with one row per ROI output, plus run metadata (aligner, caller, pipeline git SHA, ref build, truthset id)

None of this requires hap.py. It just makes your RTG-based evaluation “productized”.

Specific “gotchas” I would fix during refactor

The skip logic is wrong: you check length of {params.conc_dir} (always long). You meant {params.tdir} or existence of truth dir.

That $subdb_summary variable expansion is almost certainly a bug; fix by using braces: ${subd}b_summary.txt if you actually want subd in the filename.

Stop using set +euo pipefail for the main logic. If you truly need “best effort”, do it explicitly:

per ROI: on missing truth files, emit a SKIPPED.json and a tiny MQC TSV with NA metrics (or skip ROI entirely)

but don’t pretend success by touching .done unconditionally

Thread control: stop os.cpu_count() inside jobs. Always respect Snakemake threads.

Do this next:

Snapshot the current outputs as golden references for 2–3 representative samples:

one with 0 truth ROI dirs

one with 1 ROI dir

one with multiple ROI dirs
Save:

per-ROI snv_*_concordance.mqc.tsv

your aggregated other_reports/giab_concordance_mqc.tsv

Refactor Snakemake first using the checkpoint + per-ROI rules approach above.

Keep parse-vcfeval-summary.py unchanged initially.

Make the per-ROI MQC file an explicit Snakemake output.

Remove the side-effectful input functions by introducing an explicit “normalize/symlink call VCF” rule if you still need the DRAGEN mode.

Once outputs match exactly, refactor parse-vcfeval-summary.py internally (argparse + functions + subprocess + index_label) with a byte-for-byte output diff test.

Only then tackle configurable classes by folding classification into the report script behind a default config that reproduces current class counts.
