# Daylily Omics Analysis
_0.7.357_

Daylily Omics Analysis provides the Snakemake-based workflows that power the Daylily whole genome sequencing (WGS) platform.  The pipelines support short-read, long-read and hybrid analyses, deliver concordance and QC reporting, and surface cost telemetry so that analytical performance can be evaluated alongside runtime and spend.  The repository previously lived alongside the infrastructure automation in a monorepo; it now focuses exclusively on analysis.  Cluster lifecycle management is handled by the companion project [daylily-ephemeral-cluster](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster).

> **Beta notice:** tagged releases are the preferred entry point for production use (for example `0.7.336`).  The `main` branch is used for active development and may change without notice.

## Relationship to `daylily-ephemeral-cluster`

This repository does not create or manage compute infrastructure.  To run the workflows at scale you will first need to provision an ephemeral AWS ParallelCluster environment by following the instructions in [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster).  The high level split between the projects is:

| Project | Purpose |
| --- | --- |
| [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster) | Creates and operates the transient AWS infrastructure (VPC, ParallelCluster, FSx, PCUI, etc.). |
| `daylily-omics-analysis` | Houses Snakemake workflows, CLI tooling, manifests, and analysis documentation. |

The remainder of this document assumes you already have an ephemeral cluster available or are running locally with compatible dependencies.

## Highlights

* **Reproducible WGS workflows.** Short-read, long-read and hybrid pipelines covering alignment, deduplication, variant discovery (SNV/SV), QC aggregation (MultiQC), concordance reporting, and more.
* **Cost-aware benchmarking.** Built-in helpers to export task-level runtime and cost data so accuracy can be interpreted alongside spend.
* **Reference curation.** Re-usable manifests, GIAB sample sheets, and tooling to stage the shared reference buckets used by the cluster environment.
* **Configurable execution.** Profiles for local execution and Slurm-backed cluster execution, including containerised and Conda-based environments.
* **Transparent data products.** Results are organised per genome build under `results/day/<build>/` with concordance and QC artefacts grouped for inspection.

