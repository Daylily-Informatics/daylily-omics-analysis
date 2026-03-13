#!/bin/bash
# ---------------------------------------------------------------------------
# augment_setup_and_run_dayoa.bash
#
# Wrapper that initialises a daylily analysis directory, activates the
# execution environment, and launches a Snakemake workflow via day_run.
#
# USAGE (must be *sourced*, not executed, because dyoainit uses `return`):
#
#   source bin/augment_setup_and_run_dayoa.bash <executor> <genome_build> \
#       "<targets>" "<snakemake_flags>" ["<dry_run_flag>"]
#
# POSITIONAL ARGUMENTS:
#   1  executor        - local | slurm
#   2  genome_build    - hg38 | hg38_broad | b37
#   3  targets         - Quoted, space-separated Snakemake target rules
#   4  snakemake_flags - Quoted Snakemake flags, e.g. "-p -j 10 -k -T 1"
#   5  dry_run_flag    - Optional. Pass "-n" for dry-run; omit for real run
#
# EXAMPLES:
#   # Dry-run
#   source bin/augment_setup_and_run_dayoa.bash slurm hg38 \
#       "produce_snv_concordances" "-p -j 2 -k -T 1" "-n"
#
#   # Production run
#   source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad \
#       "produce_snv_concordances" "-p -j 2 -k -T 1"
# ---------------------------------------------------------------------------

set -uo pipefail

LOCAL_OR_SLURM="${1:-}"
GENOME_CODE="${2:-}"
SNAKEMAKE_TARGETS="${3:-}"
SNAKEMAKE_FLAGS="${4:-}"
DRY_RUN="${5:-}"

# --- Validate required args ------------------------------------------------
if [[ -z "$LOCAL_OR_SLURM" || -z "$GENOME_CODE" || -z "$SNAKEMAKE_TARGETS" ]]; then
    echo "ERROR: Missing required arguments." >&2
    echo "Usage: source bin/augment_setup_and_run_dayoa.bash <executor> <genome_build> \"<targets>\" \"<flags>\" [\"<-n>\"]" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ "$LOCAL_OR_SLURM" != "local" && "$LOCAL_OR_SLURM" != "slurm" ]]; then
    echo "ERROR: executor must be 'local' or 'slurm', got '$LOCAL_OR_SLURM'" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ "$GENOME_CODE" != "hg38" && "$GENOME_CODE" != "hg38_broad" && "$GENOME_CODE" != "b37" ]]; then
    echo "ERROR: genome_build must be hg38, hg38_broad, or b37, got '$GENOME_CODE'" >&2
    return 1 2>/dev/null || exit 1
fi

# --- Initialise and activate -----------------------------------------------
source dyoainit
source bin/day_activate "$LOCAL_OR_SLURM" "$GENOME_CODE"

# --- Run (word-split targets/flags intentionally) --------------------------
# shellcheck disable=SC2086
bash bin/day_run $SNAKEMAKE_TARGETS $SNAKEMAKE_FLAGS $DRY_RUN
