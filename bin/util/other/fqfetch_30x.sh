#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   fqfetch_30x.sh <samples.txt> <out_dir> [--parallel N]
# samples.txt: one ID per line (NA#####, HG#####)

PAR=4
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <samples.txt> <out_dir> [--parallel N]" >&2; exit 2
fi
IN="$1"; OUT="${2%/}"; shift 2
while [ "$#" -gt 0 ]; do
  case "$1" in
    --parallel) PAR="${2:-4}"; shift;;
    *) echo "WARN: unknown flag $1" >&2;;
  esac
  shift
done

mkdir -p "$OUT"

ENA='https://www.ebi.ac.uk/ena/portal/api/search'
FIELDS='run_accession,first_public,instrument_model,cram_ftp,cram_index_ftp,submitted_ftp'

q_for() {
  # PRJEB31736 only; human
  samp="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=%s&query=sample_alias%%3D%%22%s%%22%%20AND%%20project_accession%%3D%%22PRJEB31736%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA" "$FIELDS" "$samp"
}

fetch_one() {
  samp="$1"
  case "$samp" in
    NA[0-9]*|HG[0-9]*) : ;;
    *) echo "[skip] bad token: '$samp'"; return 0;;
  esac

  sdir="$OUT/$samp"
  mkdir -p "$sdir"
  man="$sdir/urls_30x.txt"
  : > "$man"

  url="$(q_for "$samp")"
  tsv="$(curl -fsSL "$url" 2>/dev/null || true)"
  if [ -z "$tsv" ]; then
    echo "[warn] $samp: ENA returned empty/400 for: $url" >&2
  fi

  printf "%s\n" "$tsv" | awk -F'\t' 'NR>1{
      if($4!=""){gsub(/;/,"\n",$4); print $4}
      if($5!=""){gsub(/;/,"\n",$5); print $5}
      if($6!="" ){gsub(/;/,"\n",$6); print $6}
    }' \
  | sed 's#^#ftp://#' \
  | awk 'NF' | sort -u > "$man"

  if [ ! -s "$man" ]; then
    echo "[$samp] No PRJEB31736 CRAM/CRAI URLs found."
    return 0
  fi

  echo "[$samp] downloading CRAM/CRAI..."
  parallel -j8 --bar \
    'wget -c --no-verbose --show-progress --directory-prefix='"$sdir"' --no-hsts {}' \
    :::: "$man"

  # Symlink canonical final name if exactly 1 CRAM
  n=$(grep -Ei '\.cram$' "$man" | wc -l | tr -d ' ')
  if [ "$n" = "1" ]; then
    src=$(grep -Ei '\.cram$' "$man" | sed 's#.*/##')
    [ -f "$sdir/$src" ] && ln -sf "$src" "$sdir/${samp}.final.cram"
    [ -f "$sdir/${src}.crai" ] && ln -sf "${src}.crai" "$sdir/${samp}.final.cram.crai" || true
  fi

  echo "[$samp] done."
}

export ENA FIELDS OUT
export -f fetch_one q_for

# Clean the sample list inline: drop quotes/CRLF, keep only NA/HG IDs
mapfile -t SAMPLES < <(sed -E 's/[\"\r]//g' "$IN" \
  | awk 'NF && $1 ~ /^(NA|HG)[0-9]+$/' \
  | sort -u)

printf "%s\n" "${SAMPLES[@]}" | parallel -j"$PAR" --eta fetch_one {}

echo "All PRJEB31736 downloads complete → $OUT/"
