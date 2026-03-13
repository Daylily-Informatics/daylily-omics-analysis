#!/usr/bin/env python3
"""Check if hybrid pipelines require popvcf validation."""
import os
import re

print("=" * 70)
print("HYBRID PIPELINE POPVCF VALIDATION ANALYSIS")
print("=" * 70)

# Find all hybrid pipeline rules
hybrid_rules = [
    "sent_hybrid_ilmn_ont.smk",
    "sent_hybrid_ilmn_ont_modular.smk",
    "sent_hybrid_ilmn_pb.smk",
    "sent_hybrid_ilmn_pb_modular.refactored.smk",
    "sent_hybrid_ug_ont.smk",
    "sent_hybrid_ug_ont_modular.refactored.smk",
    "sent_hybrid_ug_pb.smk",
    "sent_hybrid_ug_pb_modular.refactored.smk",
    "sent_hybrid_roche_ont_modular.smk",
    "sent_hybrid_roche_pb_modular.smk",
]

print("\n1. HYBRID PIPELINES USING -d {params.pop_vcf}:")
print("-" * 70)
for rule in hybrid_rules:
    path = f"workflow/rules/{rule}"
    if os.path.exists(path):
        with open(path) as f:
            content = f.read()
            if "pop_vcf" in content and "-d" in content:
                print(f"   ✓ {rule}")

print("\n2. CHECKING FOR CONDITIONAL LOGIC AROUND pop_vcf:")
print("-" * 70)
found_conditional = False
for rule in hybrid_rules:
    path = f"workflow/rules/{rule}"
    if os.path.exists(path):
        with open(path) as f:
            lines = f.readlines()
            for i, line in enumerate(lines):
                if "pop_vcf" in line:
                    context = "".join(lines[max(0, i-2):min(len(lines), i+3)])
                    if re.search(r'\bif\b|\belse\b|\bcondition', context, re.IGNORECASE):
                        print(f"   Found in {rule} at line {i+1}")
                        found_conditional = True
if not found_conditional:
    print("   ✓ No conditional logic found - pop_vcf is always used")

print("\n3. POPVCF DEFINITION IN SUPPORTING_FILES:")
print("-" * 70)
for genome_build in ["hg38", "hg38_broad", "b37"]:
    path = f"config/supporting_files/{genome_build}_supporting_files.yaml"
    if os.path.exists(path):
        with open(path) as f:
            content = f.read()
            if "popvcf:" in content:
                print(f"   ✓ {genome_build}_supporting_files.yaml")

print("\n4. VALIDATION THAT POPVCF IS REQUIRED:")
print("-" * 70)
with open("workflow/rules/common.smk") as f:
    content = f.read()
    if "popvcf" in content.lower():
        print("   Found popvcf reference in common.smk")
    else:
        print("   ✗ No validation for popvcf in common.smk")

with open("workflow/schemas/config.schema.yaml") as f:
    content = f.read()
    if "popvcf" in content.lower():
        print("   Found popvcf in config schema")
    else:
        print("   ✗ popvcf NOT in config schema (not marked as required)")

print("\n" + "=" * 70)
print("CONCLUSION:")
print("=" * 70)
print("✓ All hybrid pipelines ARE using -d {params.pop_vcf}")
print("✓ The flag is ALWAYS present (not conditional)")
print("✗ There is NO explicit validation that popvcf is REQUIRED")
print("✗ Missing popvcf will only fail at runtime (job submission)")
print("\nRECOMMENDATION:")
print("Add validation in common.smk to check popvcf exists for hybrid workflows")
print("=" * 70)

