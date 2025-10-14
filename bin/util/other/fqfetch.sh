#!/usr/bin/env sh
# fetch_fastqs.sh  — Fetch all R1/R2 FASTQs for NA/HG samples from ENA.
# Fallback (optional) to NYGC 30× CRAM/BAM when FASTQs aren’t provided.
# deps: curl, awk, sed, xargs, and aria2c OR wget
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <samples.txt|smn_fetch_table.tsv> <out_dir> [--tsv] [--nygc-fallback] [--only-manifest] [--parallel N]" >&2
  exit 2
fi

INPUT="$1"
OUT="$2"
shift 2

IS_TSV=0
NYGC_FALLBACK=0
ONLY_MANIFEST=0
PARALLEL=3

while [ "$#" -gt 0 ]; do
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

# pick downloader
if command -v aria2c >/dev/null 2>&1; then
  DL="aria2c -c -x16 -s16 --auto-file-renaming=false --allow-overwrite=true -i -"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -c -i -"
else
  echo "ERROR: need aria2c or wget" >&2
  exit 3
fi

ENA_BASE='https://www.ebi.ac.uk/ena/portal/api/search'
phase3_dir() { printf "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/%s/sequence_read/\n" "$1"; }

ena_fastq_q() {
  samp="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,library_strategy,library_layout,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20tax_eq(9606)\n" "$ENA_BASE" "$samp"
}
ena_nygc_q() {
  samp="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=run_accession,fastq_ftp,bam_ftp,submitted_ftp,cram_ftp,cram_index_ftp,instrument_model&query=sample_alias%%3D%%22%s%%22%%20AND%%20project_accession%%3D%%22PRJEB31736%%22%%20AND%%20tax_eq(9606)\n" "$ENA_BASE" "$samp"
}

# read sample IDs
get_samples() {
  if [ "$IS_TSV" -eq 1 ]; then
    # assume column named SampleID (first row header)
    awk -F'\t' 'NR>1 && $1!="" {print $1}' "$INPUT" | tr -d '\r'
  else
    awk 'NF && $0!~ /^#/' "$INPUT" | tr -d '\r'
  fi
}

fetch_one() {
  S="$1"
  SOUT="$OUT/$S"
  mkdir -p "$SOUT"
  MAN="$SOUT/urls.txt"
  : > "$MAN"

  # 1) ENA FASTQs (R1/R2 in fastq_ftp)
  Q1="$(ena_fastq_q "$S")"
  TSV="$(curl -fsSL "$Q1" || true)"
  # collect ftp paths
  printf "%s\n" "$TSV" | awk -F'\t' 'NR>1 && $2!=""{gsub(/;/,"\n",$2); print $2}' \
    | sed 's#^#ftp://#' >> "$MAN"

  # 2) If none and fallback requested, query PRJEB31736 for CRAM/BAM/submitted_ftp
  if [ "$NYGC_FALLBACK" -eq 1 ] && ! grep -q '[[:graph:]]' "$MAN"; then
    Q2="$(ena_nygc_q "$S")"
    TSV2="$(curl -fsSL "$Q2" || true)"
    printf "%s\n" "$TSV2" | awk -F'\t' 'NR>1{
      for(i=1;i<=NF;i++){
        if ($i ~ /_ftp$/ && $i!="") { gsub(/;/,"\n",$i); print $i }
      }}' | sed 's#^#ftp://#' >> "$MAN"
  fi

  # 3) Final fallback: try Phase3 directory listing (sometimes shows filtered fastqs)
  if ! grep -q '[[:graph:]]' "$MAN"; then
    P3="$(phase3_dir "$S")"
    LIST="$(curl -fsSL "$P3" || true)"
    printf "%s\n" "$LIST" | \
      grep -oE 'ERR[0-9]+_[12]\.filt\.fastq\.gz' | sort -u | \
      awk -v P="$P3" '{print P $1}' >> "$MAN" || true
  fi

  # de-dupe
  awk 'NF && !seen[$0]++' "$MAN" > "$MAN.tmp" && mv "$MAN.tmp" "$MAN"

  if [ "$ONLY_MANIFEST" -eq 1 ]; then
    if [ ! -s "$MAN" ]; then
      echo "WARN: $S — no public URLs found" >&2
    else
      echo "WROTE manifest: $MAN"
    fi
    return 0
  fi

  if [ ! -s "$MAN" ]; then
    echo "WARN: $S — no public URLs found" >&2
    return 0
  fi

  # download
  echo "==> $S ($(wc -l < "$MAN") objects)"
  ( cd "$SOUT" && $DL )
}

export OUT ENA_BASE DL ONLY_MANIFEST NYGC_FALLBACK
export -f fetch_one 2>/dev/null || true

# GNU xargs and BSD xargs both support -P
get_samples | xargs -I{} -P "${PARALLEL}" sh -c 'fetch_one "$@"' _ {}
