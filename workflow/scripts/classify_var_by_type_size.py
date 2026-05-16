"""Classify vcfeval VCF records by simple variant type and size bins."""
import gzip
import os
import sys

if len(sys.argv) < 7:
    raise SystemExit(
        "usage: classify_var_by_type_size.py in_vcf call_class target_region_size "
        "count_out sample alt_name"
    )

in_vcf = sys.argv[1]
call_class = sys.argv[2]
tgt_region_size = sys.argv[3]
count_out = sys.argv[4]
sample_mg = sys.argv[5]
sample_coriel = sys.argv[6]


def _open_text(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "r")


def _transition(ref, alt):
    return {ref.upper(), alt.upper()} in ({"A", "G"}, {"C", "T"})


def _info_end(info):
    for item in info.split(";"):
        if item.startswith("END="):
            try:
                return int(item.split("=", 1)[1])
            except ValueError:
                return None
    return None


def _variant_class(ref, alts, pos, info):
    concrete_alts = [alt for alt in alts if alt and not alt.startswith("<")]
    if not concrete_alts:
        return "indel_gt50"

    if len(ref) == 1 and all(len(alt) == 1 for alt in concrete_alts):
        if all(_transition(ref, alt) for alt in concrete_alts):
            return "snp_ts"
        return "snp_tv"

    max_alt_len = max(len(alt) for alt in concrete_alts)
    end = _info_end(info)
    ref_span = max(1, (end - pos + 1) if end is not None else len(ref))

    if max_alt_len > len(ref):
        return "ins_50" if max_alt_len < 51 else "ins_gt50"
    if ref_span > max_alt_len:
        return "del_50" if ref_span < 51 else "del_gt50"

    indel_len = max(ref_span, max_alt_len)
    return "indel_50" if indel_len < 51 else "indel_gt50"


class_paths = {
    "snp_tv": f"{in_vcf}.X_tv_snp.vcf",
    "snp_ts": f"{in_vcf}.X_ts_snp.vcf",
    "del_50": f"{in_vcf}.X_del_50.vcf",
    "del_gt50": f"{in_vcf}.X_del_gt50.vcf",
    "ins_50": f"{in_vcf}.X_ins_50.vcf",
    "ins_gt50": f"{in_vcf}.X_ins_gt50.vcf",
    "indel_50": f"{in_vcf}.X_indel_50.vcf",
    "indel_gt50": f"{in_vcf}.X_indel_gt50.vcf",
}
counts = {key: 0 for key in class_paths}
headers = []
writers = {}

try:
    with _open_text(in_vcf) as in_fh:
        for line in in_fh:
            if line.startswith("#"):
                headers.append(line)
                continue
            if not writers:
                for key, path in class_paths.items():
                    writers[key] = open(path, "w")
                    writers[key].writelines(headers)
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8:
                continue
            pos = int(fields[1])
            ref = fields[3]
            alts = fields[4].split(",")
            info = fields[7]
            variant_class = _variant_class(ref, alts, pos, info)
            writers[variant_class].write(line)
            counts[variant_class] += 1
finally:
    if not writers:
        for key, path in class_paths.items():
            writers[key] = open(path, "w")
            writers[key].writelines(headers)
    for out_fh in writers.values():
        out_fh.close()

for path in class_paths.values():
    os.system(f"bgzip -f {path}")
    os.system(f"tabix -f {path}.gz")

with open(count_out, "w") as out_count_fh:
    out_count_fh.write(
        "Sample\tCallClass\tSNPts\tSNPtv\tIns50\tIns_gt50\tDel50\tDel_gt50\t"
        "Indel_50\tIndel_gt50\tTgtRegionSize\tAltName\n"
    )
    out_count_fh.write(
        "{sample}\t{call_class}\t{snp_ts}\t{snp_tv}\t{ins_50}\t{ins_gt50}\t"
        "{del_50}\t{del_gt50}\t{indel_50}\t{indel_gt50}\t{target}\t{alt}\n".format(
            sample=sample_mg,
            call_class=call_class,
            snp_ts=counts["snp_ts"],
            snp_tv=counts["snp_tv"],
            ins_50=counts["ins_50"],
            ins_gt50=counts["ins_gt50"],
            del_50=counts["del_50"],
            del_gt50=counts["del_gt50"],
            indel_50=counts["indel_50"],
            indel_gt50=counts["indel_gt50"],
            target=tgt_region_size,
            alt=sample_coriel,
        )
    )
