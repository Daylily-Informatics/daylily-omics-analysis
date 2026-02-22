#!/usr/bin/env bash
# extract_fastq_from_ultima_cram.sh
# Extract reads from an Ultima Genomics CRAM and write a single FASTQ.gz
# with Illumina NovaSeq-style read headers.
#
# Ultima data is single-end. Output is one FASTQ.gz file.
#
# NovaSeq header format:
#   @INSTRUMENT:RUN:FLOWCELL:LANE:TILE:X:Y 1:N:0:NNNNNNNN
#
# Usage:
#   ./extract_fastq_from_ultima_cram.sh <input.cram> <output.fastq.gz> <reference.fasta> [threads]
#
#   Slurm:
#     sbatch --partition i192,i192mem --cpus-per-task 16 \
#       ./extract_fastq_from_ultima_cram.sh in.cram out.fastq.gz ref.fa 16
#
# Requirements: samtools >= 1.17, awk, pigz (or gzip fallback)

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────
INPUT_CRAM="${1:-}"
OUTPUT_FQ="${2:-}"
REFERENCE="${3:-}"
THREADS="${4:-${SLURM_CPUS_PER_TASK:-$(nproc)}}"

if [[ -z "$INPUT_CRAM" || -z "$OUTPUT_FQ" || -z "$REFERENCE" ]]; then
    echo "Usage: $0 <input.cram> <output.fastq.gz> <reference.fasta> [threads]"
    echo ""
    echo "  input.cram      Ultima Genomics aligned CRAM"
    echo "  output.fastq.gz Output FASTQ with NovaSeq-style headers"
    echo "  reference.fasta Reference genome used to encode the CRAM"
    echo "  threads         Samtools threads (default: nproc)"
    exit 1
fi

for f in "$INPUT_CRAM" "$REFERENCE"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: file not found: $f" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "$OUTPUT_FQ")"
if [[ -f "$OUTPUT_FQ" ]]; then
    echo "ERROR: output already exists: $OUTPUT_FQ" >&2
    exit 1
fi

# Pick best available compressor
if command -v pigz &>/dev/null; then
    COMPRESS="pigz -p ${THREADS} -c"
elif command -v igzip &>/dev/null; then
    COMPRESS="igzip -c"
else
    COMPRESS="gzip -c"
fi

echo "============================================"
echo "extract_fastq_from_ultima_cram.sh"
echo "============================================"
echo "Input CRAM:  $INPUT_CRAM"
echo "Output FASTQ: $OUTPUT_FQ"
echo "Reference:   $REFERENCE"
echo "Threads:     $THREADS"
echo "Compressor:  ${COMPRESS%% *}"
echo "Started:     $(date)"
echo "============================================"

# ── Instrument fields (synthetic NovaSeq) ─────────────────────────────
# These are cosmetic; any downstream tool that cares about platform
# should use the @RG PL tag, not parse read names.
INSTRUMENT="SN999"
RUN="1"
FLOWCELL="HUGFQ0001"
LANE="1"

# ── Extract → rewrite headers → compress ──────────────────────────────
# samtools fastq -0 emits all reads (single-end) to stdout when no
# -1/-2 is given and input has no proper pairs.
# The awk block rewrites the @readname line to NovaSeq format using a
# monotonic counter mapped to tile:x:y coordinates.

samtools fastq \
    -@ "$THREADS" \
    --reference "$REFERENCE" \
    -0 /dev/stdout \
    "$INPUT_CRAM" \
| awk -v inst="$INSTRUMENT" -v run="$RUN" -v fc="$FLOWCELL" -v lane="$LANE" '
BEGIN { n = 0 }
{
    if (NR % 4 == 1) {
        # Line 1 of FASTQ record: header
        n++
        tile = int(n / 100000000) + 1101
        x    = int((n / 10000) % 10000) + 1000
        y    = (n % 10000) + 1000
        printf "@%s:%s:%s:%s:%d:%d:%d 1:N:0:NNNNNNNN\n", inst, run, fc, lane, tile, x, y
    } else {
        print
    }
}' \
| $COMPRESS > "$OUTPUT_FQ"

# ── Verify ────────────────────────────────────────────────────────────
if [[ -f "$OUTPUT_FQ" ]]; then
    SIZE=$(stat -c%s "$OUTPUT_FQ" 2>/dev/null || stat -f%z "$OUTPUT_FQ")
    echo "Output size: $SIZE bytes ($(echo "scale=2; $SIZE/1073741824" | bc) GiB)"
    echo ""
    echo "First 2 records:"
    zcat "$OUTPUT_FQ" | head -8
    echo ""
    echo "✅ Done: $(date)"
else
    echo "❌ ERROR: output file not created" >&2
    exit 1
fi

