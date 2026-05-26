#!/usr/bin/env python3
"""Create downsampled FASTQ/BAM/CRAM files from a solo pipeline sample table.

Reads a TSV with columns:
  pipeline_name, giab_id, day_id, aligned_cov, R1fq, R2fq, inBAM, inCRAM

For each sample, creates downsampled copies at target coverages using:
  - seqkit sample  (paired FASTQ)
  - samtools view -s  (BAM or CRAM)

Usage:
  python create_downsampled_datasets.py \\
      --table solo_pipeline_samples.tsv \\
      --outdir /fsx/control_data/downsampled \\
      [--targets 0.1,0.5,1,1.5,3,5,10,15,20,30,40,50] \\
      [--reference /path/to/ref.fasta] \\
      [--threads 8] [--seed 42] [--dry-run]
"""
import argparse
import csv
import os
import subprocess
import sys
from pathlib import Path

TARGET_COVERAGES_DEFAULT = [0.1, 0.5, 1.0, 1.5, 3.0, 5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 50.0]
SEED = 42


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--table", required=True, help="Path to solo_pipeline_samples.tsv")
    p.add_argument("--outdir", required=True, help="Root output directory for downsampled files")
    p.add_argument("--targets", default=None,
                   help="Comma-separated target coverages (default: 0.1,0.5,1,1.5,3,5,10,15,20,30,40,50)")
    p.add_argument("--reference", default=None,
                   help="Reference FASTA (required for CRAM input; also used for BAM→CRAM if desired)")
    p.add_argument("--threads", type=int, default=8, help="Threads for samtools/seqkit (default: 8)")
    p.add_argument("--seed", type=int, default=SEED, help="Random seed (default: 42)")
    p.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    p.add_argument("--samples", default=None,
                   help="Comma-separated day_id values to process (default: all)")
    p.add_argument("--slurm", action="store_true", help="Generate and submit Slurm jobs instead of running directly")
    p.add_argument("--slurm-partition", default="i192mem", help="Slurm partition (default: i192mem)")
    p.add_argument("--slurm-comment", default="RandD", help="Slurm job comment (default: RandD)")
    p.add_argument("--conda-env", default="DOWNSAMPLE", help="Conda env to activate in Slurm jobs (default: DOWNSAMPLE)")
    p.add_argument("--job-dir", default="/fsx/scratch/downsample_jobs", help="Directory for job scripts and logs (default: /fsx/scratch/downsample_jobs)")
    return p.parse_args()


def run_cmd(cmd, dry_run=False):
    """Run a shell command, or print it if dry_run."""
    print(f"  CMD: {cmd}", flush=True)
    if dry_run:
        return 0
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        print(f"  ERROR: command returned {result.returncode}", file=sys.stderr)
    return result.returncode


def detect_input_type(row):
    """Return ('fastq', 'bam', or 'cram') and the relevant file path(s)."""
    r1 = (row.get("R1fq") or "").strip()
    r2 = (row.get("R2fq") or "").strip()
    bam = (row.get("inBAM") or "").strip()
    cram = (row.get("inCRAM") or "").strip()

    if r1 and r1.lower() not in ("", "na", "tbd"):
        return "fastq", (r1, r2 if r2 and r2.lower() not in ("", "na") else None)
    if bam and bam.lower() not in ("", "na", "tbd"):
        return "bam", bam
    if cram and cram.lower() not in ("", "na", "tbd"):
        return "cram", cram
    return None, None


def downsample_fastq(r1, r2, fraction, out_r1, out_r2, seed, threads, dry_run):
    """Downsample paired FASTQ with seqkit sample (same seed = paired sync)."""
    os.makedirs(os.path.dirname(out_r1), exist_ok=True)
    # seqkit sample with same seed keeps pairs in sync for name-sorted FASTQs
    cmd_r1 = (f"seqkit sample -j {threads} --line-width=0 --quiet "
              f"--rand-seed={seed} --seq-type=dna --proportion={fraction:.10f} "
              f'"{r1}" | pigz -p {threads} > "{out_r1}"')
    run_cmd(cmd_r1, dry_run)
    if r2:
        cmd_r2 = (f"seqkit sample -j {threads} --line-width=0 --quiet "
                  f"--rand-seed={seed} --seq-type=dna --proportion={fraction:.10f} "
                  f'"{r2}" | pigz -p {threads} > "{out_r2}"')
        run_cmd(cmd_r2, dry_run)


def _samtools_subsample_arg(seed, fraction):
    """Format samtools -s SEED.FRAC argument (e.g. 42.0996 for seed=42, p=0.0996)."""
    # samtools expects INT.FRAC where the digits after '.' are the probability
    frac_digits = f"{fraction:.10f}"[2:]  # strip leading "0."
    result = f"{seed}.{frac_digits}".rstrip("0")
    if result.endswith("."):
        result += "0"
    return result


