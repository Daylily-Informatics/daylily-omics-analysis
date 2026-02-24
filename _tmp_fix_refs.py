#!/usr/bin/env python3
"""Systematic rename of hybrid pipeline config keys and prefixes.

Usage:
  python3 _tmp_fix_refs.py <file> <mode>

Modes:
  ilmn_pb  - sentdhipm -> sentdhipmr, sentdhio -> sentdhipmr
  ug_pb    - sentdhupm -> sentdhupmr, sentdhuo -> sentdhupmr
  ug_ont   - sentdhuom -> sentdhuomr, sentdhuo -> sentdhuomr (careful: overlap)
"""
import sys

fp = sys.argv[1]
mode = sys.argv[2]

with open(fp) as f:
    c = f.read()

before_len = len(c)

if mode == "ilmn_pb":
    # No substring overlap between sentdhipm and sentdhio
    # CAPS variables first (longer before shorter)
    c = c.replace("SENTDHIPM_CHRMS_TRANSFER", "SENTDHIPMR_CHRMS_TRANSFER")
    c = c.replace("SENTDHIPM_CHRMS", "SENTDHIPMR_CHRMS")
    c = c.replace("ALIGNERS_DHIPM", "ALIGNERS_DHIPMR")
    c = c.replace("_dhipm_tmp", "_dhipmr_tmp")
    # Main prefix rename (sentdhipm -> sentdhipmr) in one pass
    c = c.replace("sentdhipm", "sentdhipmr")
    # Fix wrong config refs: config["sentdhio"] -> config["sentdhipmr"]
    c = c.replace('config["sentdhio"]', 'config["sentdhipmr"]')
    c = c.replace("config['sentdhio']", "config['sentdhipmr']")
    check_old = ["sentdhipm[^r]", "sentdhio[^m]", "SENTDHIPM_CHRMS[^_T]", "ALIGNERS_DHIPM[^R]"]
    verify_bad = lambda line: ("sentdhio" in line and "sentdhipmr" not in line) or \
                              ("sentdhipm" in line and "sentdhipmr" not in line)

elif mode == "ug_pb":
    # No substring overlap between sentdhupm and sentdhuo
    c = c.replace("SENTDHUPM_CHRMS_TRANSFER", "SENTDHUPMR_CHRMS_TRANSFER")
    c = c.replace("SENTDHUPM_CHRMS", "SENTDHUPMR_CHRMS")
    c = c.replace("ALIGNERS_DHUPM", "ALIGNERS_DHUPMR")
    # Main prefix rename
    c = c.replace("sentdhupm", "sentdhupmr")
    # Fix wrong config refs: config["sentdhuo"] -> config["sentdhupmr"]
    c = c.replace('config["sentdhuo"]', 'config["sentdhupmr"]')
    c = c.replace("config['sentdhuo']", "config['sentdhupmr']")
    # Also fix SENTDHUO_CHRMS if present
    c = c.replace("SENTDHUO_CHRMS_TRANSFER", "SENTDHUPMR_CHRMS_TRANSFER")
    c = c.replace("SENTDHUO_CHRMS", "SENTDHUPMR_CHRMS")
    verify_bad = lambda line: ("sentdhuo" in line and "sentdhupmr" not in line) or \
                              ("sentdhupm" in line and "sentdhupmr" not in line)

elif mode == "ug_ont":
    # CAREFUL: sentdhuom contains sentdhuo as substring
    # Step 1: CAPS variables (no overlap issues)
    c = c.replace("SENTDHUO_CHRMS_TRANSFER", "SENTDHUOMR_CHRMS_TRANSFER")
    c = c.replace("SENTDHUO_CHRMS", "SENTDHUOMR_CHRMS")
    c = c.replace("ALIGNERS_DHUOM", "ALIGNERS_DHUOMR")
    # Step 2: Main prefix rename - sentdhuom -> sentdhuomr (single pass, safe)
    c = c.replace("sentdhuom", "sentdhuomr")
    # Step 3: Fix remaining config refs using specific quoted patterns
    # After step 2, sentdhuomr exists. config["sentdhuo"] won't match inside
    # config["sentdhuomr"] because the closing "] is at different positions.
    c = c.replace('config["sentdhuo"]', 'config["sentdhuomr"]')
    c = c.replace("config['sentdhuo']", "config['sentdhuomr']")
    verify_bad = lambda line: ("sentdhuo" in line and "sentdhuomr" not in line)

else:
    print(f"Unknown mode: {mode}")
    sys.exit(1)

with open(fp, "w") as f:
    f.write(c)

# Verify
with open(fp) as f:
    v = f.read()

remaining = 0
for i, line in enumerate(v.split("\n"), 1):
    if verify_bad(line):
        remaining += 1
        print(f"  REMAINING L{i}: {line.strip()}")

print(f"Mode: {mode}")
print(f"File: {fp}")
print(f"Size: {before_len} -> {len(v)} bytes")
print(f"Remaining bad refs: {remaining}")

