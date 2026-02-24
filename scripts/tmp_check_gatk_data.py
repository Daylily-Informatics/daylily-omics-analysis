#!/usr/bin/env python3
"""Quick check: what data exists for sbwa+gatk @ 30x giabHC."""
import csv

TSV = "_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv"
with open(TSV) as f:
    for row in csv.DictReader(f, delimiter="\t"):
        if (row["ROI"] == "giabHC"
            and row["Aligner"] == "sent"       # sent → sbwa display
            and row["SNVCaller"] == "gatk"
            and row["PrimaryCoverageBin"] == "35"):
            print(f"VC={row['VariantClass']:12s}  "
                  f"Prec={row['Precision']:>12s}  "
                  f"Recall={row['Sensitivity-Recall']:>12s}  "
                  f"Fscore={row['Fscore']:>12s}  "
                  f"TG={row['TestGroup']}")

