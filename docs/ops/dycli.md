# DY-CLI

The Daylily CLI provides a streamlined interface for running genomics workflows.

## Basic Workflow

```bash
# Initialize the dy-cli
. dyoainit --project <PROJECT>

# Activate execution environment and genome build
dy-a slurm hg38          # or: dy-a local hg38, dy-a slurm hg38_broad

# Run workflows using target names (tab-complete available)
dy-r produce_snv_concordances -p -k -j 20 -n   # dry-run
dy-r produce_snv_concordances -p -k -j 20      # execute

# Monitor workflow progress (in another terminal)
dy-m --interval 10

# Deactivate/reset environment
dy-d reset
```

## CLI Commands

| Command | Short | Description |
|---------|-------|-------------|
| `day-activate` | `dy-a` | Activate execution environment (local/slurm) and genome build |
| `day-run` | `dy-r` | Run Snakemake workflow with targets and flags |
| `day-monitor` | `dy-m` | Monitor workflow status (Snakemake, SLURM, logs) |
| `day-set-genome-build` | `dy-g` | Set genome build (hg38, hg38_broad, b37) |
| `day-deactivate` | `dy-d` | Deactivate environment (use `dy-d reset` for hard reset) |

## Monitoring Workflows

The `day-monitor` (or `dy-m`) command provides real-time monitoring of analysis workflows:

### Basic Usage

```bash
# Monitor with default 30-second updates
dy-m

# Monitor with custom interval (10 seconds)
dy-m --interval 10

# Monitor specific directory
dy-m --workdir /fsx/analysis_results/ubuntu/ifx_go

# Block and poll until workflow completes
dy-m --block-and-poll

# Block with custom interval
dy-m --interval 5 --block-and-poll
```

### Monitor Output

The monitor displays:
1. **Directory Stats** - Size, existence, last modified time
2. **Command History** - Last 5 commands from `day_cmd.log`
3. **SLURM Job Status** - Active jobs and their status
4. **Snakemake Master Log** - Latest 20 lines of Snakemake output
5. **Recent SLURM Logs** - Last 5 SLURM output/error files with tail

### Block-and-Poll Mode

Use `--block-and-poll` to wait for workflow completion:

```bash
# Start workflow in one terminal
dy-r produce_snv_concordances -p -k -j 20

# Monitor in another terminal (blocks until done)
dy-m --block-and-poll --interval 5
```

Exit codes:
- `0` - Workflow completed successfully
- `1` - Workflow failed
- Continues polling if still running

## Common Targets

| Target | Description | Genome Build |
|--------|-------------|--------------|
| `produce_snv_concordances` | Illumina short-read SNV + concordance | hg38 |
| `produce_alignstats` | Alignment statistics | any |
| `produce_sentdont_vcf` | ONT long-read SNV calling | hg38 |
| `produce_sentdpb_vcf` | PacBio long-read SNV calling | hg38 |
| `produce_sentdug_vcf` | Ultima SNV calling | hg38_broad |
| `produce_sentdhio_vcf` | Hybrid Illumina+ONT CLI | hg38 |
| `produce_sentdhuo_vcf` | Hybrid Ultima+ONT CLI | hg38_broad |
| `produce_sentdhiom_vcf` | Hybrid Illumina+ONT Modular | hg38 |
| `produce_sentdhuom_vcf` | Hybrid Ultima+ONT Modular | hg38_broad |

## Tab Completion

- `dy-r <TAB>` - lists all available targets
- `dy-r target -<TAB>` - lists snakemake flags
- `dy-a <TAB>` - lists available profiles (local, slurm)
- `dy-m -<TAB>` - lists monitor options (--workdir, --interval, --block-and-poll)


