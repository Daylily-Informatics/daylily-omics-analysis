#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
conda run -n DAY-EC python3 scripts/tmp_hiom_jem_summary.py

