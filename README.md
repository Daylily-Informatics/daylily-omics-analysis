# Daylily Omics Analysis

Daylily Omics Analysis provides the Snakemake-based workflows that power the Daylily whole genome sequencing (WGS) platform.  The pipelines support short-read, long-read and hybrid analyses, deliver concordance and QC reporting, and surface cost telemetry so that analytical performance can be evaluated alongside runtime and spend.  The repository previously lived alongside the infrastructure automation in a monorepo; it now focuses exclusively on analysis.  Cluster lifecycle management is handled by the companion project [daylily-ephemeral-cluster](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster).

> **Beta notice:** tagged releases are the preferred entry point for production use (for example `0.7.229`).  The `main` branch is used for active development and may change without notice.

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
   . dyinit           # configures the DAYOA conda env and CLI helpers
   dy-a local hg38    # or `dy-a slurm hg38` to target the cluster profile
   ```

3. **Stage a sample manifest.**
   ```bash
   cp .test_data/data/0.01xwgs_HG002_hg38.samplesheet.csv config/analysis_manifest.csv
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

For instructions on crafting custom manifests, enabling additional tools (e.g. DeepVariant, Octopus, Clair3, Manta, Tiddit, etc.) and working with the GIAB 30× datasets, continue with the [First Ephemeral Cluster Analysis](docs/first_ephemeral_cluster_analysis.md) guide.

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
