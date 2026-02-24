#!/usr/bin/env python3
"""Rename dhiom -> dhiomr in refactored smk file (case-sensitive)."""
import sys

fpath = sys.argv[1]

with open(fpath, 'r') as f:
    content = f.read()

count_lower = content.count('dhiom')
count_upper = content.count('DHIOM')

# Replace uppercase first, then lowercase.
# Since file has no 'dhiomr' yet, single pass is safe.
new_content = content.replace('DHIOM', 'DHIOMR').replace('dhiom', 'dhiomr')

# Safety checks
assert 'dhiomrr' not in new_content, "Double replacement detected!"
assert 'DHIOMRR' not in new_content, "Double replacement detected!"
assert 'SENTDHIO_CHRMS' in new_content, "SENTDHIO_CHRMS was incorrectly modified!"
assert "config['sentdhio']" in new_content, "config sentdhio was incorrectly modified!"

with open(fpath, 'w') as f:
    f.write(new_content)

count_lower_after = new_content.count('dhiomr')
count_upper_after = new_content.count('DHIOMR')

print("Replaced %d lowercase 'dhiom' -> 'dhiomr' (now %d occurrences)" % (count_lower, count_lower_after))
print("Replaced %d uppercase 'DHIOM' -> 'DHIOMR' (now %d occurrences)" % (count_upper, count_upper_after))
print("SENTDHIO_CHRMS preserved: %s" % ('SENTDHIO_CHRMS' in new_content))
print("Done.")

