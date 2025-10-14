#!/usr/bin/env bash
set -euo pipefail

ENA_BASE="https://www.ebi.ac.uk/ena/portal/api/search"

# Resolve absolute path to this script for worker calls
script_abs="$0"
case "$script_abs" in
  /*) : ;;
  *) script_abs="$(cd "$(dirname "$script_abs")" && pwd)/$(basename "$script_abs")" ;;
esac

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
phase3_dir() { printf "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/%s/sequence_read/\n" "$1"; }

# Subcommand: process one sample
if [[ "${1:-}" == "one" ]]; then
  sample="$2"; out="$3"; nygc="${4:-0}"; only="${5:-0}"

  mkdir -p "$out/$sample"
  manf="$out/$sample/urls.txt"; : > "$manf"

  # 1) FASTQs (R1/R2 in fastq_ftp)
  curl -fsSL "$(ena_fastq_q "$sample")" 2>/dev/null \
    | awk -F'\t' 'NR>1 && $2!=""{gsub(/;/,"\n",$2); print $2}' \
    | sed 's#^#ftp://#' >> "$manf" || true

  # 2) Optional fallback to NYGC PRJEB31736 (CRAM/BAM)
  if [[ "$nygc" == "1" ]] && ! grep -q '[[:graph:]]' "$manf"; then
    curl -fsSL "$(ena_nygc_q "$sample")" 2>/dev/null \
      | awk -F'\t' 'NR>1{for(i=1;i<=NF;i++){ if($i ~ /_ftp$/ && $i!=""){gsub(/;/,"\n",$i); print $i}}}' \
      | sed 's#^#ftp://#' >> "$manf" || true
  fi

  # 3) Last resort: list Phase3 dir for *_1/_2.filt.fastq.gz
  if ! grep -q '[[:graph:]]' "$manf"; then
    p3="$(phase3_dir "$sample")"
    curl -fsSL "$p3" 2>/dev/null \
      | grep -oE 'ERR[0-9]+_[12]\.filt\.fastq\.gz' | sort -u \
      | awk -v P="$p3" '{print P $1}' >> "$manf" || true
  fi

  awk 'NF && !seen[$0]++' "$manf" > "$manf.tmp" && mv "$manf.tmp" "$manf"

  [[ "$only" == "1" ]] && { [[ -s "$manf" ]] || echo "WARN: $sample — no public URLs"; exit 0; }

  if command -v aria2c >/dev/null 2>&1; then
    ( cd "$out/$sample" && aria2c -c -x16 -s16 --auto-file-renaming=false --allow-overwrite=true -i "$manf" )
  elif command -v wget >/dev/null 2>&1; then
    ( cd "$out/$sample" && wget -c -i "$manf" )
  else
    echo "ERROR: need aria2c or wget" >&2; exit 3
  fi
  exit 
