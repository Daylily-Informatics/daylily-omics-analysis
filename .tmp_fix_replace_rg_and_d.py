#!/usr/bin/env python3
"""Fix --replace_rg tab escaping and -d flag position in both HIOM smk files."""
import re

def fix_file(path, fix_d_flag=False):
    with open(path) as f:
        content = f.read()
    original = content

    # Fix 1: --replace_rg lines: \tSM: -> \\tSM: and \tLR: -> \\tLR:
    # These are in Snakemake shell blocks where \t becomes literal tab.
    # We need \\t so bash gets \t string, which sentieon interprets as tab.
    # Only fix lines that have --replace_rg (avoid touching -R "@RG\\t..." which is already correct)
    old_pattern = r'(--replace_rg [^"]*)"'
    lines = content.split('\n')
    fixed_lines = []
    replace_rg_fixes = 0
    d_flag_fixes = 0

    i = 0
    while i < len(lines):
        line = lines[i]

        # Fix --replace_rg \t -> \\t (only for \t that are NOT already \\t)
        if '--replace_rg' in line and '\\tSM:' in line:
            # Check if already escaped (\\t vs \t)
            # If we see \tSM but NOT \\tSM, we need to fix
            # But since the file has \\tSM in the raw text... let's be precise.
            # In the raw file text, the current state is:  \tSM:  (single backslash)
            # We want:  \\tSM:  (double backslash)
            # Python reads the file literally, so \t in file = \t in string (two chars: \ and t)
            # We want \\t in file = \\t in string (three chars: \, \, t)
            if '\\\\tSM:' not in line and '\\tSM:' in line:
                line = line.replace('\\tSM:', '\\\\tSM:')
                line = line.replace('\\tLR:', '\\\\tLR:')
                replace_rg_fixes += 1

        # Fix -d before --algo DNAscope: swap lines
        if fix_d_flag and '-d {params.pop_vcf}' in line.strip():
            next_line = lines[i + 1] if i + 1 < len(lines) else ''
            if '--algo DNAscope' in next_line:
                # Swap the two lines
                fixed_lines.append(next_line)
                fixed_lines.append(line)
                d_flag_fixes += 1
                i += 2
                continue

        fixed_lines.append(line)
        i += 1

    content = '\n'.join(fixed_lines)

    if content != original:
        with open(path, 'w') as f:
            f.write(content)
        print(f"  {path}: {replace_rg_fixes} --replace_rg \\t fixes, {d_flag_fixes} -d flag position fixes")
    else:
        print(f"  {path}: no changes needed")


print("=== Fixing STD file (with -d flag fix) ===")
fix_file("workflow/rules/sent_hybrid_ilmn_ont_modular.smk", fix_d_flag=True)

print("=== Fixing REF file ===")
fix_file("workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk", fix_d_flag=False)

# Verify
print("\n=== Verification ===")
for path in [
    "workflow/rules/sent_hybrid_ilmn_ont_modular.smk",
    "workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk",
]:
    with open(path) as f:
        lines = f.readlines()
    bad_rg = sum(1 for l in lines if '--replace_rg' in l and '\\tSM:' in l and '\\\\tSM:' not in l)
    good_rg = sum(1 for l in lines if '--replace_rg' in l and '\\\\tSM:' in l)
    bad_d = sum(1 for i, l in enumerate(lines) if '-d {params.pop_vcf}' in l
                and i + 1 < len(lines) and '--algo DNAscope' in lines[i + 1])
    print(f"  {path.split('/')[-1]}:")
    print(f"    --replace_rg with single \\t (BAD): {bad_rg}")
    print(f"    --replace_rg with \\\\t (GOOD): {good_rg}")
    print(f"    -d before --algo (BAD): {bad_d}")

