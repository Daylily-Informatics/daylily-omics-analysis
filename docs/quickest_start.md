# Quickest Start

_Use this checklist when you want the fastest path from a fresh AWS account to running a Daylily WGS workflow._

Daylily is now delivered as two coordinated repositories:

* [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster) provisions the transient AWS ParallelCluster environment (networking, FSx, Slurm, PCUI, etc.).
* `daylily-omics-analysis` (this repository) contains the Snakemake workflows, manifests, and CLI helpers that run on that infrastructure.

The steps below link the two pieces together.  Follow them in order and you will have a working smoke-test analysis in under an hour.

## 0. Prerequisites

* An AWS account with permissions to create IAM users, VPC resources, ParallelCluster, FSx, and S3 buckets.
* The AWS CLI configured on the workstation that will create the cluster.
* A Unix-like shell with `git`, `ssh`, and `conda` available.

## 1. Bootstrap the Ephemeral Cluster

All cluster automation now lives in [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster).  Work through the "Quick Start" and "Install" sections in that repository to:

1. Create the `daylily-service` IAM user and credentials.
2. Stage the regional Daylily reference bucket (one per region where you intend to run analyses).
3. Launch an ephemeral cluster using the provided `make` targets or helper scripts.
4. (Optional) Deploy the PCUI dashboard for one-click access to cluster consoles.

When the cluster build completes you will have a head node with the Daylily CLI pre-installed and an FSx Lustre filesystem mounted at `/fsx`.

## 2. Connect to the Head Node

From your workstation (or via the PCUI shell), connect to the head node.  Replace `PATH_TO_PEM` and `CLUSTER_IP` with the values reported by the cluster build process.

```bash
ssh -i PATH_TO_PEM ubuntu@CLUSTER_IP
# Always start a tmux session to guard against network hiccups.
tmux new -s daylily
```

The cluster repository also provides helper scripts (`make ssh`, `make ssh-ssm`, etc.) if you prefer not to manage SSH parameters manually.

## 3. Clone the Analysis Repository

On the head node, clone the Daylily Omics Analysis repository into your working directory on the FSx volume:

```bash
cd /fsx/analysis_results/ubuntu
mkdir -p first_analysis
cd first_analysis

git clone https://github.com/Daylily-Informatics/daylily-omics-analysis.git
cd daylily-omics-analysis
```

(If you have activated the Daylily CLI with `. dyinit`, the `day-clone` helper can automate these steps for you.)

## 4. Run the Smoke Test

Inside the repository:

```bash
bash
. dyinit

# local execution profile targets the head node
dy-a local hg38

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

dy-r seqqc -j 1 -p -k -n   # dry-run

dy-r seqqc -j 1 -p -k      # execute
```

The results land in `results/day/hg38/` and logs in `logs/`.  When ready to scale out, switch to the Slurm profile and re-run the workflow:

```bash
dy-a slurm hg38
dy-r produce_snv_concordances -p -k -j 6 --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep']
```

## 5. Next Steps

* Explore [`docs/first_ephemeral_cluster_analysis.md`](docs/first_ephemeral_cluster_analysis.md) for a more in-depth walkthrough, including GIAB concordance runs and manifest creation.
* Review the workflow catalogue under [`workflow/rules/`](../workflow/rules) to enable additional tools (DeepVariant, Octopus, Clair3, Manta, Tiddit, etc.).
* Export results back to S3 using the FSx data export tasks described in the cluster repository before tearing the cluster down.

With these steps complete you can iterate on analysis profiles, add your own manifests, or integrate the workflows into automated benchmarking studies.