A broader motivation for the project, including why the pipelines emphasise FAIR bioinformatics practices, reproducible hardware profiles, and transparent cost reporting, is captured in the [Intention](#intention) section below.

## Quick Start

The fastest way to experience the workflows is to run the built-in smoke test using the GIAB 0.01× HG002 dataset.  The steps below assume you have cloned this repository onto the head node of an ephemeral cluster created with `daylily-ephemeral-cluster`.  The same commands can also run locally provided the dependencies defined in [setup.py](setup.py) are installed.

1. **Clone the repository.**
   ```bash
   git clone https://github.com/Daylily-Informatics/daylily-omics-analysis.git
   cd daylily-omics-analysis
   ```

2. **Initialise the Daylily CLI and activate a profile.**
   ```bash
   # from the repository root
   bash               # start a clean shell session if connecting via SSH
   . dyoainit           # configures the DAYOA conda env and CLI helpers
   dy-a local hg38    # or `dy-a slurm hg38` to target the cluster profile
   ```

3. **Stage sample metadata tables.**
   ```bash
   cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
   cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv
   ```

4. **Dry-run the workflow.**
   ```bash
   dy-r seqqc -j 1 -p -k -n
   ```

5. **Execute the workflow.**
   ```bash
   dy-r seqqc -j 1 -p -k
   ```

   Results will be written under `results/day/hg38/` and logs will collect in `logs/`.

6. **Scale out on the cluster (optional).**
   ```bash
   dy-a slurm hg38
   dy-r produce_snv_concordances -p -k -j 6 --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep']
   ```

For instructions on crafting custom sample/unit tables, enabling additional tools (e.g. DeepVariant, Octopus, Clair3, Manta, Tiddit, etc.) and working with the GIAB 30× datasets, continue with the [First Ephemeral Cluster Analysis](docs/first_ephemeral_cluster_analysis.md) guide.

## Documentation Roadmap

| Document | Purpose |
| --- | --- |
| [`docs/quickest_start.md`](docs/quickest_start.md) | Checklist for new users that links infrastructure bootstrapping with the minimal analysis steps in this repository. |
| [`docs/first_ephemeral_cluster_analysis.md`](docs/first_ephemeral_cluster_analysis.md) | Detailed walkthrough for cloning the repo on a head node, preparing manifests, and running both local and Slurm-backed jobs. |
| [`docs/advanced/`](docs/advanced) | Deep dives on specialised workflows, benchmarking, and operations. |
| [`docs/reports/`](docs/reports) | Example concordance and QC outputs from previous Daylily runs. |
| [`docs/whitepaper/`](docs/whitepaper) | Background material for the forthcoming Daylily whitepaper. |

## Repository Layout

```
### Run A Local Test Workflow

#### First, clone this repository into a new analysis directory.

Create a directory for your analysis under `/fsx/analysis_results/ubuntu/` and clone this repository into it using git.

```bash
mkdir -p /fsx/analysis_results/ubuntu/first_analysis
cd /fsx/analysis_results/ubuntu/first_analysis
git clone <repository-url> daylily
cd daylily

```
  > *note*: if you have an active DAYOA conda env, begin a fresh bash shell from your new analysis dir, `bash`.

#### Next, init daylily, set the genome, stage sample/unit tables and run a test workflow.

```bash
. dyoainit  --project PROJECT

dy-a local hg38 # the other option: b37 ( or set via config command line below)

cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

head -n 2 config/units.tsv

export DAY_CONTAINERIZED=false # or true to use pre-built container of all analysis envs. false will create each conda env as needed

dy-r produce_deduplicated_bams -p -j 2 --config genome_build=hg38 aligners=['bwa2a','sent'] dedupers=['dppl'] -n # dry run
dy-r produce_deduplicated_bams -p -j 2 --config genome_build=hg38 aligners=['bwa2a','sent'] dedupers=['dppl'] 
```

#### More On The `-j` Flag

The `-j` flag specified in `dy-r` limits the number of jobs submitted to slurm. For out of the box settings, the advised range for `-j` is 1 to 10. You may omit this flag, and allow submitting all potnetial jobs to slurm, which slurm, /fsx, and the instances can handle growing to the 10s or even 100 thousands of instances... however, various quotas will begin causing problems before then.  The `local` defauly is set to `-j 1` and `slurm` is set to `-j 10`, `-j` may be set to any int > 0.

This will produce a job plan, and then begin executing. The bundled multi-sample tables live in `.test_data/data/0.01x_3_wgs_HG002_hg38.samples.tsv` and `.test_data/data/0.01x_3_wgs_HG002_hg38.units.tsv`. Runtime on the default small test data running locally on the default headnode instance type should be ~5min.

```text
NOTE! NOTE !! NOTE !!! ---- The Undetermined Sample Is Excluded. Set --config keep_undetermined=1 to process it.
Building DAG of jobs...
Creating conda environment workflow/envs/vanilla_v0.1.yaml...
Downloading and installing remote packages.
Environment for /home/ubuntu/projects/daylily/workflow/rules/../envs/vanilla_v0.1.yaml created (location: ../../../../fsx/resources/environments/conda/ubuntu/ip-10-0-0-37/f7b02dfcffb9942845fe3a995dd77dca_)
Creating conda environment workflow/envs/strobe_aligner.yaml...
Downloading and installing remote packages.
Environment for /home/ubuntu/projects/daylily/workflow/rules/../envs/strobe_aligner.yaml created (location: ../../../../fsx/resources/environments/conda/ubuntu/ip-10-0-0-37/a759d60f3b4e735d629d60f903591630_)
Using shell: /usr/bin/bash
Provided cores: 16
Rules claiming more threads will be scaled down.
Provided resources: vcpu=16
Job stats:
job                          count    min threads    max threads
-------------------------  -------  -------------  -------------
doppelmark_dups                  1             16             16
pre_prep_raw_fq                  1              1              1
prep_results_dirs                1              1              1
produce_deduplicated_bams        1              1              1
stage_supporting_data            1              1              1
strobe_align_sort                1             16             16
workflow_staging                 1              1              1
total                            7              1             16
```

> This should exit with a magenta success message and `RETURN CODE: 0`. Results can be found in `results/day/{hg38,b37}`.


### Run A Slurm Test Workflow

The following will submit jobs to the slurm scheduler on the headnode, and spot instances will be spun up to run the jobs (modulo limits imposed by config and quotas).

First, create a working directory on the `/fsx/` filesystem.

> init daylily, activate an analysis profile, set genome, stage an analysis_manigest.csv and run a test workflow.

```bash
# create a working analysis directory & clone daylily
mkdir -p /fsx/analysis_results/first_analysis
cd /fsx/analysis_results/first_analysis
git clone <repository-url> daylily
cd daylily

#  prepare to run the test
tmux new -s slurm_test
. dyoainit 
dy-a slurm hg38 # the other options being b37

# create a test sample/unit pair for one giab sample only, which will run on the 0.01x test dataset
cp .test_data/data/0.01xwgs_HG002_hg38.samples.tsv config/samples.tsv
cp .test_data/data/0.01xwgs_HG002_hg38.units.tsv config/units.tsv

export DAY_CONTAINERIZED=false # or true to use pre-built container of all analysis envs. false will create each conda env as needed

# run the test, which will auto detect the sample/unit tables & will run this all via slurm
dy-r produce_snv_concordances -p -k -j 2 --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep'] -n
```

Which will produce a plan that looks like.

```text

Job stats:
job                           count    min threads    max threads
--------------------------  -------  -------------  -------------
deep_concat_fofn                  1              2              2
deep_concat_index_chunks          1              4              4
deepvariant                      24             64             64
doppelmark_dups                   1            192            192
dv_sort_index_chunk_vcf          24              4              4
pre_prep_raw_fq                   1              1              1
prep_deep_chunkdirs               1              1              1
prep_for_concordance_check        1             32             32
prep_results_dirs                 1              1              1
produce_snv_concordances          1              1              1
stage_supporting_data             1              1              1
strobe_align_sort                 1            192            192
workflow_staging                  1              1              1
total                            59              1            192
```

Run the test with:

```bash
dy-r produce_snv_concordances -p -k -j 6  --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep'] #  -j 6 will run 6 jobs in parallel max, which is done here b/c the test data runs so quickly we do not need to spin up one spor instance per deepvariant job & since 3 dv jobs can run on a 192 instance, this flag will limit creating only  2 instances at a time.
```

_note1:_ the first time you run a pipeline, if the docker images are not cached, there can be a delay in starting jobs as the docker images are cached. They are only pulled 1x per cluster lifetime, so subsequent runs will be faster.

_note2:_ The first time a cold cluster requests spot instances, can take some time (~10min) to begin winning spot bids and running jobs. Hang tighe, and see below for monitoring tips.

#### (RUN ON A FULL 30x WGS DATA SET)

**ALERT** The legacy `analysis_manifest.csv` workflow has been replaced by paired `samples.tsv` and `units.tsv` tables. The commands below reference both files when staging data.

##### Specify A Single Sample Manifest

You may repeat the above, and use the pre-existing sample/unit templates `.test_data/data/giab_30x_hg38_analysis_manifest.samples.tsv` and `.test_data/data/giab_30x_hg38_analysis_manifest.units.tsv`.

```bash
tmux new -s slurm_test_30x_single

# Create new analysis dir
mkdir -p /fsx/analysis_results/slurmtest
cd /fsx/analysis_results/slurmtest
git clone <repository-url> daylily
cd daylily


. dyoainit  --project PROJECT 
dy-a slurm hg38 # the other option being b37

# TO create a single sample manifest
head -n 2 .test_data/data/giab_30x_hg38_analysis_manifest.samples.tsv > config/samples.tsv
head -n 2 .test_data/data/giab_30x_hg38_analysis_manifest.units.tsv > config/units.tsv

export DAY_CONTAINERIZED=false # or true to use pre-built container of all analysis envs. false will create each conda env as needed

dy-r produce_snv_concordances -p -k -j 10 --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep'] -n  # dry run

dy-r produce_snv_concordances -p -k -j 10  --config genome_build=hg38 aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep'] # run jobs, and wait for completion
```


##### Specify A Multi-Sample Manifest (in this case, all 7 GIAB samples) - 2 aligners, 1 deduper, 2 snv callers

```bash

tmux new -s slurm_test_30x_multi

# Create new analysis dir
mkdir -p /fsx/analysis_results/fulltest
cd /fsx/analysis_results/fulltest
git clone <repository-url> daylily
cd daylily


. dyoainit  --project PROJECT 
dy-a slurm hg38 # the other options being b37

# copy full 30x giab sample templates into config/
cp .test_data/data/giab_30x_hg38_analysis_manifest.samples.tsv  config/samples.tsv
cp .test_data/data/giab_30x_hg38_analysis_manifest.units.tsv  config/units.tsv

export DAY_CONTAINERIZED=false # or true to use pre-built container of all analysis envs. false will create each conda env as needed

dy-r produce_snv_concordances -p -k -j 10 --config genome_build=hg38 aligners=['strobe,'bwa2a'] dedupers=['dppl'] snv_callers=['oct','deep'] -n  # dry run

dy-r produce_snv_concordances -p -k -j 10 --config genome_build=hg38 aligners=['strobe','bwa2a'] dedupers=['dppl'] snv_callers=['oct','deep'] 

```

##### The Whole Magilla (3 aligners, 1 deduper, 5 snv callers, 3 sv callers)

```bash
max_snakemake_tasks_active_at_a_time=2 # for local headnode, maybe 400 for a full cluster
dy-r produce_snv_concordances produce_manta produce_tiddit produce_dysgu produce_kat produce_multiqc_final_wgs -p -k -j $max_snakemake_tasks_active_at_a_time --config genome_build=hg38 aligners=['strobe','bwa2a','sent'] dedupers=['dppl'] snv_callers=['oct','sentd','deep','clair3','lfq2'] sv_callers=['tiddit','manta','dysgu'] -n
```

## To Create Your Own `config/samples.tsv` and `config/units.tsv`

The paired tables are required to run the daylily pipeline. They should be created by following the column layout shown in the smoke-test examples under `.test_data/data/`. Updated helpers for generating the tables from lab manifests are in progress; for legacy workflows you may still use `./bin/daylily-analysis-samples-to-manifest-new` and then convert the output into the new structure.

**this script is still in development, more docs to come**, run with `-h` for now and see the example [etc/analysis_samples.tsv template](etc/analysis_samples.tsv) file for the format of the `analysis_samples.tsv` file. You also need to have a valid ephemeral cluster available.

**TODO** document this

---

## Supported References

The references supported via cloning public references s3 bucket are `b37`, `hg38`, `hg38_broad`.  You specify a reference build by setting `export DAY_GENOME_BUILD=hg38` and/or when activating a compute environment, ie: `dy-a slurm hg38`. `dy-g hg38` will also do the trick.

### b37
- with no alt contigs.

### h38
- with no alt contigs.

### hg38_broad
- all contigs


### Reference Artifacts

#### Supporting Files `yaml`
- The build will direct daylily to choose the correct `config/supporting_files/${DAY_GENOME_BUILD}_suppoting_files.yaml` which contain the paths to resources specific to the build.

#### `/fsx/data/genomic_data/organism_references/H_sapiens/$DAY_GENOME_BUILD` Files

- All reference files can be found here for the build.

#### `/fsx/data/genomic_data/organism_annotations/H_sapiens/$DAY_GENOME_BUILD` Files

- All annotation files can be found here for the build

#### Results Directories: `./results/day/$DAY_GENOME_BUILD/`

- Each build has it's own results subdirectory.

## Slurm Monitoring

### Monitor Slurm Submitted Jobs

Once jobs begin to be submitted, you can monitor from another shell on the headnode(or any compute node) with:

```bash
# The compute fleet, only nodes in state 'up' are running spots. 'idle' are defined pools of potential spots not bid on yet.
sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
i8*          up   infinite     12  idle~ i8-dy-gb64-[1-12]
i32          up   infinite     24  idle~ i32-dy-gb64-[1-8],i32-dy-gb128-[1-8],i32-dy-gb256-[1-8]
i64          up   infinite     16  idle~ i64-dy-gb256-[1-8],i64-dy-gb512-[1-8]
i96          up   infinite     16  idle~ i96-dy-gb384-[1-8],i96-dy-gb768-[1-8]
i128         up   infinite     28  idle~ i128-dy-gb256-[1-8],i128-dy-gb512-[1-10],i128-dy-gb1024-[1-10]
i192         up   infinite      1  down# i192-dy-gb384-1
i192         up   infinite     29  idle~ i192-dy-gb384-[2-10],i192-dy-gb768-[1-10],i192-dy-gb1536-[1-10]

# running jobs, usually reflecting all running node/spots as the spot teardown idle time is set to 5min default.
squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 1      i192 D-strobe   ubuntu PD       0:00      1 (BeginTime)
# ST = PD is pending
# ST = CF is a spot has been instantiated and is being configured
# PD and CF sometimes toggle as the spot is configured and then begins running jobs.

 squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 1      i192 D-strobe   ubuntu  R       5:09      1 i192-dy-gb384-1
# ST = R is running


# Also helpful
watch squeue

# also for the headnode
glances
```


### SSH Into Compute Nodes

You can not access compute nodes directly, but can access them via the head node. From the head node, you can determine if there are running compute nodes with `squeue`, and use the node names to ssh into them.

```bash
ssh i192-dy-gb384-1
```


### Delete Cluster

**warning**: this will delete all resources created for the ephemeral cluster, importantly, including the fsx filesystem. You must export any analysis results created in `/fsx/analysis_results` from the `fsx` filesystem  back to `s3` before deleting the cluster. 

- During cluster config, you will choose if Fsx and the EBS volumes auto-delete with cluster deletion. If you disable auto-deletion, these idle volumes can begin to cost a lot, so keep an eye on this if you opt for retaining on deletion.

### Export `fsx` Analysis Results Back To S3

#### Facilitated

Run:

```bash
./bin/daylily-export-fsx-to-s3 <cluster_name> <region> <export_path:analysis_results>
```

- export_path should be `analysis_results` or a subdirectory of `analysis_results/*` to export successfully. 
- The script will run, and report status until complete. If interrupted, the export will not be halted. 
- You can visit the FSX console, and go to the Fsx filesystem details page to monitor the export status in the data repository tab.


#### Via `FSX` Console

- Go to the 'fsx' AWS console and select the filesystem for your cluster.
- Under the `Data Repositories` tab, select the `fsx` filesystem and click `Export to S3`. Export can only currently be carried out back to the same s3 which was mounted to the fsx filesystem. 
- Specify the export path as `analysis_results` (or be more specific to an `analysis_results/subdir`), the path you enter is named relative to the mountpoint of the fsx filesystem on the cluster head and compute nodes, which is `/fsx/`. Start the export. This can take 10+ min.  When complete, confirm the data is now visible in the s3 bucket which was exported to. Once you confirm the export was successful, you can delete the cluster (which will delete the fsx filesystem).

#### Delete The Cluster, For Real

_note: this will not modify/delete the s3 bucket mounted to the fsx filesystem, nor will it delete the policyARN, or private/public subnets used to config the ephemeral cluster._

**the headnode `/root` volume and the fsx filesystem will be deleted if not explicitly flagged to be saved -- be sure you have exported Fsx->S3 before deleting the cluster**

```bash
pcluster delete-cluster-instances -n <cluster-name> --region us-west-2
pcluster delete-cluster -n <cluster-name> --region us-west-2
```

- You can monitor the status of the cluster deletion using `pcluster list-clusters --region us-west-2` and/or `pcluster describe-cluster -n <cluster-name> --region us-west-2`. Deletion can take ~10min depending on the complexity of resources created and fsx filesystem size.



<p valign="middle"><img src="docs/images/000000.png" valign="bottom" ></p>

# Other Monitoring Tools

## PCUI (Parallel Cluster User Interface)
... For real, use it!

## Quick SSH Into Headnode
(also, can be done via pcui)

`bin/daylily-ssh-into-headnode`

_alias it for your shell:_ `alias goday="source ~/git_repos/daylily/bin/daylily-ssh-into-headnode"`


---

## AWS Cloudwatch

- The AWS Cloudwatch console can be used to monitor the cluster, and the resources it is using.  This is a good place to monitor the health of the cluster, and in particular the slurm and pcluster logs for the headnode and compute fleet.
- Navigate to your `cloudwatch` console, then select `dashboards` and there will be a dashboard named for the name you used for the cluster. Follow this link (be sure you are in the `us-west-2` region) to see the logs and metrics for the cluster.
- Reports are not automaticaly created for spot instances, but you may extend this base report as you like.  This dashboard is automatically created by `pcluster` for each new cluster you create (and will be deleted when the cluster is deleted).



<p valign="middle"><img src="docs/images/000000.png" valign="bottom" ></p>
 
# And There Is More

## S3 Reference Bucket & Fsx Filesystem

### PREFIX-omics-analysis-REGION Reference Bucket

Daylily relies on a variety of pre-built reference data and resources to run. These are stored in the `daylily-references-public` bucket. You will need to clone this bucket to a new bucket in your account, once per region you intend to operate in.  

> This is a design choice based on leveraging the `FSX` filesystem to mount the data to the cluster nodes. Reference data in this S3 bucket are auto-mounted an available to the head and all compute nodes (*Fsx supports 10's of thousands of concurrent connections*), further, as analysis completes on the cluster, you can choose to reflect data back to this bucket (and then stage elsewhere). Having these references pre-arranged aids in reproducibility and allows for the cluster to be spun up and down with negligible time required to move / create refernce data. 

> BONUS: the 7 giab google brain 30x ILMN read sets are included with the bucket to standardize benchmarking and concordance testing.

> You may add / edit (not advised) / remove data (say, if you never need one of the builds, or don't wish to use the GIAB reads) to suit your needs.

#### Reference Bucket Metrics

*Onetime* cost of between ~$27 to ~$108 per region to create bucket.

*monthly S3 standard* cost of ~$14/month to continue hosting it.

- Size: 617.2GB, and contains 599 files.
- Source bucket region: `us-west-2`
- Cost to store S3 (standard: $14.20/month, IA: $7.72/month, Glacier: $2.47 to $0.61/month)
- Data transfer costs to clone source bucket
  - within us-west-2: ~$3.40
  - to other regions: ~$58.00
- Accelerated transfer is used for the largest files, and adds ~$24.00 w/in `us-west-2` and ~$50 across regions.
- Cloning w/in `us-west-2` will take ~2hr, and to other regions ~7hrs.
- Moving data between this bucket and the FSX filesystem and back is not charged by size, but by number of objects, at a cost of `$0.005 per 1,000 PUT`. The cost to move 599 objecsts back and forth once to Fsx is `$0.0025`(you do pay for Fsx _when it is running, which is only when you choose to run analysus_).

### The `YOURPREFIX-omics-analysis-REGION` s3 Bucket

- Your new bucket name needs to end in `-omics-analysis-REGION` and be unique to your account.
- One bucket must be created per `REGION` you intend to run in.
- The reference data version is currently `0.7`, and will be replicated correctly using the script below.
- The total size of the bucket will be 779.1GB, and the cost of standard S3 storage will be ~$30/mo.
- Copying the daylily-references-public bucket will take ~7hrs using the script below.

#### daylily-references-public Bucket Contents

- `hg38` and `b37` reference data files (including supporting tool specific files).
- 7 google-brain ~`30x` Illunina 2x150 `fastq.gz` files for all 7 GIAB samples (`HG001,HG002,HG003,HG004,HG005,HG006,HG007`).
- snv and sv truth sets (`v4.2.1`) for all 7 GIAB samples in both `b37` and `hg38`.
- A handful of pre-built conda environments and docker images (for demonstration purposes, you may choose to add to your own instance of this bucket to save on re-building envs on new eclusters).
- A handful of scripts and config necessary for the ephemeral cluster to run.

_note:_ you can choose to eliminate the data for `b37` or `hg38` to save on storage costs. In addition, you may choose to eliminate the GIAB fastq files if you do not intend to run concordance or benchmarking tests (which is advised against as this framework was developed explicitly to facilitate these types of comparisons in an ongoing way).

##### Top Level Diretories

See the secion on [shared Fsx filesystem](#shared-fsx-filesystem) for more on hos this bucket interacts with these ephemeral cluster region specific S3 buckets.

```text
.
├── bin/                # helper scripts used by the CLI and workflows
├── config/             # Snakemake profiles, tool configuration, and manifests
├── docs/               # user guides, whitepaper drafts, metrics and demos
├── resources/          # supporting resources staged on the cluster FSx volume
├── workflow/           # Snakemake rules, environments and shared logic
└── .test_data/         # small data bundles for smoke testing
```

## Intention

> The goal of daylily is to enable more rigorous comparisons of informatics tools by formalising their compute environments and establishing hardware profiles that reproduce each tool’s accuracy and runtime/cost performance. This approach is general and not tied to a single toolset; while AWS is involved, nothing prevents deployment elsewhere. AWS simply offers a standardised hardware environment accessible to anyone with an account. By “compute environment,” I mean more than a container—containers alone don’t guarantee hardware performance, and cost/runtime considerations demand reproducibility on specific hardware. Though daylily uses containers and conda, it remains agnostic about the tools themselves. I have three main aims:

### Shift Focus

Move away from unhelpful debates over “the best” tool and toward evidence-based evaluations. Real use cases dictate tool choice, so let’s make sure relevant data and clear methodologies are accessible—or at least ensure enough detail is published to make meaningful comparisons. Specifically, this means moving beyond limited summary metrics that fail to describe our tools in sufficient detail.

### Raise the Bar

Demand better metrics and documentation in tool publications: thorough cost data, specific and reproducible hardware details, more nuanced concordance metrics, and expansive QC reporting. Half-measures shouldn’t pass as “sufficient.”

### Escape Outdated “Best Practices”

The field is stuck relying on practices that were sufficient a decade ago. We need shareable frameworks that capture both accuracy and cost/runtime for truly reproducible pipeline performance—so we can finally move forward.

The [Daylily GIAB analyses repository](https://github.com/Daylily-Informatics/daylily_giab_analyses) contains (work in progress) results from the first stable Daylily release, run on seven GIAB samples.  Draft whitepaper content is tracked in [`docs/whitepaper`](docs/whitepaper).

## Community & Support

Daylily development is self-funded.  If you would like to collaborate, extend the workflows, or discuss benchmarking results, please reach out via [john@daylilyinformatics.com](mailto:john@daylilyinformatics.com).  Consulting engagements are available through [https://www.dyly.bio](https://www.dyly.bio).

## Contributing

Contributions that improve reproducibility, expand workflow coverage, or enhance documentation are very welcome.  See [`CONTRIBUTING.md`](CONTRIBUTING.md) for details on the preferred workflow, coding standards, and how to propose changes.

## License

This project is released under the terms of the [MIT License](LICENSE).
X
