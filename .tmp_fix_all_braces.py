#!/usr/bin/env python3
"""Fix all Snakemake brace/escaping issues in both HIOM workflow files."""

import sys

def fix_file(filepath, label):
    with open(filepath, 'r') as f:
        content = f.read()
    original = content
    fixes = []

    # Fix 1: LR awk blocks - single braces → double braces
    old_awk = """| awk '
            $1=="@RG"{
                for(i=1;i<=NF;i++){
                    if($i~/^ID:/){
                        sub(/^ID:/,"",$i);
                        print $i
                    }
                }
            }')"""

    new_awk = """| awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')"""

    count = content.count(old_awk)
    content = content.replace(old_awk, new_awk)
    if count:
        fixes.append(f"  Fixed {count} LR awk blocks (single → double braces)")

    # Fix 2: ${rgid} → ${{rgid}} in shell blocks
    count = content.count('${rgid}')
    content = content.replace('${rgid}', '${{rgid}}')
    if count:
        fixes.append(f"  Fixed {count} ${{rgid}} → ${{{{rgid}}}} escapes")

    with open(filepath, 'w') as f:
        f.write(content)

    changed = content != original
    print(f"\n=== {label} ({filepath}) ===")
    if fixes:
        for f_ in fixes:
            print(f_)
    else:
        print("  No changes needed")
    print(f"  File {'MODIFIED' if changed else 'unchanged'}")
    return changed


# --- Standard file ---
changed_std = fix_file(
    'workflow/rules/sent_hybrid_ilmn_ont_modular.smk',
    'Standard HIOM'
)

# --- Refactored file ---
changed_ref = fix_file(
    'workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk',
    'Refactored HIOM'
)

# --- Fix config initialization in standard file ---
print("\n=== Config initialization (Standard file) ===")
with open('workflow/rules/sent_hybrid_ilmn_ont_modular.smk', 'r') as f:
    content = f.read()

old_config = '''SENTDHIOM_SAMPLE_SM = config.get("sentdhio", {}).get("sample_sm", "hybrid_sample")
SENTDHIOM_LR_READ_FILTER = config.get("sentdhio", {}).get("lr_read_filter", "")
SENTDHIOM_SR_READ_FILTER = config.get("sentdhio", {}).get("sr_read_filter", "")'''

new_config = '''# Ensure config keys exist for shell-block {config[sentdhio][...]} access
if "sentdhio" not in config:
    config["sentdhio"] = {}
config["sentdhio"].setdefault("sample_sm", "hybrid_sample")
config["sentdhio"].setdefault("lr_read_filter", "")
config["sentdhio"].setdefault("sr_read_filter", "")
SENTDHIOM_SAMPLE_SM = config["sentdhio"]["sample_sm"]
SENTDHIOM_LR_READ_FILTER = config["sentdhio"]["lr_read_filter"]
SENTDHIOM_SR_READ_FILTER = config["sentdhio"]["sr_read_filter"]'''

if old_config in content:
    content = content.replace(old_config, new_config)
    with open('workflow/rules/sent_hybrid_ilmn_ont_modular.smk', 'w') as f:
        f.write(content)
    print("  Fixed config initialization (setdefault pattern)")
else:
    print("  Already fixed or pattern not found")

# --- Add config init to refactored file ---
print("\n=== Config initialization (Refactored file) ===")
with open('workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk', 'r') as f:
    content = f.read()

marker = "# Aligner constraint: ONT for long reads"
config_block = """# Ensure config keys exist for shell-block {config[sentdhio][...]} access
if "sentdhio" not in config:
    config["sentdhio"] = {}
config["sentdhio"].setdefault("sample_sm", "hybrid_sample")
config["sentdhio"].setdefault("lr_read_filter", "")
config["sentdhio"].setdefault("sr_read_filter", "")

# Aligner constraint: ONT for long reads"""

if 'config["sentdhio"].setdefault' not in content:
    content = content.replace(marker, config_block)
    with open('workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk', 'w') as f:
        f.write(content)
    print("  Added config initialization block")
else:
    print("  Already has config initialization")

# --- Fix ${timestamp} in refactored file line 617 ---
print("\n=== Fix ${timestamp} (Refactored file) ===")
with open('workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk', 'r') as f:
    content = f.read()

old_ts = 'export TMPDIR="/dev/shm/sentdhiomr_s1_${timestamp}_$$"'
new_ts = 'export TMPDIR="/dev/shm/sentdhiomr_s1_${{timestamp}}_$$"'
if old_ts in content:
    content = content.replace(old_ts, new_ts)
    with open('workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk', 'w') as f:
        f.write(content)
    print("  Fixed ${timestamp} → ${{timestamp}}")
else:
    print("  Already fixed or not found")

print("\n=== ALL DONE ===")

