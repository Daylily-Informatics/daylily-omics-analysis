#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
echo "=== GIT LOG ==="
git log --oneline -5
echo ""
echo "=== GIT STATUS ==="
git status --short
echo ""
echo "=== GIT DIFF STAT ==="
git diff --stat
echo ""
echo "=== DONE ==="

