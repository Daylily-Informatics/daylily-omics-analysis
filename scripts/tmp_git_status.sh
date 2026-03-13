#!/bin/bash
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
echo "=== GIT LOG ==="
git log --oneline -8
echo ""
echo "=== GIT STATUS ==="
git status --short
echo ""
echo "=== BRANCH ==="
git branch --show-current

