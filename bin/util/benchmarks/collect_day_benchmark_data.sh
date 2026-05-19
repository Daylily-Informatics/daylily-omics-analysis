#!/usr/bin/env bash

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo " run from the DAY_ROOT dir, optionally passing the build name as the first arg"
    exit 0
fi

build=${1:-${DAY_GENOME_BUILD:-}}

if [[ "$build" == "" ]]; then
    echo "No build specified, please pass [hg38|hg38_broad|b37] or set DAY_GENOME_BUILD with dy-g [hg38|b37] and rerun"
    exit 1
fi

summary="results/day/$build/reports/benchmarks_summary.tsv"
mkdir -p "$(dirname "$summary")"

if [[ -e "$summary" ]]; then
    mv "$summary" "$summary.old"
else
    echo "no file to move"
fi

shopt -s nullglob
bench_dirs=(results/day/"$build"/benchmarks results/day/"$build"/*/benchmarks)
bench_files=()
for bench_dir in "${bench_dirs[@]}"; do
    [[ -d "$bench_dir" ]] || continue
    while IFS= read -r -d '' bench_file; do
        bench_files+=("$bench_file")
    done < <(find "$bench_dir" -maxdepth 1 -type f -name "*.bench.tsv" -print0)
done
shopt -u nullglob

if [[ "${#bench_files[@]}" -eq 0 ]]; then
    echo "No benchmark files found under results/day/$build/{benchmarks,*/benchmarks}" >&2
    exit 1
fi

{
    printf "sample  rule  "
    head -n 1 "${bench_files[0]}"
    printf "%s\n" "${bench_files[@]}" | sort | while IFS= read -r bench_file; do
        printf "%sXyyyX" "$bench_file"
        tail -n 1 "$bench_file"
    done
} > "$summary"

perl -pi -e 's/XyyyX/\t/g' "$summary"
perl -pi -e 's/(^.*\/results\/day\/)(.*)(\/benchmarks\/.*_[0-9]\.)(.*)(\.bench\.tsv)(.*$)/$2\t$4\t$6/g;' "$summary"
perl -pi -e 's/ +/\t/g' "$summary"
perl -pi -e 's/(^.*\/benchmarks\/)(.+?\.)(.*)(\.bench\.tsv)/$2\t$3/g;' "$summary"
perl -pi -e 's/_DBC0_0\.//g;' "$summary"
echo "

Benchmark Collection Complete, see results/day/$build/reports/benchmarks_summary.tsv"
