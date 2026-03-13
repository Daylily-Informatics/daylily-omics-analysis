#!/bin/sh
cd "$(dirname "$0")/../../.." || exit 1
python3 .test_data/data/roche/_gen_coverage_series.py

