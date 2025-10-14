#!/usr/bin/env bash
set -euo pipefail

# Fetch FASTQs for specific 1kGP Phase 3 samples:
# 1) Prefer ENA "read_run" records (fastq_ftp + fastq_md5).
# 2) Fallback to 1000 Genomes Phase 3 'sequence_read' filtered FASTQs (*_1.filt.fastq.gz + *_2.filt.fastq.gz).
#
# Requires: curl, awk, sed, grep, md5sum (or md5 on macOS), and either aria2c or wget.
# Nice-to-have: parallel (ignored if absent).

# ---------- Config ----------
DEST_ROOT="${DEST_ROOT:-./fastq/1kgp_phase3}"
DRY_RUN="${DRY_RUN:-0}"             # 1 = list what we'd download, 0 = download
MAX_JOBS="${MAX_JOBS:-6}"           # parallel fetches with aria2c
USE_ENA_FIRST="${USE_ENA_FIRST:-1}" # 1 = try ENA first
USE_PHASE3_FALLBACK="${USE_PHASE3_FALLBACK:-1}"

# Samples from your table
declare -a SAMPLES=(
  "NA19360"
  "HG02697"
  "NA19177"
  "NA21526"
  "NA20760"
  "HG01773"
  "NA19429"
  "NA19122"
  "NA19123"
)

# Phase 3 base URLs (all share the same pattern)
declare -A PHASE3_URL=(
  [NA19360]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA19360/sequence_read/"
  [HG02697]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG02697/sequence_read/"
  [NA19177]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA19177/sequence_read/"
  [NA21526]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA21526/sequence_read/"
  [NA20760]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA20760/sequence_read/"
  [HG01773]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG01773/sequence_read/"
  [NA19429]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA19429/sequence_read/"
  [NA19122]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA19122/sequence_read/"
  [NA19123]="http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/NA19123/sequence_read/"
)

# ---------- Helpers ----------
have() { command -v "$1" >/dev/null 2>&1; }

md5_check() {
  local file="$1" want="$2"
  if [[ -z "$want" || ! -s "$file" ]]; then return 0; fi
  local got
  if have md5sum; then
    got="$(md5sum "$file" | awk '{print $1}')"
  elif have md5; then
    got="$(md5 -q "$file")"
  else
    echo "[warn] No md5 tool; skipping checksum for $file" >&2
    return 0
  fi
  if [[ "$got" != "$want" ]]; then
    echo "[fail] MD5 mismatch: $file (got $got, want $want)" >&2
    return 1
  fi
  return 0
}

fetch_urls() {
  # Fetch a list of URLs to a target dir, optionally verifying md5 if provided.
  # Args: dest_dir, url[, md5]
  local dest_dir="$1"; shift
  mkdir -p "$dest_dir"

  # If aria2c exists, batch them; else wget individually
  if have aria2c; then
    local input_list
    input_list="$(mktemp)"
    # For aria2c, we can add checksum lines as well.
    while (( "$#" )); do
      local url="$1"; shift
      local md5="${1:-}"; [[ -n "${md5:-}" ]] && shift || true
      local fname
      fname="$(basename "$url")"
      {
        echo "$url"
        echo "  dir=$dest_dir"
        echo "  out=$fname"
        [[ -n "$md5" ]] && echo "  checksum=md5=$md5"
      } >> "$input_list"
    done
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "=== DRY-RUN aria2c batch ==="
      cat "$input_list"
      rm -f "$input_list"
      return 0
    fi
    aria2c -c -x 8 -s 8 -j "$MAX_JOBS" --auto-file-renaming=false --allow-overwrite=false --input-file="$input_list"
    rm -f "$input_list"
  else
    while (( "$#" )); do
      local url="$1"; shift
      local md5="${1:-}"; [[ -n "${md5:-}" ]] && shift || true
      local fname dest="$dest_dir/$(basename "$url")"
      if [[ "$DRY_RUN" == "1" ]]; then
        echo "DRY-RUN wget -> $dest"
        continue
      fi
      if [[ -s "$dest" ]]; then
        # verify if md5 available
        if [[ -n "$md5" ]]; then
          if md5_check "$dest" "$md5"; then
            echo "[ok] exists+md5: $dest"
            continue
          else
            echo "[warn] removing corrupt $dest and re-downloading"
            rm -f "$dest"
          fi
        else
          echo "[ok] exists: $dest"
          continue
        fi
      fi
      if have wget; then
        wget -c -O "$dest" "$url"
      else
        curl -L --fail --retry 5 --retry-delay 3 -C - -o "$dest" "$url"
      fi
      [[ -n "$md5" ]] && md5_check "$dest" "$md5"
    done
  fi
}

