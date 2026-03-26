#!/usr/bin/env bash
# Download files from presigned URLs, 3 at a time using wait.
# Generated 2026-03-25 — URLs expire 2026-04-01.
#
# Usage: bash download_presigned.sh [output_dir]
#   output_dir defaults to current directory.

set -euo pipefail

OUTDIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${SCRIPT_DIR}/presigned_manifest.tsv"
PARALLEL=3

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Manifest not found at $MANIFEST" >&2
    exit 1
fi

mkdir -p "$OUTDIR"
echo "=== Presigned URL Downloader ==="
echo "Downloading to: $(cd "$OUTDIR" && pwd)"
echo "Max parallel:   $PARALLEL"
echo "Manifest:       $MANIFEST"
echo "---"

RUNNING=0
FAILED=0
PIDS=()
NAMES=()

# Skip header line
while IFS=$'\t' read -r filename s3key size url; do
    human_size=$(awk "BEGIN{printf \"%.1f GiB\", $size/1073741824}" 2>/dev/null || echo "${size} bytes")
    echo "[$(date '+%H:%M:%S')] Starting: $filename ($human_size)"

    curl -fSL --retry 3 --retry-delay 5 -o "$OUTDIR/$filename" "$url" &
    PIDS+=($!)
    NAMES+=("$filename")
    RUNNING=$((RUNNING + 1))

    if [ "$RUNNING" -ge "$PARALLEL" ]; then
        # Wait for oldest job
        if ! wait "${PIDS[0]}"; then
            echo "ERROR: Failed to download ${NAMES[0]}" >&2
            FAILED=$((FAILED + 1))
        else
            echo "[$(date '+%H:%M:%S')] Completed: ${NAMES[0]}"
        fi
        PIDS=("${PIDS[@]:1}")
        NAMES=("${NAMES[@]:1}")
        RUNNING=$((RUNNING - 1))
    fi
done < <(tail -n +2 "$MANIFEST")

# Wait for remaining background jobs
for i in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$i]}"; then
        echo "ERROR: Failed to download ${NAMES[$i]}" >&2
        FAILED=$((FAILED + 1))
    else
        echo "[$(date '+%H:%M:%S')] Completed: ${NAMES[$i]}"
    fi
done

echo "---"
echo "All downloads finished."
if [ "$FAILED" -gt 0 ]; then
    echo "WARNING: $FAILED download(s) failed — check output above."
    exit 1
else
    echo "All files downloaded successfully to: $(cd "$OUTDIR" && pwd)"
fi

