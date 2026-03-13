#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== Find sentieon-cli package location ==="
$SSH $HN 'source ~/.bashrc 2>/dev/null; conda activate sentieon_v0.3 2>/dev/null || true; pip show sentieon-cli 2>/dev/null | head -20'

echo ""
echo "=== Find dnascope-hybrid main Python file ==="
$SSH $HN 'source ~/.bashrc 2>/dev/null; conda activate sentieon_v0.3 2>/dev/null || true; python -c "import sentieon_cli; import os; print(os.path.dirname(sentieon_cli.__file__))" 2>/dev/null'

echo ""
echo "=== List sentieon_cli directory contents ==="
$SSH $HN 'source ~/.bashrc 2>/dev/null; conda activate sentieon_v0.3 2>/dev/null || true; DIR=$(python -c "import sentieon_cli; import os; print(os.path.dirname(sentieon_cli.__file__))" 2>/dev/null); find $DIR -name "*.py" -type f | sort'

echo ""
echo "=== Look for dnascope_hybrid or hybrid in file names ==="
$SSH $HN 'source ~/.bashrc 2>/dev/null; conda activate sentieon_v0.3 2>/dev/null || true; DIR=$(python -c "import sentieon_cli; import os; print(os.path.dirname(sentieon_cli.__file__))" 2>/dev/null); find $DIR -name "*hybrid*" -o -name "*dnascope*" | sort'

