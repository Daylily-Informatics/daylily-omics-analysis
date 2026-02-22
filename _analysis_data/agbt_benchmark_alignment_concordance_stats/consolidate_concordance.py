#!/usr/bin/env python3
"""Consolidate concordance data from all test groups into a single TSV."""

import csv
import os
import re
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DATA_DIR = os.path.join(BASE_DIR, "src_data")

# (test_group_name, concordance_tsv_relative_to_SRC_DATA_DIR, alignstats_relative_or_None)
TEST_GROUPS = [
    ("agbt_ont", "agbt_ont/giab_concordance_mqc.tsv", "agbt_ont/alignstats_combo_mqc.tsv"),
    ("agbt_ug", "agbt_ug/giab_concordance_mqc.tsv", "agbt_ug/alignstats_combo_mqc.tsv"),
    ("dark_horses2", "dark_horses2/giab_concordance_mqc.tsv", "dark_horses2/alignstats_combo_mqc.tsv"),
    ("hio_cli", "hio_cli/giab_concordance_mqc.tsv", "hio_cli/alignstats_combo_mqc.tsv"),
    ("hio_fillin", "hio_fillin/giab_concordance_mqc.tsv", "hio_fillin/alignstats_combo_mqc.tsv"),
    ("hio_old", "hio_old/giab_concordance_mqc.tsv", "hio_old/alignstats_combo_mqc.tsv"),
    ("hiom_jem", "hiom_jem/giab_concordance_mqc.tsv", "hiom_jem/alignstats_combo_mqc.tsv"),
    ("huo_old", "huo_old/giab_concordance_mqc.tsv", "huo_old/alignstats_combo_mqc.tsv"),
    ("ilmn_all_downsamples_a", "ilmn_all_downsamples_a/giab_concordance_mqc.tsv", "ilmn_all_downsamples_a/alignstats_combo_mqc.tsv"),
    ("ilmn_gatk_b", "ilmn_gatk_b/giab_concordance_mqc.tsv", "ilmn_gatk_b/alignstats_combo_mqc.tsv"),
    ("ilmn_hg003_ilmn_sentonly", "ilmn_hg003_ilmn_sentonly/giab_concordance_mqc.tsv", "ilmn_hg003_ilmn_sentonly/alignstats_combo_mqc.tsv"),
    ("ilmn_hg003_prod", "ilmn_hg003_prod/giab_concordance_mqc.tsv", "ilmn_hg003_prod/alignstats_combo_mqc.tsv"),
    ("ilmn_read_trim", "ilmn_read_trim/giab_concordance_mqc.tsv", "ilmn_read_trim/alignstats_combo_mqc.tsv"),
    ("ont_ds", "ont_ds/ont_patch/giab_concordance_mqc.tsv", "ont_ds/ont_patch/alignstats_combo_mqc.tsv"),
    ("ont_dv19", "ont_dv19/giab_concordance_mqc.tsv", "ont_dv19/alignstats_combo_mqc.tsv"),
    ("pacbio_ds", "pacbio_ds/giab_concordance_mqc.tsv", "pacbio_ds/alignstats_combo_mqc.tsv"),
    ("pangenome_3_and_30x", "pangenome_3_and_30x/giab_concordance_mqc.tsv", None),
    ("pb_hg003_prod", "pb_hg003_prod/giab_concordance_mqc.tsv", "pb_hg003_prod/alignstats_combo_mqc.tsv"),
    ("roche_ds_a", "roche_ds_a/giab_concordance_mqc.tsv", "roche_ds_a/alignstats_combo_mqc.tsv"),
    ("roche_ds_b", "roche_ds_b/giab_concordance_mqc.tsv", "roche_ds_b/alignstats_combo_mqc.tsv"),
    ("roche_ds_c", "roche_ds_c/giab_concordance_mqc.tsv", "roche_ds_c/alignstats_combo_mqc.tsv"),
    ("roche_hg003_coverage_series", "roche_hg003_coverage_series/giab_concordance_mqc.tsv", "roche_hg003_coverage_series/alignstats_combo_mqc.tsv"),
    ("sentdhiomr", "sentdhiomr_results/other_reports/giab_concordance_mqc.tsv", "sentdhiomr_results/other_reports/alignstats_combo_mqc.tsv"),
    ("ultima_ds", "ultima_ds/giab_concordance_mqc.tsv", "ultima_ds/alignstats_combo_mqc.tsv"),
]

ILMN_SOLO_ALIGNSTATS = os.path.join(SRC_DATA_DIR, "ilmn_hg003_ilmn_sentonly/alignstats_combo_mqc.tsv")
ONT_SOLO_ALIGNSTATS = os.path.join(SRC_DATA_DIR, "ont_ds/ont_patch/alignstats_combo_mqc.tsv")

HIO_PATTERN = re.compile(r"^HIO[ab]-.*-SR(\d+)x-ONT(\d+)x-")
HIO_OLD_PATTERN = re.compile(r"^HIOv1_HG003_")
HUO_PATTERN = re.compile(r"^HUOv1_")
COV_PATTERN = re.compile(r"HG003-(\d+)x")
COV_FRACTIONAL_PATTERN = re.compile(r"HG003-(\d+)p(\d+)xa?-")  # e.g. 2p5xa → 2.5
READLEN_PATTERN = re.compile(r"HG003-\d+x-(\d+)bp-")
# Pangenome samples: R30x-HG003-D0-... or R3x-HG003-D0-...
PANGENOME_COV_PATTERN = re.compile(r"^R(\d+)x-HG00[23]-")

