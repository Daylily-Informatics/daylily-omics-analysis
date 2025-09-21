# Running Analysis on an Ephemeral Cluster

This guide walks through the first end-to-end analysis after you have created an ephemeral Daylily cluster.  It covers connecting to the head node, preparing an analysis directory on the FSx volume, running a local smoke test, and scaling out to the Slurm-backed workflow.  The instructions assume you followed the provisioning steps in [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster) and now have a running cluster.

## 1. Connect to the Head Node

From your workstation run:

```bash
ssh -i PATH_TO_PEM ubuntu@CLUSTER_IP
# Guard your session in case the network drops.
tmux new -s first_analysis
```

The cluster repository also ships helper targets (`make ssh`, `make ssh-ssm`, etc.) if you prefer not to manage the SSH parameters manually.  Inside the tmux session you should already be the `ubuntu` user.

## 2. Prepare the Analysis Directory

The Daylily CLI is pre-installed on the head node.  Start by moving to the shared FSx filesystem and either clone the repository manually or use the `day-clone` helper (installed when `. dyinit` has been sourced once).

### Option A: Manual clone

```bash
cd /fsx/analysis_results/ubuntu
mkdir -p first_analysis
cd first_analysis

git clone https://github.com/Daylily-Informatics/daylily-omics-analysis.git
cd daylily-omics-analysis
```

### Option B: `day-clone`

```bash
# `day-clone` is placed on your PATH when the Daylily CLI is initialised
# Create a new analysis directory named `first_analysis`
day-clone -d first_analysis

bash
cd /fsx/analysis_results/ubuntu/first_analysis/daylily-omics-analysis
```

Whichever route you take, the remainder of the guide assumes you are inside the repository root on the head node.

## 3. Initialise the CLI

```bash
bash            # start a fresh shell when attaching to tmux
. dyinit        # configures the DAYOA conda env and helper commands
```

If `. dyinit` succeeds you should see a magenta `WORKFLOW SUCCESS` banner.  The command also installs the `day-clone` helper under `~/miniconda3/condabin/` for future sessions.

## 4. Run a Local Smoke Test

Use the 0.01× HG002 dataset to validate the environment before scheduling Slurm jobs.

```bash
# Local profile targets the head node directly
dy-a local hg38

# Stage the toy manifest
cp .test_data/data/0.01xwgs_HG002_hg38.samplesheet.csv config/analysis_manifest.csv

# Inspect the manifest if you are curious
head -n 2 config/analysis_manifest.csv

# Dry-run and then execute the workflow
dy-r seqqc -j 1 -p -k -n
dy-r seqqc -j 1 -p -k

find results/
```

Results land in `results/day/hg38/` and logs in `logs/`.  If you see the `WORKFLOW SUCCESS` banner, the environment is ready for larger runs.

## 5. Run the Same Workflow on Slurm

Switch to the Slurm profile and repeat the workflow.  Spot instances may take a few minutes to join the cluster when it is cold; monitor with `sinfo` and `squeue`.

```bash
dy-a slurm hg38

# Clean up any prior run artefacts
rm -rf results .snakemake logs

# Reuse the manifest and execute via Slurm
dy-r seqqc -j 3 -p -k -n
dy-r seqqc -j 3 -p -k

watch 'squeue -o "%.18i %.9P %.30j %.8u %.2t %.10M %.6D %R"'
```

When jobs finish you can browse results as before.  Logs for Slurm-submitted tasks are stored under `logs/slurm/`.

## 6. Run Concordance Workloads with GIAB Data

Seven 30× Illumina GIAB samples are staged in the Daylily reference bucket.  The manifests in `.test_data/data/` reference these datasets and truth sets.

### HG38 concordance example

```bash
. dyinit
dy-a slurm hg38

cp .test_data/data/giab_30x_hg38_analysis_manifest.csv config/analysis_manifest.csv

# plan the run
dy-r produce_snv_concordances -p -k -j 9 -n

# execute
dy-r produce_snv_concordances -p -k -j 9

ls results/day/hg38/other_reports/*giab*
```

### B37 concordance example

```bash
. dyinit
dy-a slurm b37

cp .test_data/data/giab_30x_b37_analysis_manifest.csv config/analysis_manifest.csv

dy-r produce_snv_concordances -p -k -j 9 -n
dy-r produce_snv_concordances -p -k -j 9

ls results/day/b37/other_reports/*giab*
```

Adjust `aligners`, `dedupers`, `snv_callers`, and `sv_callers` via the `--config` flag or by editing `config/day_profiles/<profile>/rule_config.yaml` before running the workflows.

## 7. Crafting Your Own Analysis Manifest

1. Stage your FASTQ files under `/fsx/data/tmp_input_sample_data/` (they originate from the regional Daylily S3 bucket).
2. Create a `fastq_manifest.tsv` describing each sample:

   ```text
   sample_id   fastq1_fsx_path  fastq2_fsx_path  expected_copies_x  expected_copies_y
   HG001-30x   /fsx/data/tmp_input_sample_data/HG001_R1.fastq.gz  /fsx/data/tmp_input_sample_data/HG001_R2.fastq.gz  2 0
   ```

3. Generate `config/analysis_manifest.csv` using the helper script:

   ```bash
   python bin/daylily-analysis-samples-to-manifest-new.py fastq_manifest.tsv config
   ```

   The helper writes `analysis_manifest.csv` into the target directory (for example `config/`).  Ensure `AWS_PROFILE` points to the credentials used to stage your data before running the script.

4. Run the desired workflow(s) with `dy-r` as demonstrated above.

The manifest format is evolving, but the helper keeps you aligned with the expected schema.

## 8. Monitoring and Cost Awareness

* `sinfo` and `squeue` surface Slurm queue status; wrap them in `watch` for continuous updates.
* CloudWatch dashboards provisioned by the cluster repository track spend and utilisation in real time.
* Use `bin/calc_daylily_aws_cost_estimates.py` and `bin/estimate-daylily-ephemeral-compute-cost.py` to generate cost projections for planned runs.

## 9. Export Results Before Teardown

Ephemeral clusters delete the FSx filesystem on destroy.  Export analysis outputs back to the Daylily S3 bucket via the FSx console or AWS CLI (`create-data-repository-task`) before deleting the cluster.

With these steps complete you have a reproducible baseline for Daylily analyses and can iterate on additional pipelines or integrate the workflows into larger benchmarking campaigns.
