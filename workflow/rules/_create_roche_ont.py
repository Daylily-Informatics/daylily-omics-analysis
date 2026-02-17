#!/usr/bin/env python3
"""Script to create sent_hybrid_roche_ont.smk from sent_hybrid_ug_ont_modular.smk"""
import re

with open("workflow/rules/sent_hybrid_ug_ont_modular.smk", "r") as f:
    content = f.read()

# Replacements for Roche+ONT workflow
replacements = [
    ("Ultima + ONT", "Roche + ONT"),
    ("Ultima+ONT", "Roche+ONT"),
    ("Ultima Genomics", "Roche"),
    ("Ultima short-read", "Roche short-read"),
    ("Ultima CRAM", "Roche CRAM"),
    ("Ultima reads", "Roche reads"),
    ("sentdhuom", "sentdhro"),
    ("SENTDHUO_CHRMS", "SENTDHRO_CHRMS"),
    ("ALIGNERS_DHUOM", "ALIGNERS_DHRO"),
    ('config["sentdhuo"]', 'config["sentdhro"]'),
    ("config['sentdhuo']", "config['sentdhro']"),
    ('ALIGNERS_DHRO = ["ug"]', 'ALIGNERS_DHRO = ["roche"]'),
    ("ug_cram", "roche_cram"),
    ("ug_crai", "roche_crai"),
    # Update docstring
    ("Caller code: sentdhro (Sentieon DNAscope Hybrid Roche+ONT Modular)",
     "Caller code: sentdhro (Sentieon DNAscope Hybrid Roche+ONT Modular)"),
    ('Uses HybridUltimaONT model bundle', 'Uses HybridUltimaONT1.1 model bundle (no Roche-specific model)'),
    ('Uses ALIGNERS_DHRO = ["ug"]', 'Uses ALIGNERS_DHRO = ["roche"]'),
]

for old, new in replacements:
    content = content.replace(old, new)

with open("workflow/rules/sent_hybrid_roche_ont.smk", "w") as f:
    f.write(content)

print("Created workflow/rules/sent_hybrid_roche_ont.smk")

