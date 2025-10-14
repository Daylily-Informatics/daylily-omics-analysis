#!/usr/bin/env bash
set -euo pipefail
mf="${1:?urls.txt path required}"
cd "$(dirname "$mf")"
parallel -j8 --halt now,fail=1 --joblog wget.jobs \
  'wget -c --tries=20 --timeout=60 --read-timeout=60 \
        --retry-connrefused --no-verbose --show-progress \
        --directory-prefix=. --no-hsts {}' \
  :::: "$(basename "$mf")"
