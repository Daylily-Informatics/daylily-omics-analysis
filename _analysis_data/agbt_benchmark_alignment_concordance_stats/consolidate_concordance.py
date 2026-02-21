#!/usr/bin/env python3
"""Consolidate concordance data from all test groups into a single TSV."""

import csv
import os
import re
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

TEST_GROUPS = [
    ("hio_cli", "hio_cli/giab_concordance_mqc.tsv", "hio_cli/alignstats_combo_mqc.tsv"),
    ("hio_fillin", "hio_fillin/giab_concordance_mqc.tsv", "hio_fillin/alignstats_combo_mqc.tsv"),
    ("hio_old", "hio_old/giab_concordance_mqc.tsv", "hio_old/alignstats_combo_mqc.tsv"),
    ("ilmn_all_downsamples_a", "ilmn_all_downsamples_a/giab_concordance_mqc.tsv", "ilmn_all_downsamples_a/alignstats_combo_mqc.tsv"),
    ("ilmn_hg003_ilmn_sentonly", "ilmn_hg003_ilmn_sentonly/giab_concordance_mqc.tsv", "ilmn_hg003_ilmn_sentonly/alignstats_combo_mqc.tsv"),
    ("ilmn_read_trim", "ilmn_read_trim/giab_concordance_mqc.tsv", "ilmn_read_trim/alignstats_combo_mqc.tsv"),
    ("ont_ds", "ont_ds/ont_patch/giab_concordance_mqc.tsv", "ont_ds/ont_patch/alignstats_combo_mqc.tsv"),
    ("pacbio_ds", "pacbio_ds/giab_concordance_mqc.tsv", "pacbio_ds/alignstats_combo_mqc.tsv"),
    ("roche_ds", "roche_ds/giab_concordance_mqc.tsv", "roche_ds/alignstats_combo_mqc.tsv"),
    ("roche_ds_fillinone", "roche_ds_fillinone/giab_concordance_mqc.tsv", "roche_ds_fillinone/alignstats_combo_mqc.tsv"),
    ("ultima_ds", "ultima_ds/giab_concordance_mqc.tsv", "ultima_ds/alignstats_combo_mqc.tsv"),
    ("ont_dv19", "ont_dv19/giab_concordance_mqc.tsv", "ont_dv19/alignstats_combo_mqc.tsv"),
    ("ilmn_gatk_b", "ilmn_gatk_b/giab_concordance_mqc.tsv", "ilmn_gatk_b/alignstats_combo_mqc.tsv"),
    ("dragen_fullold", "dragen_fullold/giab_concordance_mqc.tsv", None),
]

ILMN_SOLO_ALIGNSTATS = os.path.join(BASE_DIR, "ilmn_hg003_ilmn_sentonly/alignstats_combo_mqc.tsv")
ONT_SOLO_ALIGNSTATS = os.path.join(BASE_DIR, "ont_ds/ont_patch/alignstats_combo_mqc.tsv")

HIO_PATTERN = re.compile(r"^HIO[ab]-.*-SR(\d+)x-ONT(\d+)x-")
HIO_OLD_PATTERN = re.compile(r"^HIOv1_HG003_")
COV_PATTERN = re.compile(r"HG003-(\d+)x")
READLEN_PATTERN = re.compile(r"HG003-\d+x-(\d+)bp-")

PRIMARY_SEQ_PLATFORM = {
    "hio_cli": "ILMN",
    "hio_fillin": "ILMN",
    "hio_old": "ILMN",
    "ilmn_all_downsamples_a": "ILMN",
    "ilmn_hg003_ilmn_sentonly": "ILMN",
    "ilmn_read_trim": "ILMN",
    "ont_ds": "ONT",
    "ont_dv19": "ONT",
    "pacbio_ds": "PacBio",
    "roche_ds": "Roche",
    "roche_ds_fillinone": "Roche",
    "ultima_ds": "Ultima",
    "ilmn_gatk_b": "ILMN",
    "dragen_fullold": "ILMN",
    "dragen_old": "ILMN",
}

SECONDARY_SEQ_PLATFORM = {
    "hio_cli": "ONT",
    "hio_fillin": "ONT",
    "hio_old": "ONT",
}

# Test groups where only HG003 samples should be kept
HG003_ONLY_GROUPS = {"hio_old", "dragen_fullold"}

# Genome build per test group (default: hg38)
# dragen uses ILMN proprietary pangenome; roche uses public pangenome
GENOME_BUILD = {
    "dragen_old": "pangenome-ilmn",
    "dragen_fullold": "pangenome-ilmn",
    "roche_ds": "pangenome-pub",
    "roche_ds_fillinone": "pangenome-pub",
}


