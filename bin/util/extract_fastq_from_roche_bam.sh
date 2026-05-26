#!/usr/bin/env bash
# extract_fastq_from_roche_bam.sh
# Extract reads from a Roche SBX Duplex BAM and write FASTQ.gz files
# with Illumina NovaSeq-style read headers.
#
# Roche BAMs are paired-end (BWA-aligned).
# Output: R1 + R2 FASTQ.gz (or single interleaved if --interleave).
#
# NovaSeq header format:
#   @INSTRUMENT:RUN:FLOWCELL:LANE:TILE:X:Y READ:N:0:INDEX
#
# Usage:
#   ./extract_fastq_from_roche_bam.sh <input.bam> <out_prefix> [threads]
#
#   Outputs:  <out_prefix>_R1.fastq.gz  <out_prefix>_R2.fastq.gz
#
#   Slurm:
#     sbatch --partition i192,i192mem --cpus-per-task 16 \
#       ./extract_fastq_from_roche_bam.sh in.bam /fsx/out/HG001_roche 16
#
# Requirements: samtools >= 1.17, awk, pigz (or gzip fallback)

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────
INPUT_BAM="${1:-}"
OUT_PREFIX="${2:-}"
THREADS="${3:-${SLURM_CPUS_PER_TASK:-$(nproc)}}"

if [[ -z "$INPUT_BAM" || -z "$OUT_PREFIX" ]]; then
    echo "Usage: $0 <input.bam> <output_prefix> [threads]"
    echo ""
    echo "  input.bam      Roche SBX Duplex aligned BAM"
    echo "  output_prefix   Prefix for output files (adds _R1.fastq.gz, _R2.fastq.gz)"
    echo "  threads         Samtools threads (default: nproc)"
    echo ""
    echo "Example:"
    echo "  $0 /fsx/control_data/roche/HG001.bam /fsx/scratch/roche_fq/HG001 16"
    exit 1
fi

if [[ ! -f "$INPUT_BAM" ]]; then
    echo "ERROR: BAM not found: $INPUT_BAM" >&2
    exit 1
fi

OUT_R1="${OUT_PREFIX}_R1.fastq.gz"
OUT_R2="${OUT_PREFIX}_R2.fastq.gz"

mkdir -p "$(dirname "$OUT_PREFIX")"
for f in "$OUT_R1" "$OUT_R2"; do
    if [[ -f "$f" ]]; then
        echo "ERROR: output already exists: $f" >&2
        exit 1
    fi
done

# Pick best available compressor
if command -v pigz &>/dev/null; then
    COMPRESS="pigz -p ${THREADS} -c"
elif command -v igzip &>/dev/null; then
    COMPRESS="igzip -c"
else
    COMPRESS="gzip -c"
fi

echo "============================================"
echo "extract_fastq_from_roche_bam.sh"
echo "============================================"
echo "Input BAM:   $INPUT_BAM"
echo "Output R1:   $OUT_R1"
echo "Output R2:   $OUT_R2"
echo "Threads:     $THREADS"
echo "Compressor:  ${COMPRESS%% *}"
echo "Started:     $(date)"
echo "============================================"

# ── Instrument fields (synthetic NovaSeq) ─────────────────────────────
INSTRUMENT="A00488"
RUN="1"
FLOWCELL="HRCHFQ001"
LANE="1"

# ── Helper: rewrite headers ───────────────────────────────────────────
# Reads interleaved FASTQ (R1, R2, R1, R2, ...) from samtools and writes
# two named pipes — one for R1 and one for R2.  The awk program assigns
# matching NovaSeq coordinates to each pair and sets read number 1 or 2.

TMPDIR="${TMPDIR:-/tmp}/roche_fq_$$"
mkdir -p "$TMPDIR"
cleanup() { rm -rf "$TMPDIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM HUP

FIFO_R1="$TMPDIR/r1.fifo"
FIFO_R2="$TMPDIR/r2.fifo"
mkfifo "$FIFO_R1" "$FIFO_R2"

# Compress FIFOs into final files in background
$COMPRESS < "$FIFO_R1" > "$OUT_R1" &
PID_Z1=$!
$COMPRESS < "$FIFO_R2" > "$OUT_R2" &
PID_Z2=$!

# ── Extract → rewrite → split ────────────────────────────────────────
# samtools collate + fastq ensures proper pairing.
# -N keeps /1 /2 suffixes so awk can distinguish mates.
samtools collate -u -@ "$THREADS" "$INPUT_BAM" "$TMPDIR/collate" \
| samtools fastq -@ "$THREADS" -N -0 /dev/null -s /dev/null - \
| awk -v inst="$INSTRUMENT" -v run="$RUN" -v fc="$FLOWCELL" -v lane="$LANE" \
      -v r1="$FIFO_R1" -v r2="$FIFO_R2" '
BEGIN { n = 0; rec = 0 }
{
    rec++
    line_in_rec = ((rec - 1) % 4) + 1
    buf[line_in_rec] = $0

    if (line_in_rec == 4) {
        # Determine read number from original header (last char /1 or /2)
        rn = 1
        if (match(buf[1], /\/2$/)) rn = 2
        if (rn == 1) n++

        tile = int(n / 100000000) + 1101
        x    = int((n / 10000) % 10000) + 1000
        y    = (n % 10000) + 1000
        hdr = sprintf("@%s:%s:%s:%s:%d:%d:%d %d:N:0:ACGTACGT", inst, run, fc, lane, tile, x, y, rn)

        dest = (rn == 1) ? r1 : r2
        print hdr > dest
        print buf[2] > dest
        print buf[3] > dest
        print buf[4] > dest
    }
}' -

# Wait for compressors to finish
wait $PID_Z1 $PID_Z2

# ── Verify ────────────────────────────────────────────────────────────
echo ""
for f in "$OUT_R1" "$OUT_R2"; do
    if [[ -f "$f" ]]; then
        SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        echo "$(basename "$f"): $SIZE bytes ($(echo "scale=2; $SIZE/1073741824" | bc) GiB)"
        echo "  First record:"
        zcat "$f" | head -4 | sed 's/^/    /'
    else
        echo "❌ ERROR: $f not created" >&2
        exit 1
    fi
done
echo ""
echo "✅ Done: $(date)"

