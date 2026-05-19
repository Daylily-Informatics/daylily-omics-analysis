#!/usr/bin/env bash

# Usage: ./fastq_qc.sh <skip> <R1_1.fastq(.gz)> <R2_1.fastq(.gz)> ...
# Example: ./fastq_qc.sh 10000 R1_1.fastq.gz R2_1.fastq R1_2.fastq.gz R2_2.fastq

set -euo pipefail

if [[ $# -lt 3 || $((($# - 1) % 2)) -ne 0 ]]; then
    echo "Usage: $0 <skip> <R1_1.fastq(.gz)> <R2_1.fastq(.gz)> ..."
    exit 1
fi

# Get the skip value and shift the arguments to get the file list
SKIP=$1
shift
if ! [[ "$SKIP" =~ ^[0-9]+$ ]] || [[ "$SKIP" -lt 1 ]]; then
    echo "skip must be a positive integer" >&2
    exit 1
fi

# Function to read FASTQ content.
fastq_reader() {
    local file=$1
    if [[ "$file" == *.gz ]]; then
        gzip -dc -- "$file"
    else
        cat -- "$file"
    fi
}

count_reads() {
    local file=$1
    fastq_reader "$file" | awk 'END { if (NR % 4 != 0) exit 2; print NR / 4 }'
}

first_read_name() {
    local file=$1
    fastq_reader "$file" | awk 'NR == 1 { print; exit }'
}

last_read_name() {
    local file=$1
    fastq_reader "$file" | awk 'NR % 4 == 1 { header=$0 } END { if (header == "") exit 2; print header }'
}

sampled_read_names() {
    local file=$1
    local skip=$2
    fastq_reader "$file" | awk -v skip="$skip" 'NR % 4 == 1 && (((NR - 1) / 4) % skip == 0) { print }'
}

normalize_read_name() {
    local raw=$1
    raw=${raw#@}
    raw=${raw%%[[:space:]]*}
    raw=${raw%/1}
    raw=${raw%/2}
    printf '%s\n' "$raw"
}

# Function to compare two FASTQ files
compare_fastq_pair() {
    local r1=$1
    local r2=$2

    local r1_count
    local r2_count
    r1_count=$(count_reads "$r1")
    r2_count=$(count_reads "$r2")

    if [[ "$r1_count" -ne "$r2_count" ]]; then
        echo "Mismatch: $r1 ($r1_count reads) and $r2 ($r2_count reads)"
        return 1
    fi

    local r1_first
    local r2_first
    local r1_last
    local r2_last
    r1_first=$(normalize_read_name "$(first_read_name "$r1")")
    r2_first=$(normalize_read_name "$(first_read_name "$r2")")
    r1_last=$(normalize_read_name "$(last_read_name "$r1")")
    r2_last=$(normalize_read_name "$(last_read_name "$r2")")

    if [[ "$r1_first" != "$r2_first" ]]; then
        echo "First read mismatch: $r1 has $r1_first; $r2 has $r2_first"
        return 1
    fi
    if [[ "$r1_last" != "$r2_last" ]]; then
        echo "Last read mismatch: $r1 has $r1_last; $r2 has $r2_last"
        return 1
    fi

    if ! diff -u <(sampled_read_names "$r1" "$SKIP" | while read -r read_name; do normalize_read_name "$read_name"; done) \
        <(sampled_read_names "$r2" "$SKIP" | while read -r read_name; do normalize_read_name "$read_name"; done) >/dev/null; then
        echo "Sampled read-order mismatch: $r1 and $r2 differ with skip=$SKIP"
        return 1
    fi

    echo "Paired correctly: $r1 and $r2 ($r1_count reads; first=$r1_first last=$r1_last)"
    return 0
}

status=0
while [[ $# -gt 0 ]]; do
    if ! compare_fastq_pair "$1" "$2"; then
        status=1
    fi
    shift 2
done

if [[ "$status" -eq 0 ]]; then
    echo "All FASTQ pairs passed QC."
else
    echo "Some FASTQ pairs failed QC. See above for details."
fi
exit "$status"
