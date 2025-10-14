#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  fqfetch.sh <samples.txt|smn_fetch_table.tsv> <out_dir> [--tsv] [--nygc-fallback] [--only-manifest] [--parallel N]

Modes:
  - Plain list: one SampleID per line
  - TSV mode:  --tsv  (expects first column header "SampleID")

Flags:
  --nygc-fallback   Also query PRJEB31736 (NYGC 30x PCR-free) for CRAM/BAM if no FASTQs
  --only-manifest   Write per-sample URL manifests but do not download
  --parallel N      Number of samples to process concurrently (default 3)

Subcommand (internal):
  fqfetch.sh one <sample> <out_dir> <nygc_fallback(0|1)> <only_manifest(0|1)>
USAGE
}

ENA_BASE="https://www.ebi.ac.uk/ena/portal/api/search"

ena_fastq_q() {
  local s="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,library_strategy,library_layout,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA_BASE" "$s"
}
ena_nygc_q() {
  local s="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,bam_ftp,submitted_ftp,cram_ftp,cram_index_ftp,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20project_accession%%3D%%22PRJEB31736%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA_BASE" "$s"
}
phase3_dir() {
  printf "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/%s/sequence_read/\n" "$1"
}

# ---- subcommand: one sample ----
if [[ "${1:-}" == "one" ]]; then
  sample="$2"; out="$3"; nygc="${4:-0}"; only="${5:-0}"

  mkdir -p "$out/$sample"
  manf="$out/$sample/urls.txt"
  : > "$manf"

  # 1) FASTQs via ENA (fastq_ftp has R1;R2)
  q1="$(ena_fastq_q "$sample")"
  curl -fsSL "$q1" 2>/dev/null | awk -F'\t' 'NR>1 && $2!=""{gsub(/;/,"\n",$2); print $2}' \
    | sed 's#^#ftp://#' >> "$manf" || true

  # 2) Optional fallback: NYGC PRJEB31736 CRAM/BAM
  if [[ "$nygc" == "1" ]] && ! grep -q '[[:graph:]]' "$manf"; then
    q2="$(ena_nygc_q "$sample")"
    curl -fsSL "$q2" 2>/dev/null | awk -F'\t' 'NR>1{
      for(i=1;i<=NF;i++){
        if ($i ~ /_ftp$/ && $i!="") {gsub(/;/,"\n",$i); print $i}
      }}' | sed 's#^#ftp://#' >> "$manf" || true
  fi

  # 3) Last resort: list Phase3 directory for *_1/_2.filt.fastq.gz
  if ! grep -q '[[:graph:]]' "$manf"; then
    p3="$(phase3_dir "$sample")"
    curl -fsSL "$p3" 2>/dev/null | grep -oE 'ERR[0-9]+_[12]\.filt\.fastq\.gz' | sort -u \
      | awk -v P="$p3" '{print P $1}' >> "$manf" || true
  fi

  # dedupe
  awk 'NF && !seen[$0]++' "$manf" > "$manf.tmp" && mv "$manf.tmp" "$manf"

  # stop here if only manifest
  if [[ "$only" == "1" ]]; then
    [[ -s "$manf" ]] || echo "WARN: $sample — no public URLs found" >&2
    exit 0
  fi

  # choose downloader
  if command -v aria2c >/dev/null 2>&1; then
    ( cd "$out/$sample" && aria2c -c -x16 -s16 --auto-file-renaming=false --allow-overwrite=true -i "$manf" )
  elif command -v wget >/dev/null 2>&1; then
    ( cd "$out/$sample" && wget -c -i "$manf" )
  else
    echo "ERROR: need aria2c or wget" >&2
    exit 3
  fi
  exit 0
fi

# ---- main mode ----
if [[ "$#" -lt 2 ]]; then usage; exit 2; fi
INPUT="$1"; OUT="$2"; shift 2

IS_TSV=0; NYGC_FALLBACK=0; ONLY_MANIFEST=0; PARALLEL=3
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tsv) IS_TSV=1 ;;
    --nygc-fallback) NYGC_FALLBACK=1 ;;
    --only-manifest) ONLY_MANIFEST=1 ;;
    --parallel) PARALLEL="${2:-3}"; shift ;;
    *) echo "WARN: unknown flag $1" >&2 ;;
  esac
  shift
done

mkdir -p "$OUT"

# Build null-delimited list of SampleIDs
if [[ "$IS_TSV" == "1" ]]; then
  # first column named SampleID
  mapfile -d '' samples < <(awk -F'\t' 'NR==1{if($1!="SampleID"){exit 9}} NR>1 && $1!=""{print $1}' "$INPUT" | tr -d '\r' | awk 'NF' | sed 's/$/\0/')
else
  mapfile -d '' samples < <(awk 'NF && $0!~/^#/' "$INPUT" | tr -d '\r' | sed 's/$/\0/')
fi

# Launch workers with null-delimited xargs; pass fixed args plus sample at the end
printf '%s' "${samples[@]}" | xargs -0 -n1 -P "$PARALLEL" \
  bash -c 'script="$0"; out="$1"; nygc="$2"; only="$3"; sample="$4"; "$script" one "$sample" "$out" "$nygc" "$only"' \
  "$0" "$OUT" "$NYGC_FALLBACK" "$ONLY_MANIFEST"
