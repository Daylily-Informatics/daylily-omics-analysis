#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   fqfetch_30x.sh <samples.txt> <out_dir> [--parallel N]
# samples.txt: one SampleID per line (e.g., NA19360)

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

ENA='https://www.ebi.ac.uk/ena/portal/api/search'
FIELDS='run_accession,first_public,instrument_model,cram_ftp,cram_index_ftp,submitted_ftp'
q_for() {
  # PRJEB31736 only; human; returns CRAM/CRAI if present
  samp="$1"
  printf "%s?result=read_run&format=tsv&limit=0&fields=%s&query=sample_alias%%3D%%22%s%%22%%20AND%%20project_accession%%3D%%22PRJEB31736%%22%%20AND%%20tax_eq(9606)\n" \
    "$ENA" "$FIELDS" "$samp"
}

fetch_one() {
  samp="$1"
  sdir="$OUT/$samp"
  mkdir -p "$sdir"
  man="$sdir/urls_30x.txt"
  : > "$man"

  # Query ENA
  curl -fsSL "$(q_for "$samp")" \
  | awk -F'\t' 'NR>1{
      # prefer cram_ftp and cram_index_ftp; fallback to submitted_ftp if it contains cram/bam
      if($4!=""){gsub(/;/,"\n",$4); print $4}
      if($5!=""){gsub(/;/,"\n",$5); print $5}
      if($6!="" ){gsub(/;/,"\n",$6); print $6}
    }' \
  | sed 's#^#ftp://#' \
  | awk 'NF' \
  | sort -u > "$man"

  if [ ! -s "$man" ]; then
    echo "[$samp] No PRJEB31736 CRAM/CRAI URLs found." >&2
    return 0
  fi

  echo "[$samp] downloading CRAM/CRAI..."
  parallel -j8 --bar \
    'wget -c --no-verbose --show-progress --directory-prefix='"$sdir"' --no-hsts {}' \
    :::: "$man"

  # Optional: rename canonical -> SampleID.final.cram if a single CRAM present
  n=$(grep -Ei '\.cram$' "$man" | wc -l | tr -d ' ')
  if [ "$n" = "1" ]; then
    src=$(grep -Ei '\.cram$' "$man" | sed 's#.*/##')
    [ -f "$sdir/$src" ] && ln -sf "$src" "$sdir/${samp}.final.cram" && \
                          [ -f "$sdir/${src}.crai" ] && ln -sf "${src}.crai" "$sdir/${samp}.final.cram.crai" || true
  fi

  echo "[$samp] done."
}

export ENA FIELDS OUT
export -f fetch_one q_for

mapfile -t SAMPLES < <(awk 'NF && $0!~/^#/' "$IN" | sort -u)
printf "%s\n" "${SAMPLES[@]}" | parallel -j"$PAR" --eta fetch_one {}
echo "All PRJEB31736 downloads complete → $OUT/"