def downsample_bam(bam_path, fraction, out_path, seed, threads, dry_run):
    """Downsample BAM with samtools view -s SEED.FRAC."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    frac_str = _samtools_subsample_arg(seed, fraction)
    cmd = (f'samtools view -@ {threads} -b -s {frac_str} "{bam_path}" '
           f'| samtools sort -@ {threads} -o "{out_path}" && '
           f'samtools index -@ {threads} "{out_path}"')
    run_cmd(cmd, dry_run)


def downsample_cram(cram_path, fraction, out_path, reference, seed, threads, dry_run):
    """Downsample CRAM with samtools view -s SEED.FRAC."""
    if not reference:
        print(f"  ERROR: --reference required for CRAM input: {cram_path}", file=sys.stderr)
        return
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    frac_str = _samtools_subsample_arg(seed, fraction)
    cmd = (f'samtools view -@ {threads} -C -s {frac_str} '
           f'--reference "{reference}" "{cram_path}" '
           f'| samtools sort -@ {threads} --reference "{reference}" '
           f'-O cram -o "{out_path}" && '
           f'samtools index -@ {threads} "{out_path}"')
    run_cmd(cmd, dry_run)


def build_downsample_commands(input_type, input_paths, targets, aligned_cov, outdir, pipeline, giab_id, day_id, reference, seed, threads):
    """Build list of (target_cov, command_string) tuples for a sample."""
    commands = []
    for tgt in targets:
        if tgt >= aligned_cov:
            continue

        fraction = tgt / aligned_cov
        cov_label = f"{tgt}x".replace(".", "p")
        sample_dir = outdir / pipeline / giab_id / day_id / cov_label

        if input_type == "fastq":
            r1, r2 = input_paths
            ext = ".fastq.gz"
            out_r1 = str(sample_dir / f"{giab_id}_{cov_label}_R1{ext}")
            out_r2 = str(sample_dir / f"{giab_id}_{cov_label}_R2{ext}") if r2 else None

            cmd_r1 = (f"mkdir -p {sample_dir} && "
                      f"seqkit sample -j {threads} --line-width=0 --quiet "
                      f"--rand-seed={seed} --seq-type=dna --proportion={fraction:.10f} "
                      f'"{r1}" | pigz -p {threads} > "{out_r1}"')
            if r2:
                cmd_r2 = (f"seqkit sample -j {threads} --line-width=0 --quiet "
                          f"--rand-seed={seed} --seq-type=dna --proportion={fraction:.10f} "
                          f'"{r2}" | pigz -p {threads} > "{out_r2}"')
                cmd = f"{cmd_r1} && {cmd_r2}"
            else:
                cmd = cmd_r1
            commands.append((tgt, cmd))

        elif input_type == "bam":
            out_bam = str(sample_dir / f"{giab_id}_{cov_label}.bam")
            frac_str = _samtools_subsample_arg(seed, fraction)
            cmd = (f"mkdir -p {sample_dir} && "
                   f'samtools view -@ {threads} -b -s {frac_str} "{input_paths}" '
                   f'| samtools sort -@ {threads} -o "{out_bam}" && '
                   f'samtools index -@ {threads} "{out_bam}"')
            commands.append((tgt, cmd))

        elif input_type == "cram":
            out_cram = str(sample_dir / f"{giab_id}_{cov_label}.cram")
            frac_str = _samtools_subsample_arg(seed, fraction)
            cmd = (f"mkdir -p {sample_dir} && "
                   f'samtools view -@ {threads} -C -s {frac_str} '
                   f'--reference "{reference}" "{input_paths}" '
                   f'| samtools sort -@ {threads} --reference "{reference}" '
                   f'-O cram -o "{out_cram}" && '
                   f'samtools index -@ {threads} "{out_cram}"')
            commands.append((tgt, cmd))

    return commands


def generate_slurm_script(day_id, pipeline, giab_id, commands, args):
    """Generate a Slurm job script for a single sample."""
    job_name = f"downsample_{pipeline}_{giab_id}_{day_id}"
    script_path = Path(args.job_dir) / f"{job_name}.sh"
    log_path = Path(args.job_dir) / "logs" / f"{job_name}_%j.out"

    script_content = f"""#!/bin/bash
#SBATCH --comment {args.slurm_comment}
#SBATCH --partition {args.slurm_partition}
#SBATCH --cpus-per-task={args.threads}
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --job-name={job_name}
#SBATCH --output={log_path}
#SBATCH --error={log_path}

set -euo pipefail

echo "=== Downsampling {pipeline}/{giab_id}/{day_id} ==="
echo "Start: $(date)"
echo "Host: $(hostname)"
echo ""

# Activate conda environment
source /home/ubuntu/miniconda3/bin/activate {args.conda_env}

# Run downsampling commands
"""

    for tgt, cmd in commands:
        script_content += f'\necho "Processing {tgt}x..."\n{cmd}\necho "  {tgt}x complete"\n'

    script_content += f"""