# Column name mapping: files with SNPClass/CmpFootprint → VariantClass/ROI
COLUMN_REMAP = {
    "SNPClass": "VariantClass",
    "CmpFootprint": "ROI",
}

PRIMARY_SEQ_PLATFORM = {
    "agbt_ont": "ONT",
    "agbt_ug": "Ultima",
    "dark_horses2": "ILMN",
    "hio_cli": "ILMN",
    "hio_fillin": "ILMN",
    "hio_old": "ILMN",
    "hiom_jem": "ILMN",
    "huo_old": "Ultima",
    "ilmn_all_downsamples_a": "ILMN",
    "ilmn_gatk_b": "ILMN",
    "ilmn_hg003_ilmn_sentonly": "ILMN",
    "ilmn_hg003_prod": "ILMN",
    "ilmn_read_trim": "ILMN",
    "ont_ds": "ONT",
    "ont_dv19": "ONT",
    "pacbio_ds": "PacBio",
    "pangenome_3_and_30x": "ILMN",
    "pb_hg003_prod": "PacBio",
    "roche_ds_a": "Roche",
    "roche_ds_b": "Roche",
    "roche_ds_c": "Roche",
    "roche_hg003_coverage_series": "Roche",
    "sentdhiomr": "ILMN",
    "ultima_ds": "Ultima",
}

SECONDARY_SEQ_PLATFORM = {
    "hio_cli": "ONT",
    "hio_fillin": "ONT",
    "hio_old": "ONT",
    "hiom_jem": "ONT",
    "huo_old": "ONT",
    "sentdhiomr": "ONT",
}

# Genome build per test group (default: hg38)
# roche uses public pangenome; pangenome_3_and_30x uses HPRC pangenome
GENOME_BUILD = {
    "roche_ds_a": "pangenome-pub",
    "roche_ds_b": "pangenome-pub",
    "roche_ds_c": "pangenome-pub",
    "roche_hg003_coverage_series": "pangenome-pub",
    "pangenome_3_and_30x": "pangenome-hprc",
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
        conc_path = os.path.join(SRC_DATA_DIR, conc_rel)
        if not os.path.exists(conc_path):
            print(f"SKIP: {conc_path} not found", file=sys.stderr)
            continue
        align_path = os.path.join(SRC_DATA_DIR, align_rel) if align_rel else None
        alignstats = load_alignstats(align_path) if align_path and os.path.exists(align_path) else {}

        with open(conc_path, "r") as f:
            reader = csv.DictReader(f, delimiter="\t")
            if header is None:
                header = list(reader.fieldnames) + new_cols
            n, miss = 0, 0
            for row in reader:
                # --- Remap column names if needed (SNPClass→VariantClass, etc.) ---
                for old_key, new_key in COLUMN_REMAP.items():
                    if old_key in row and new_key not in row:
                        row[new_key] = row.pop(old_key)

                sample, aligner = row["Sample"], row["Aligner"]

                hio_m = HIO_PATTERN.match(sample)
                hio_old_m = HIO_OLD_PATTERN.match(sample)
                huo_m = HUO_PATTERN.match(sample)
                cov_m = COV_PATTERN.search(sample)
                cov_frac_m = COV_FRACTIONAL_PATTERN.search(sample)
                pangenome_m = PANGENOME_COV_PATTERN.match(sample)

                # --- Determine target coverages ---
                if hio_m:
                    pri_tgt = int(hio_m.group(1))
                    sec_tgt = int(hio_m.group(2))
                elif hio_old_m:
                    # hio_old: force SR40x / ONT40x
                    pri_tgt = 40
                    sec_tgt = 40
                elif huo_m:
                    # huo_old: full-depth, no coverage in name; use alignstats
                    pri_tgt = 0
                    sec_tgt = 0
                elif pangenome_m:
                    # Pangenome samples: R30x-HG003-... → 30x
                    pri_tgt = int(pangenome_m.group(1))
                    sec_tgt = 0
                elif cov_frac_m:
                    # Fractional coverage: e.g. 2p5xa → 2.5
                    pri_tgt = float(f"{cov_frac_m.group(1)}.{cov_frac_m.group(2)}")
                    sec_tgt = 0
                elif cov_m:
                    pri_tgt = int(cov_m.group(1))
                    sec_tgt = 0
                else:
                    pri_tgt = 0
                    sec_tgt = 0

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
                elif huo_m:
                    # huo_old: use alignstats directly for primary (ONT-aligned)
                    meas = alignstats.get((sample, aligner))
                    pri = meas if meas else (0.0, 0.0)
                    sec = (0.0, 0.0)
                    if not meas:
                        miss += 1
                else:
                    meas = alignstats.get((sample, aligner))
                    if meas:
                        pri = meas
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
        print(f"  {tg_name}: {n} rows{suffix}")

    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"\nWrote {output_path}")
    print(f"  Total rows: {len(all_rows)}  |  Columns: {len(header)}")


if __name__ == "__main__":
    main()