def coverage_bin(value):
    """Bin a measured coverage value into standard buckets."""
    if value == 0:
        return 0
    if value < 2:
        return 1
    if value < 4:
        return 3
    if value < 6:
        return 5
    if value < 8:
        return 7
    if value < 12:
        return 10
    if value < 19.990:
        return 15
    if value < 30:
        return 25
    if value < 40:
        return 35
    if value < 50:
        return 45
    return 50


def load_alignstats(filepath):
    """Load alignstats → dict keyed by (sample_base, aligner) → (mean_cov, median_cov)."""
    result = {}
    with open(filepath, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            sample_full = row["sample"]
            aligner = row["aligner"]
            base = sample_full[:-(len(aligner) + 1)] if sample_full.endswith(f".{aligner}") else sample_full
            mean_cov = float(row["WgsCoverageMean"]) if row.get("WgsCoverageMean") else 0.0
            median_cov = float(row["WgsCoverageMedian"]) if row.get("WgsCoverageMedian") else 0.0
            result[(base, aligner)] = (mean_cov, median_cov)
    return result


def build_solo_lookup(filepath, prefix, aligner_filter):
    """Build target_cov(int) → (mean, median) lookup from solo alignstats."""
    result = {}
    for (base, aligner), (mean_cov, median_cov) in load_alignstats(filepath).items():
        if aligner != aligner_filter or not base.startswith(prefix):
            continue
        m = COV_PATTERN.search(base)
        if m:
            result[int(m.group(1))] = (mean_cov, median_cov)
    return result


def make_dragen_old_rows(header_fields):
    """Construct manual rows for dragen_old (20x, All, hg38, F=0.9983).

    The source files have identical data for 10x and 15x; we use one copy at 20x.
    """
    base = {k: "" for k in header_fields}
    base.update({
        "Sample": "dragen_old_HG003_20x",
        "VariantClass": "All",
        "ROI": "hg38",
        "Fscore": "0.9983",
        "Sensitivity-Recall": "0.9971",
        "Precision": "0.9994",
        "PPV": "0.9994",
        "FDR": "0.0006",
        "TP": "3820846",
        "FP": "2190",
        "FN": "11031",
        "TN": "",
        "TgtRegionSize": "",
        "Specificity": "",
        "AllVarMeanDP": "",
        "AltId": "",
        "CovBin": "-2",
        "Aligner": "dragen",
        "SNVCaller": "dragen",
        "mqc_id": "dragen_old_HG003_20x-dragen-dragen-All",
        "TestGroup": "dragen_old",
        "PrimarySeqPlatform": "ILMN",
        "SecondarySeqPlatform": "",
        "Primary_Tgt_Cov": 20,
        "Secondary_Tgt_Cov": 0,
        "Primary_MeasuredMeanCov": 20.0,
        "PrimaryCoverageBin": coverage_bin(20.0),
        "Secondary_MeasuredMeanCov": 0.0,
        "SecondaryCoverageBin": "",
        "Primary_MeasuredMedianCov": 20.0,
        "Secondary_MeasuredMedianCov": 0.0,
        "ReadLengthBP": "",
        "GenomeBuild": GENOME_BUILD.get("dragen_old", "hg38"),
    })
    return [base]


def main():
    output_path = os.path.join(BASE_DIR, "consolidated_concordance.tsv")
    ilmn_solo = build_solo_lookup(ILMN_SOLO_ALIGNSTATS, "I2-HG003-", "sent")
    ont_solo = build_solo_lookup(ONT_SOLO_ALIGNSTATS, "On1-HG003-", "ont")

    print(f"ILMN solo lookup: {len(ilmn_solo)} entries | ONT solo lookup: {len(ont_solo)} entries")
    for tag, lk in [("ILMN", ilmn_solo), ("ONT", ont_solo)]:
        for k, v in sorted(lk.items()):
            print(f"  {tag} {k}x -> mean={v[0]:.3f} median={v[1]:.1f}")

    new_cols = [
        "TestGroup", "PrimarySeqPlatform", "SecondarySeqPlatform",
        "Primary_Tgt_Cov", "Secondary_Tgt_Cov",
        "Primary_MeasuredMeanCov", "PrimaryCoverageBin",
        "Secondary_MeasuredMeanCov", "SecondaryCoverageBin",
        "Primary_MeasuredMedianCov", "Secondary_MeasuredMedianCov",
        "ReadLengthBP", "GenomeBuild",
    ]
    all_rows = []
    header = None

    for tg_name, conc_rel, align_rel in TEST_GROUPS:
        conc_path = os.path.join(BASE_DIR, conc_rel)
        if not os.path.exists(conc_path):
            print(f"SKIP: {conc_path} not found", file=sys.stderr)
            continue
        align_path = os.path.join(BASE_DIR, align_rel) if align_rel else None
        alignstats = load_alignstats(align_path) if align_path and os.path.exists(align_path) else {}

        with open(conc_path, "r") as f:
            reader = csv.DictReader(f, delimiter="\t")
            if header is None:
                header = list(reader.fieldnames) + new_cols
            n, miss, skip = 0, 0, 0
            for row in reader:
                sample, aligner = row["Sample"], row["Aligner"]

                # HG003-only filter for selected groups
                if tg_name in HG003_ONLY_GROUPS and "HG003" not in sample:
                    skip += 1
                    continue

                hio_m = HIO_PATTERN.match(sample)
                hio_old_m = HIO_OLD_PATTERN.match(sample)
                cov_m = COV_PATTERN.search(sample)

                # --- Determine target coverages ---
                if hio_m:
                    pri_tgt = int(hio_m.group(1))
                    sec_tgt = int(hio_m.group(2))
                elif hio_old_m:
                    # hio_old: force SR40x / ONT40x
                    pri_tgt = 40
                    sec_tgt = 40
                elif cov_m:
                    pri_tgt = int(cov_m.group(1))
                    sec_tgt = 0
                else:
                    pri_tgt = 0
                    sec_tgt = 0

                # --- dragen_fullold: assume 30x ---
                if tg_name == "dragen_fullold" and pri_tgt == 0:
                    pri_tgt = 30

                # --- Determine measured coverage ---
                if hio_m:
                    pri = ilmn_solo.get(pri_tgt, (0.0, 0.0))
                    sec = ont_solo.get(sec_tgt, None)
                    if sec is None:
                        # Extrapolate from linear trend (measured/target ≈ 0.52)
                        sec = (round(sec_tgt * 0.52, 6), round(sec_tgt * 0.52, 1))
                elif hio_old_m:
                    # Use the hio_old alignstats directly for secondary (ONT)
                    meas_ont = alignstats.get((sample, aligner))
                    pri = ilmn_solo.get(40, (0.0, 0.0))
                    sec = meas_ont if meas_ont else (0.0, 0.0)
                else:
                    meas = alignstats.get((sample, aligner))
                    if meas:
                        pri = meas
                    elif tg_name == "dragen_fullold":
                        # No alignstats; assume 30x measured
                        pri = (30.0, 30.0)
                    else:
                        pri = (0.0, 0.0)
                        miss += 1
                    sec = (0.0, 0.0)

                # --- Read length for ilmn_read_trim ---
                readlen = ""
                if tg_name == "ilmn_read_trim":
                    rl_m = READLEN_PATTERN.search(sample)
                    if rl_m:
                        readlen = rl_m.group(1)

                out = dict(row)
                out["TestGroup"] = tg_name
                out["PrimarySeqPlatform"] = PRIMARY_SEQ_PLATFORM.get(tg_name, "")
                out["SecondarySeqPlatform"] = SECONDARY_SEQ_PLATFORM.get(tg_name, "")
                out["Primary_Tgt_Cov"] = pri_tgt
                out["Secondary_Tgt_Cov"] = sec_tgt
                out["Primary_MeasuredMeanCov"] = round(pri[0], 6)
                out["PrimaryCoverageBin"] = coverage_bin(pri[0])
                out["Secondary_MeasuredMeanCov"] = round(sec[0], 6)
                out["SecondaryCoverageBin"] = coverage_bin(sec[0]) if sec[0] > 0 else ""
                out["Primary_MeasuredMedianCov"] = round(pri[1], 6)
                out["Secondary_MeasuredMedianCov"] = round(sec[1], 6)
                out["ReadLengthBP"] = readlen
                out["GenomeBuild"] = GENOME_BUILD.get(tg_name, "hg38")
                all_rows.append(out)
                n += 1
        suffix = f" ({miss} alignstats misses)" if miss else ""
        if skip:
            suffix += f" ({skip} non-HG003 skipped)"
        print(f"  {tg_name}: {n} rows{suffix}")

    # --- dragen_old: manual row construction ---
    dragen_old_rows = make_dragen_old_rows(header)
    all_rows.extend(dragen_old_rows)
    print(f"  dragen_old: {len(dragen_old_rows)} rows (manual)")

    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"\nWrote {output_path}")
    print(f"  Total rows: {len(all_rows)}  |  Columns: {len(header)}")


if __name__ == "__main__":
    main()

