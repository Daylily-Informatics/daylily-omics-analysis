# CRITICAL - SSH LOGIN SHELLS (READ FIRST)
**EVERY SSH command to remote hosts MUST use `bash -l -c`**
- **PATTERN (MANDATORY)**: `ssh -i <pemfile> ubuntu@<headnode-ip> "bash -l -c 'your command here'"`
- **WHY**: Login shells initialize PATH, conda, aliases, functions
- **WITHOUT login shell**: Commands fail silently (squeue not found, conda unavailable, etc.)
- **NEVER deviate** from this pattern. No exceptions.
- See "SSH Commands" section below for details and examples.

# AWS CREDENTIALS
Ask user for profile name to set AWS_PROFILE to, never use default as profile name.

# UPON STARTING A NEW TERMINAL SESSION ON A MAC
On a mac, no workflows will actually ever be run, but we need the conda env for the dy-cli to work to debug and tinker locally.  This repo must be deployed to an AWS ParallelCluster headnode which has been configured by `daylily-ephemeral-cluster`, and each analysis workset is run from a clone of this repo (or reruns).

# TERMINAL STARTUP (ALWAYS RUN THESE COMMANDS IN THIS ORDER)
## ON A MAC 
Always `conda activate DAY-EC`, little is done in this repo from a mac, but most dependencies needed to tinker and debug are in the daylily-ephemeral-cluster env DAY-EC.

## ON THE HEADNODE (ubuntu)
- Intended use via is brokered by daylily-ephemeral-cluster, often via the GUI daylily-ursa. 
- CLONE REPO USING `day-clone` (which should be in the login bash PATH). See the day-clone --help for more info (and the .md docs).
- upon moving to reso cloned dir (the analysis dir):
  - INITIALIZE: source the `dyoainit` script to initialize the dy-cli. (note: the output of dyoainit should tell you how to activte slurm or local execution env, set genome build, run example commands.
  - ACTIVATE: `dy-a local hg38` to activate the local execution env, or  `dy-a slurm hg38` to activate the slurm execution env. Note, the second argument is the genome build, and must be set. In practice, this is almost always `hg38`, but could be `b37` or `hg38_broad`. 
  - RUN: `dy-r help` to see the available targets, and the init output should tell you how to run the common workflow. Important flags: -n for dry run, -p to print helpful info to stdout, -j for job limit (local should be 1 or 2, slurm can be 300-500), -k to keep going if a job fails... the dy-r cli command actually composes a complex snakemake command given these user command line specified ones. Run `dy-r --help` for all of them.

## Wrapper Script (alternative to dy-r)
`bin/augment_setup_and_run_dayoa.bash` combines init, activate, and run into a single sourced command. Useful for tmux sessions and automation.

```bash
source bin/augment_setup_and_run_dayoa.bash <executor> <genome_build> "<targets>" "<snakemake_flags>" ["<dry_run_flag>"]
```

- **executor**: `local` or `slurm`
- **genome_build**: `hg38`, `hg38_broad`, or `b37`
- **targets**: Quoted space-separated Snakemake targets (e.g. `"produce_snv_concordances"`)
- **snakemake_flags**: Quoted flags (e.g. `"-p -j 10 -k -T 1"`)
- **dry_run_flag**: Optional 5th arg. Pass `"-n"` for dry-run; omit for real execution.

Examples:
```bash
# Dry-run
source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad \
    "produce_snv_concordances" "-p -j 2 -k -T 1" "-n"

# Production run
source bin/augment_setup_and_run_dayoa.bash slurm hg38 \
    "produce_sentdhiom_vcf produce_snv_concordances" "-p -j 2 -k -T 1"
```

**Important**: This script must be `source`d (not executed) because `dyoainit` uses `return`. Use `bash bin/day_run` internally (not `source bin/day_run`) so that `exit` in day_run stays in a subprocess.

# Debugging From MAC
If given an AWS_PROFILE, region, cluster name, pem file, and optionally the : path to analysis, and potentially a tmux session analysis is running in. With the `DAY-EC` env actice, you can use `pcluster describe-cluster -n <name> --region <region>` to get the cluster headnode ip, and can then ssh into it using ssh -i <pemfile> ubuntu@<headnode-ip>.

## SSH Commands
**CRITICAL REQUIREMENTS**:
1. Always use login shells when running SSH commands. Use `ssh -i <pemfile> ubuntu@<headnode-ip> "bash -l -c 'your command here'"` to ensure the full shell environment (including PATH and conda) is available.
2. **Never use SSM (Systems Manager)** — always use direct SSH with login shells.
3. **`squeue` must be on PATH** — if `squeue` is not available, the command must fail loudly with an error. Do NOT report zero exit code or silently skip SLURM status checks.

## Terminal Heredoc Corruption
**CRITICAL RULE - DO NOT USE HEREDOC**:
- **NEVER use heredoc syntax** (`<< 'EOF'`, `<< 'EOFSCRIPT'`, etc.) in terminal commands. Heredoc ALWAYS corrupts the terminal with character doubling and scrambling.
- **ALWAYS use temporary scripts instead**: Write scripts to `/tmp/` using `save-file` tool or echo commands, then execute them.
- **Alternative approaches**:
  - Use `save-file` tool to create scripts (preferred)
  - Use multiple `echo` commands to build files line-by-line
  - Use Python to write files
  - Use `str-replace-editor` to create/edit files
- **If terminal becomes corrupted**: Kill the terminal with `kill-process` and start a fresh one.

# Log Locations for SLURM-based Workflows

When jobs are running via the SLURM profile in `/fsx/analysis_results/ubuntu/<workdir>/`, logs are split across three locations:

1. **Snakemake Master Log** (PRIMARY - read this first)
   - Location: `.snakemake/log/<most_recent_timestamp>`
   - Contains: Snakemake command output, rule execution order, and progress updates (e.g., "3 of 1556 steps (0.2%) done")
   - On failure: Includes failure messages (note: failures may not be terminal; Snakemake may retry based on configuration)

2. **SLURM Job Logs** (SECONDARY - per-job details)
   - Location: `logs/slurm/<taskname>/*.out` and `logs/slurm/<taskname>/*.err`
   - Named by SLURM job ID
   - Important: Job reruns create new log files; use file modification timestamps to find the latest logs
   - Reruns may have smaller job IDs than previous attempts

3. **Rule-Specific Logs** (TERTIARY - rule execution details)
   - Location: `.snakemake/log/` (Snakemake-managed) and `logs/slurm/` (SLURM-managed)
   - Contains: Output and errors from individual rule executions

4. **Command History Log**
   - Location: `day_cmds.log`
   - Contains: Record of all `dy-r` command invocations

**Debugging Strategy**: Start with the Snakemake master log to identify which rules failed, then check the corresponding SLURM logs by job ID and timestamp to see detailed error messages.

# Sentieon Info
Some can be found here: https://github.com/Sentieon/sentieon-models?tab=readme-ov-file
