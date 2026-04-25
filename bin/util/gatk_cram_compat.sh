#!/usr/bin/env bash
set -euo pipefail

# GATK/CRAM 3.1 compatibility shim.
# Detects input format; if CRAM v3.1, converts to BAM (default) or CRAM v3.0.
# Requires: htsfile, samtools. For CRAM ops: the exact reference FASTA.

usage() {
  cat <<'EOF'
Usage:
  gatk_cram_compat.sh --in IN.{bam|cram} --ref REF.fa [--mode {bam|cram30|stream}] [--threads N] [--out OUT]

Modes:
  bam     : If CRAM v3.1, write OUT (BAM) + index. If already BAM/≤3.0 CRAM, just echo the input path.
  cram30  : If CRAM v3.1, write OUT (CRAM v3.0) + .crai. Else echo input.
  stream  : If CRAM v3.1, create a named pipe BAM and print its path for streaming; caller must rm it.

Notes:
  - For CRAM operations, REF.fa (and .fai) must match the CRAM's reference.
  - Prints the path to the GATK-compatible file on stdout.
  - Does NOT overwrite existing OUT unless --out explicitly points to a non-existent file.
EOF
}

IN=""
REF=""
MODE="bam"
THREADS="${THREADS:-8}"
OUT=""

# --- args ---
while (( "$#" )); do
  case "$1" in
    --in) IN="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

# --- sanity ---
[[ -n "$IN" && -r "$IN" ]] || { echo "❌ --in missing/unreadable: $IN" >&2; exit 2; }
command -v htsfile >/dev/null || { echo "❌ htsfile not in PATH" >&2; exit 2; }
command -v samtools >/dev/null || { echo "❌ samtools not in PATH" >&2; exit 2; }

# detect format + version via htsfile
HTS_LINE="$(htsfile "$IN" 2>/dev/null || true)"
# Examples:
#   "reads.bam: BAM version 1 compressed sequence data"
#   "reads.cram: CRAM version 3.1 compressed sequence data"
HTS_DESC="$(printf "%s\n" "$HTS_LINE" | sed -E 's/^[^:]*:[[:space:]]*//')"
FMT="$(printf "%s\n" "$HTS_DESC" | awk '{print $1}')"
VER="$(printf "%s\n" "$HTS_DESC" | sed -nE 's/.*version[[:space:]]+([0-9.]+).*/\1/p')"

# Helper: print and exit with original file if already compatible
emit_original_and_exit() { printf "%s\n" "$IN"; exit 0; }

case "$FMT" in
  BAM)
    # Always compatible
    emit_original_and_exit
    ;;
  CRAM)
    # Need REF for any CRAM ops
    [[ -n "$REF" && -r "$REF" && -r "${REF}.fai" ]] || {
      echo "❌ CRAM detected; require --ref REF.fa and REF.fa.fai" >&2; exit 2; }

    # If version is empty, assume old/compatible
    if [[ -z "${VER:-}" ]]; then
      emit_original_and_exit
    fi

    # Compare "3.1" vs "3.0" lexically by fields
    MAJ="${VER%%.*}"; MIN="${VER#*.}"
    if (( MAJ > 3 || (MAJ == 3 && MIN >= 1) )); then
      # CRAM 3.1+ → fix according to MODE
      case "$MODE" in
        bam)
          if [[ -z "$OUT" ]]; then OUT="${IN%.*}.for_gatk.bam"; fi
          [[ ! -e "$OUT" ]] || { echo "❌ OUT exists: $OUT" >&2; exit 3; }
          samtools view -@ "$THREADS" -b -T "$REF" -o "$OUT" "$IN"
          samtools index -@ "$THREADS" "$OUT"
          printf "%s\n" "$OUT"
          ;;
        cram30)
          if [[ -z "$OUT" ]]; then OUT="${IN%.cram}.v3.0.cram"; fi
          [[ ! -e "$OUT" ]] || { echo "❌ OUT exists: $OUT" >&2; exit 3; }
          samtools view -@ "$THREADS" -C -T "$REF" --output-fmt-option version=3.0 \
            -o "$OUT" "$IN"
          samtools index -@ "$THREADS" "$OUT"
          printf "%s\n" "$OUT"
          ;;
        stream)
          # Named pipe for tools that don't require an index
          if [[ -z "$OUT" ]]; then OUT="${IN%.*}.stream.bam"; fi
          [[ -e "$OUT" ]] && rm -f "$OUT"
          mkfifo "$OUT"
          # background producer; caller must rm $OUT after use
          ( samtools view -@ "$THREADS" -b -T "$REF" "$IN" > "$OUT" ) &
          printf "%s\n" "$OUT"
          ;;
        *)
          echo "❌ Unknown --mode: $MODE (use bam|cram30|stream)" >&2; exit 2;;
      esac
    else
      # CRAM ≤3.0 → compatible
      emit_original_and_exit
    fi
    ;;
  *)
    echo "❌ Unrecognized format from htsfile: $HTS_LINE" >&2
    exit 2
    ;;
esac