ena_urls_for_sample() {
  # Print tab-separated: URL<tab>MD5 (one line per file) for a sample alias
  local sample="$1"
  local q="sample_alias%3D%22${sample}%22%20AND%20tax_eq(9606)"
  local fields="run_accession,fastq_ftp,fastq_md5"
  local api="https://www.ebi.ac.uk/ena/portal/api/search?result=read_run&format=tsv&fields=${fields}&query=${q}"

  curl -s "$api" \
    | awk 'NR>1 {print $2 "\t" $3}' \
    | awk -F'\t' '{
         n=split($1,a,";"); m=split($2,b,";");
         for(i=1;i<=n;i++){
           url=a[i]; md=(i<=m?b[i]:"");
           if (url ~ /^ftp\./) { url="https://" url }
           print url "\t" md
         }
       }' \
    | grep -E '\.fastq\.gz(\.gpg)?$' || true
}

phase3_urls_for_sample() {
  # Parse the 1000G Phase 3 directory HTML listing and emit paired *_1.filt.fastq.gz + *_2.filt.fastq.gz URLs.
  local sample="$1"
  local base="${PHASE3_URL[$sample]:-}"
  [[ -z "$base" ]] && return 0

  # List all ERR subdirs and files, then pair 1/2 for same ERR
  local listing
  listing="$(curl -s "$base")"
  # Grab sub-ERR dirs
  echo "$listing" | grep -Eo 'ERR[0-9]+' | sort -u | while read -r err; do
    local subhtml
    subhtml="$(curl -s "${base}${err}/")"
    # find *filt.fastq.gz
    echo "$subhtml" \
      | grep -Eo "${err}_(1|2)\.filt\.fastq\.gz" \
      | sort -u \
      | while read -r fn; do
          echo "${base}${err}/${fn}"
        done
  done
}

download_sample() {
  local sample="$1"
  local outdir="$DEST_ROOT/$sample"
  mkdir -p "$outdir"

  local had_any=0
  local urls_md5=()

  if [[ "$USE_ENA_FIRST" == "1" ]]; then
    while IFS=$'\t' read -r url md5; do
      [[ -z "${url:-}" ]] && continue
      urls_md5+=("$url" "${md5:-}")
      had_any=1
    done < <(ena_urls_for_sample "$sample" || true)
  fi

  if [[ "$had_any" -eq 0 && "$USE_PHASE3_FALLBACK" == "1" ]]; then
    # Phase 3 fallback (no md5s there)
    while read -r url; do
      [[ -z "$url" ]] && continue
      urls_md5+=("$url" "")
      had_any=1
    done < <(phase3_urls_for_sample "$sample" || true)
  fi

  if [[ "$had_any" -eq 0 ]]; then
    echo "[warn] No FASTQ URLs found for $sample (ENA empty and Phase3 fallback yielded nothing)."
    return 0
  fi

  fetch_urls "$outdir" "${urls_md5[@]}"
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--dest DIR] [--dry-run] [--only SAMPLE,...] [--no-ena] [--no-phase3] [--jobs N]

Env overrides:
  DEST_ROOT=$DEST_ROOT
  DRY_RUN=$DRY_RUN
  MAX_JOBS=$MAX_JOBS

Examples:
  # Download all samples to ./fastq/1kgp_phase3
  $(basename "$0")

  # Dry-run (print what would be fetched)
  DRY_RUN=1 $(basename "$0")

  # Custom destination + limit to two samples
  $(basename "$0") --dest /fsx/1kgp_fastqs --only NA19360,NA19177

  # Skip ENA (force Phase 3 filt.fastq.gz)
  $(basename "$0") --no-ena

  # Skip Phase3 fallback (ENA only)
  $(basename "$0") --no-phase3
EOF
}

# ---------- CLI ----------
ONLY_LIST=""
while (( "$#" )); do
  case "$1" in
    --dest) shift; DEST_ROOT="${1:?}";;
    --dry-run) DRY_RUN=1;;
    --only) shift; ONLY_LIST="${1:?}";;
    --no-ena) USE_ENA_FIRST=0;;
    --no-phase3) USE_PHASE3_FALLBACK=0;;
    --jobs) shift; MAX_JOBS="${1:?}";;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
  shift
done

# Filter sample list if --only
if [[ -n "$ONLY_LIST" ]]; then
  IFS=',' read -r -a WANT <<<"$ONLY_LIST"
  declare -A wantmap=()
  for s in "${WANT[@]}"; do wantmap["$s"]=1; done
  filtered=()
  for s in "${SAMPLES[@]}"; do
    [[ "${wantmap[$s]:-}" == "1" ]] && filtered+=("$s")
  done
  SAMPLES=("${filtered[@]}")
fi

echo "[info] DEST_ROOT=$DEST_ROOT  DRY_RUN=$DRY_RUN  MAX_JOBS=$MAX_JOBS  ENA=$USE_ENA_FIRST  PHASE3=$USE_PHASE3_FALLBACK"

# Parallelize by sample if GNU parallel is available
if have parallel; then
  export -f ena_urls_for_sample phase3_urls_for_sample fetch_urls md5_check download_sample have
  export DEST_ROOT DRY_RUN MAX_JOBS USE_ENA_FIRST USE_PHASE3_FALLBACK
  printf "%s\n" "${SAMPLES[@]}" \
    | parallel -j "${MAX_JOBS}" --halt now,fail=1 download_sample {}
else
  for s in "${SAMPLES[@]}"; do
    download_sample "$s"
  done
fi

echo "[done] All requested samples processed."