echo ""
echo "End: $(date)"
echo "=== All targets complete for {day_id} ==="
"""

    return script_path, script_content


def main():
    args = parse_args()
    targets = TARGET_COVERAGES_DEFAULT
    if args.targets:
        targets = sorted(float(x) for x in args.targets.split(","))

    filter_ids = None
    if args.samples:
        filter_ids = set(s.strip() for s in args.samples.split(","))

    # Track processed (pipeline, day_id) pairs to handle duplicate day_ids across pipelines
    processed_pairs = set()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    with open(args.table, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        rows = [r for r in reader]

    print(f"Loaded {len(rows)} rows from {args.table}")
    print(f"Target coverages: {targets}")
    if args.slurm:
        print(f"*** SLURM MODE — generating job scripts in {args.job_dir} ***")
        Path(args.job_dir).mkdir(parents=True, exist_ok=True)
        (Path(args.job_dir) / "logs").mkdir(parents=True, exist_ok=True)
    if args.dry_run:
        print("*** DRY RUN — no files will be created ***")
    print()

    skipped = 0
    processed = 0
    jobs_submitted = 0

    for row in rows:
        day_id = row["day_id"].strip()
        pipeline = row["pipeline_name"].strip()
        giab_id = row["giab_id"].strip()
        aligned_cov_str = row["aligned_cov"].strip()

        # Skip if already processed this (pipeline, day_id) pair
        pair_key = (pipeline, day_id)
        if pair_key in processed_pairs:
            continue
        processed_pairs.add(pair_key)

        if filter_ids and day_id not in filter_ids:
            continue

        if aligned_cov_str.upper() in ("TBD", "", "NA"):
            print(f"SKIP {pipeline}/{giab_id} ({day_id}): aligned_cov={aligned_cov_str}")
            skipped += 1
            continue

        aligned_cov = float(aligned_cov_str)
        input_type, input_paths = detect_input_type(row)

        if input_type is None:
            print(f"SKIP {pipeline}/{giab_id} ({day_id}): no input file found")
            skipped += 1
            continue

        print(f"=== {pipeline} / {giab_id} / {day_id} === aligned_cov={aligned_cov}x  type={input_type}")

        if args.slurm:
            # Build all commands for this sample
            commands = build_downsample_commands(
                input_type, input_paths, targets, aligned_cov, outdir,
                pipeline, giab_id, day_id, args.reference, args.seed, args.threads
            )

            if not commands:
                print(f"  No valid targets (all >= {aligned_cov}x)")
                continue

            # Generate job script
            script_path, script_content = generate_slurm_script(day_id, pipeline, giab_id, commands, args)

            print(f"  Writing job script: {script_path}")
            with open(script_path, "w") as f:
                f.write(script_content)
            os.chmod(script_path, 0o755)

            # Submit job
            if not args.dry_run:
                submit_cmd = f"/opt/slurm/bin/sbatch {script_path}"
                print(f"  Submitting: {submit_cmd}")
                result = subprocess.run(submit_cmd, shell=True, capture_output=True, text=True)
                if result.returncode == 0:
                    print(f"  ✓ {result.stdout.strip()}")
                    jobs_submitted += 1
                else:
                    print(f"  ✗ sbatch failed: {result.stderr.strip()}", file=sys.stderr)
            else:
                print(f"  [DRY RUN] Would submit: /opt/slurm/bin/sbatch {script_path}")
                jobs_submitted += 1

            processed += len(commands)

        else:
            # Direct execution mode (original behavior)
            for tgt in targets:
                if tgt >= aligned_cov:
                    print(f"  {tgt}x: SKIP (>= aligned {aligned_cov}x)")
                    continue

                fraction = tgt / aligned_cov
                cov_label = f"{tgt}x".replace(".", "p")
                sample_dir = outdir / pipeline / giab_id / day_id / cov_label

                if input_type == "fastq":
                    r1, r2 = input_paths
                    ext = ".fastq.gz"
                    out_r1 = str(sample_dir / f"{giab_id}_{cov_label}_R1{ext}")
                    out_r2 = str(sample_dir / f"{giab_id}_{cov_label}_R2{ext}") if r2 else None
                    print(f"  {tgt}x: fraction={fraction:.6f} -> {out_r1}")
                    downsample_fastq(r1, r2, fraction, out_r1, out_r2, args.seed, args.threads, args.dry_run)

                elif input_type == "bam":
                    out_bam = str(sample_dir / f"{giab_id}_{cov_label}.bam")
                    print(f"  {tgt}x: fraction={fraction:.6f} -> {out_bam}")
                    downsample_bam(input_paths, fraction, out_bam, args.seed, args.threads, args.dry_run)

                elif input_type == "cram":
                    out_cram = str(sample_dir / f"{giab_id}_{cov_label}.cram")
                    print(f"  {tgt}x: fraction={fraction:.6f} -> {out_cram}")
                    downsample_cram(input_paths, fraction, out_cram, args.reference,
                                    args.seed, args.threads, args.dry_run)

                processed += 1

    print()
    if args.slurm:
        print(f"Done. Generated {jobs_submitted} Slurm jobs, {processed} total downsample operations, skipped {skipped} samples.")
    else:
        print(f"Done. Processed {processed} downsample operations, skipped {skipped} samples.")


if __name__ == "__main__":
    main()

