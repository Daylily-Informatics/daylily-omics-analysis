import sys
import csv

# Read command-line arguments
infile = sys.argv[1]
outfile = sys.argv[2]

with open(infile, newline="") as in_handle:
    reader = csv.DictReader(in_handle, delimiter="\t")
    fieldnames = reader.fieldnames or []
    output_fieldnames = ["combined_rule", *fieldnames, "rule_prefix", "rule_suffix"]
    rows = []

    for row in reader:
        rule = row.get("rule", "")
        sample = row.get("sample", "")
        rule_prefix, sep, rule_suffix = rule.partition(".")
        row["combined_rule"] = f"{rule}-{sample}"
        row["rule_prefix"] = rule_prefix
        row["rule_suffix"] = rule_suffix if sep else ""
        rows.append(row)

with open(outfile, "w", newline="") as out_handle:
    writer = csv.DictWriter(
        out_handle,
        fieldnames=output_fieldnames,
        delimiter="\t",
        lineterminator="\n",
    )
    writer.writeheader()
    writer.writerows(rows)
