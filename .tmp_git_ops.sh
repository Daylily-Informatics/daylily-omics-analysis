#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
echo "=== GIT LOG ==="
git log --oneline -5
echo "=== GIT STATUS ==="
git status --short
echo "=== GIT DIFF STAT ==="
git diff --stat
echo "=== DONE ==="

