#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis

echo "=== CURRENT BRANCH ==="
git branch --show-current

echo "=== LAST COMMIT ==="
git log --oneline -1

echo "=== STAGED CHANGES ==="
git diff --cached --stat
echo "(end staged)"

echo "=== UNSTAGED CHANGES ==="
git diff --stat
echo "(end unstaged)"

echo "=== UNTRACKED FILES ==="
git ls-files --others --exclude-standard
echo "(end untracked)"

echo "=== MODIFIED FILES (working tree) ==="
git status --short
echo "(end status)"

