#!/usr/bin/env python3
"""Estimate human same-species contamination without a target sample genotype.

The scalar estimator integrates over the target sample genotype at each common
SNP using the population allele frequency from the marker panel. Optional donor
attribution uses candidate sample genotypes to explain the estimated
contaminating fraction, but the primary contamination estimate remains target
genotype-free.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import math
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


BASES = {"A", "C", "G", "T"}
DEFAULT_BASE_ERROR = 0.001
LIKELIHOOD_CI_DROP = 1.92


@dataclass(frozen=True)
class Site:
    chrom: str
    pos: int
    ref: str
    alt: str
    af: float

    @property
    def key(self) -> tuple[str, int]:
        return (self.chrom, self.pos)


@dataclass(frozen=True)
class CountRecord:
    site: Site
    ref_count: int
    alt_count: int
    other_count: int = 0

    @property
    def depth(self) -> int:
        return self.ref_count + self.alt_count


@dataclass(frozen=True)
class PileupChunk:
    region: str
    sites: list[Site]


@dataclass(frozen=True)
class ScalarEstimate:
    contamination_fraction: float
    ci_low: float
    ci_high: float
    log_likelihood: float
    null_log_likelihood: float
    site_count: int
    read_count: int
    mean_depth: float


@dataclass(frozen=True)
class CandidateProfile:
    sample_id: str
    genotypes: dict[tuple[str, int], float]


@dataclass(frozen=True)
class AttributionResult:
    total_contamination_fraction: float
    unknown_contamination_fraction: float
    donor_weights: dict[str, float]
    donor_log_likelihood_delta: dict[str, float]
    log_likelihood: float
    unknown_only_log_likelihood: float


def open_text(path: str | os.PathLike[str]):
    path_str = str(path)
    if path_str.endswith(".gz"):
        return gzip.open(path_str, "rt", encoding="utf-8")
    return open(path_str, encoding="utf-8")


def parse_af(info: str) -> float | None:
    for field in info.split(";"):
        if field.startswith("AF="):
            raw_value = field.split("=", 1)[1].split(",", 1)[0]
            try:
                af = float(raw_value)
            except ValueError:
                return None
            if 0.0 < af < 1.0:
                return af
            return None
    return None


def load_sites(
    sites_vcf: str | os.PathLike[str],
    *,
    min_af: float,
    max_af: float,
    max_sites: int = 0,
    require_pass: bool = False,
) -> list[Site]:
    sites: list[Site] = []
    with open_text(sites_vcf) as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8:
                continue
            chrom, pos_raw, _id, ref, alt, _qual, filt, info = fields[:8]
            ref = ref.upper()
            alt = alt.upper()
            if require_pass and filt not in {"PASS", "."}:
                continue
            if len(ref) != 1 or len(alt) != 1 or ref not in BASES or alt not in BASES:
                continue
            af = parse_af(info)
            if af is None or af < min_af or af > max_af:
                continue
            sites.append(Site(chrom=chrom, pos=int(pos_raw), ref=ref, alt=alt, af=af))
            if max_sites and len(sites) >= max_sites:
                break
    if not sites:
        raise ValueError(f"No usable biallelic AF sites found in {sites_vcf}")
    return sites


def parse_pileup_bases(bases: str, ref: str, alt: str) -> tuple[int, int, int]:
    ref_count = 0
    alt_count = 0
    other_count = 0
    i = 0
    while i < len(bases):
        char = bases[i]
        if char == "^":
            i += 2
            continue
        if char == "$":
            i += 1
            continue
        if char in "+-":
            match = re.match(r"[+-](\d+)", bases[i:])
            if match is None:
                i += 1
                continue
            length_text = match.group(1)
            i += 1 + len(length_text) + int(length_text)
            continue
        if char in ".,":  # reference match on forward/reverse strand
            ref_count += 1
        else:
            base = char.upper()
            if base == ref:
                ref_count += 1
            elif base == alt:
                alt_count += 1
            elif base in BASES:
                other_count += 1
        i += 1
    return ref_count, alt_count, other_count


def records_from_counts_tsv(path: str | os.PathLike[str]) -> list[CountRecord]:
    records: list[CountRecord] = []
    with open(path, newline="", encoding="utf-8") as handle:
        rows = (line for line in handle if line.strip() and not line.startswith("#"))
        reader = csv.DictReader(rows, delimiter="\t")
        for row in reader:
            chrom = row.get("chrom") or row.get("contig")
            pos = row.get("pos") or row.get("position")
            ref = str(row.get("ref") or "N").upper()
            alt = str(row.get("alt") or "N").upper()
            af_raw = row.get("af") or row.get("allele_frequency")
            if not chrom or not pos or not af_raw:
                raise ValueError(
                    "Counts TSV requires chrom/contig, pos/position, and af/allele_frequency columns"
                )
            site = Site(
                chrom=chrom,
                pos=int(pos),
                ref=ref,
                alt=alt,
                af=float(af_raw),
            )
            records.append(
                CountRecord(
                    site=site,
                    ref_count=int(row["ref_count"]),
                    alt_count=int(row["alt_count"]),
                    other_count=int(row.get("other_count") or row.get("other_alt_count") or 0),
                )
            )
    return records


def build_pileup_chunks(sites: list[Site], *, region_size: int) -> list[PileupChunk]:
    if region_size < 0:
        raise ValueError("pileup region size must be >= 0")

    chunks_by_key: dict[tuple[str, int], list[Site]] = {}
    key_order: list[tuple[str, int]] = []
    for site in sites:
        bin_index = 0 if region_size == 0 else (site.pos - 1) // region_size
        key = (site.chrom, bin_index)
        if key not in chunks_by_key:
            chunks_by_key[key] = []
            key_order.append(key)
        chunks_by_key[key].append(site)

    chunks: list[PileupChunk] = []
    for chrom, bin_index in key_order:
        chunk_sites = sorted(chunks_by_key[(chrom, bin_index)], key=lambda site: site.pos)
        if region_size == 0:
            region = chrom
        else:
            start = min(site.pos for site in chunk_sites)
            end = max(site.pos for site in chunk_sites)
            region = f"{chrom}:{start}-{end}"
        chunks.append(PileupChunk(region=region, sites=chunk_sites))
    return chunks


def parse_mpileup_lines(
    lines: Iterable[str],
    *,
    sites_by_key: dict[tuple[str, int], Site],
) -> list[CountRecord]:
    records: list[CountRecord] = []
    for line in lines:
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 5:
            continue
        chrom, pos_raw = fields[0], fields[1]
        key = (chrom, int(pos_raw))
        site = sites_by_key.get(key)
        if site is None:
            continue
        ref_count, alt_count, other_count = parse_pileup_bases(
            fields[4],
            site.ref,
            site.alt,
        )
        records.append(
            CountRecord(
                site=site,
                ref_count=ref_count,
                alt_count=alt_count,
                other_count=other_count,
            )
        )
    return records


def run_mpileup_chunk(
    *,
    bam: str | os.PathLike[str],
    reference: str | os.PathLike[str],
    chunk: PileupChunk,
    min_mapping_quality: int,
    min_base_quality: int,
    sites_by_key: dict[tuple[str, int], Site],
) -> list[CountRecord]:
    with tempfile.NamedTemporaryFile("w", suffix=".bed", delete=False, encoding="utf-8") as bed:
        bed_path = bed.name
        for site in chunk.sites:
            bed.write(f"{site.chrom}\t{site.pos - 1}\t{site.pos}\n")
    try:
        command = [
            "samtools",
            "mpileup",
            "-f",
            str(reference),
            "-r",
            chunk.region,
            "-l",
            bed_path,
            "-q",
            str(min_mapping_quality),
            "-Q",
            str(min_base_quality),
            "-aa",
            str(bam),
        ]
        with tempfile.NamedTemporaryFile("w+", encoding="utf-8") as stderr_handle:
            proc = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=stderr_handle,
                text=True,
            )
            if proc.stdout is None:
                raise RuntimeError("samtools mpileup did not provide stdout")
            records = parse_mpileup_lines(proc.stdout, sites_by_key=sites_by_key)
            return_code = proc.wait()
            stderr_handle.seek(0)
            stderr = stderr_handle.read()
        if return_code != 0:
            raise RuntimeError(
                "samtools mpileup failed with exit "
                f"{return_code} for {chunk.region}: {stderr.strip()}"
            )
        return records
    finally:
        try:
            os.unlink(bed_path)
        except FileNotFoundError:
            pass


def pileup_counts(
    *,
    bam: str | os.PathLike[str],
    reference: str | os.PathLike[str],
    sites: list[Site],
    min_mapping_quality: int,
    min_base_quality: int,
    threads: int = 1,
    pileup_region_size: int = 25_000_000,
) -> list[CountRecord]:
    if threads < 1:
        raise ValueError("threads must be >= 1")
    sites_by_key = {site.key: site for site in sites}
    chunks = build_pileup_chunks(sites, region_size=pileup_region_size)
    if not chunks:
        return []

    worker_count = min(threads, len(chunks))
    if worker_count == 1:
        records: list[CountRecord] = []
        for chunk in chunks:
            records.extend(
                run_mpileup_chunk(
                    bam=bam,
                    reference=reference,
                    chunk=chunk,
                    min_mapping_quality=min_mapping_quality,
                    min_base_quality=min_base_quality,
                    sites_by_key=sites_by_key,
                )
            )
        return records

    records = []
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = [
            executor.submit(
                run_mpileup_chunk,
                bam=bam,
                reference=reference,
                chunk=chunk,
                min_mapping_quality=min_mapping_quality,
                min_base_quality=min_base_quality,
                sites_by_key=sites_by_key,
            )
            for chunk in chunks
        ]
        for future in futures:
            records.extend(future.result())
    return records


def filtered_records(
    records: Iterable[CountRecord],
    *,
    min_depth: int,
    max_depth: int,
) -> list[CountRecord]:
    usable: list[CountRecord] = []
    for record in records:
        depth = record.depth
        if depth < min_depth:
            continue
        if max_depth and depth > max_depth:
            continue
        usable.append(record)
    return usable


def logsumexp(values: Iterable[float]) -> float:
    vals = list(values)
    if not vals:
        return -math.inf
    max_value = max(vals)
    if max_value == -math.inf:
        return max_value
    return max_value + math.log(sum(math.exp(value - max_value) for value in vals))


def genotype_priors(af: float) -> tuple[tuple[float, float], ...]:
    ref = 1.0 - af
    return (
        (0.0, ref * ref),
        (0.5, 2.0 * af * ref),
        (1.0, af * af),
    )


def bounded_probability(value: float, base_error: float) -> float:
    value = base_error + (1.0 - 2.0 * base_error) * value
    return min(max(value, 1.0e-9), 1.0 - 1.0e-9)


def site_log_likelihood(
    record: CountRecord,
    *,
    contamination_fraction: float,
    contaminant_alt_fraction: float,
    base_error: float,
) -> float:
    k = record.alt_count
    n = record.depth
    terms: list[float] = []
    for target_alt_fraction, prior in genotype_priors(record.site.af):
        if prior <= 0.0:
            continue
        allele_probability = (
            (1.0 - contamination_fraction) * target_alt_fraction
            + contamination_fraction * contaminant_alt_fraction
        )
        p_alt = bounded_probability(allele_probability, base_error)
        terms.append(math.log(prior) + k * math.log(p_alt) + (n - k) * math.log1p(-p_alt))
    return logsumexp(terms)


def total_log_likelihood(
    records: Iterable[CountRecord],
    *,
    contamination_fraction: float,
    base_error: float,
) -> float:
    return sum(
        site_log_likelihood(
            record,
            contamination_fraction=contamination_fraction,
            contaminant_alt_fraction=record.site.af,
            base_error=base_error,
        )
        for record in records
    )


def contamination_grid(max_contamination: float, grid_step: float) -> list[float]:
    if max_contamination <= 0.0 or max_contamination >= 1.0:
        raise ValueError("max_contamination must be > 0 and < 1")
    if grid_step <= 0.0 or grid_step > max_contamination:
        raise ValueError("grid_step must be > 0 and <= max_contamination")
    count = int(round(max_contamination / grid_step))
    values = [i * grid_step for i in range(count + 1)]
    if values[-1] < max_contamination:
        values.append(max_contamination)
    return [min(value, max_contamination) for value in values]


def estimate_scalar_contamination(
    records: Iterable[CountRecord],
    *,
    min_depth: int = 4,
    max_depth: int = 250,
    min_sites: int = 20,
    max_contamination: float = 0.5,
    grid_step: float = 0.001,
    base_error: float = DEFAULT_BASE_ERROR,
) -> ScalarEstimate:
    usable = filtered_records(records, min_depth=min_depth, max_depth=max_depth)
    if len(usable) < min_sites:
        raise ValueError(
            f"Only {len(usable)} usable sites after depth filters; need at least {min_sites}"
        )

    values = contamination_grid(max_contamination, grid_step)
    likelihoods = [
        total_log_likelihood(
            usable,
            contamination_fraction=value,
            base_error=base_error,
        )
        for value in values
    ]
    best_index = max(range(len(values)), key=lambda index: likelihoods[index])
    best_value = values[best_index]
    best_ll = likelihoods[best_index]
    null_ll = likelihoods[0]
    ci_values = [
        value
        for value, likelihood in zip(values, likelihoods, strict=True)
        if best_ll - likelihood <= LIKELIHOOD_CI_DROP
    ]
    read_count = sum(record.depth for record in usable)
    return ScalarEstimate(
        contamination_fraction=best_value,
        ci_low=min(ci_values),
        ci_high=max(ci_values),
        log_likelihood=best_ll,
        null_log_likelihood=null_ll,
        site_count=len(usable),
        read_count=read_count,
        mean_depth=read_count / len(usable),
    )


def genotype_to_alt_fraction(gt: str) -> float | None:
    gt = gt.split(":", 1)[0].replace("|", "/")
    if gt in {"0/0", "0"}:
        return 0.0
    if gt in {"0/1", "1/0"}:
        return 0.5
    if gt in {"1/1", "1"}:
        return 1.0
    return None


def load_vcf_candidate_genotypes(
    *,
    sample_id: str,
    vcf_path: str | os.PathLike[str],
    site_keys: set[tuple[str, int]],
) -> CandidateProfile:
    genotypes: dict[tuple[str, int], float] = {}
    sample_column_index: int | None = None
    with open_text(vcf_path) as handle:
        for line in handle:
            if line.startswith("##"):
                continue
            if line.startswith("#CHROM"):
                header = line.rstrip("\n").split("\t")
                sample_columns = header[9:]
                if sample_id in sample_columns:
                    sample_column_index = 9 + sample_columns.index(sample_id)
                elif len(sample_columns) == 1:
                    sample_column_index = 9
                else:
                    raise ValueError(
                        f"VCF {vcf_path} does not contain sample {sample_id}; "
                        "multi-sample donor VCFs must include matching sample_id"
                    )
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 10 or sample_column_index is None:
                continue
            key = (fields[0], int(fields[1]))
            if key not in site_keys:
                continue
            format_keys = fields[8].split(":")
            try:
                gt_index = format_keys.index("GT")
            except ValueError:
                continue
            sample_values = fields[sample_column_index].split(":")
            if gt_index >= len(sample_values):
                continue
            alt_fraction = genotype_to_alt_fraction(sample_values[gt_index])
            if alt_fraction is not None:
                genotypes[key] = alt_fraction
    if not genotypes:
        raise ValueError(f"No usable donor genotypes for {sample_id} in {vcf_path}")
    return CandidateProfile(sample_id=sample_id, genotypes=genotypes)


def infer_genotype_alt_fraction(
    record: CountRecord,
    *,
    min_depth: int,
    hom_ref_max: float = 0.15,
    het_min: float = 0.30,
    het_max: float = 0.70,
    hom_alt_min: float = 0.85,
) -> float | None:
    if record.depth < min_depth:
        return None
    alt_fraction = record.alt_count / record.depth
    if alt_fraction <= hom_ref_max:
        return 0.0
    if het_min <= alt_fraction <= het_max:
        return 0.5
    if alt_fraction >= hom_alt_min:
        return 1.0
    return None


def load_bam_candidate_genotypes(
    *,
    sample_id: str,
    bam_path: str | os.PathLike[str],
    reference: str | os.PathLike[str],
    sites: list[Site],
    min_mapping_quality: int,
    min_base_quality: int,
    min_depth: int,
    threads: int = 1,
    pileup_region_size: int = 25_000_000,
) -> CandidateProfile:
    genotypes: dict[tuple[str, int], float] = {}
    for record in pileup_counts(
        bam=bam_path,
        reference=reference,
        sites=sites,
        min_mapping_quality=min_mapping_quality,
        min_base_quality=min_base_quality,
        threads=threads,
        pileup_region_size=pileup_region_size,
    ):
        alt_fraction = infer_genotype_alt_fraction(record, min_depth=min_depth)
        if alt_fraction is not None:
            genotypes[record.site.key] = alt_fraction
    if not genotypes:
        raise ValueError(f"No usable donor genotypes for {sample_id} in {bam_path}")
    return CandidateProfile(sample_id=sample_id, genotypes=genotypes)


def load_candidate_manifest(
    *,
    manifest_path: str | os.PathLike[str],
    sites: list[Site],
    reference: str | os.PathLike[str],
    min_mapping_quality: int,
    min_base_quality: int,
    donor_min_depth: int,
    threads: int = 1,
    pileup_region_size: int = 25_000_000,
) -> list[CandidateProfile]:
    profiles: list[CandidateProfile] = []
    site_keys = {site.key for site in sites}
    with open(manifest_path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"sample_id", "path", "path_type"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Candidate manifest missing columns: {sorted(missing)}")
        for row in reader:
            sample_id = row["sample_id"]
            path = row["path"]
            path_type = row["path_type"].lower()
            if path_type in {"vcf", "vcf.gz", "bcf"}:
                profiles.append(
                    load_vcf_candidate_genotypes(
                        sample_id=sample_id,
                        vcf_path=path,
                        site_keys=site_keys,
                    )
                )
            elif path_type in {"bam", "cram"}:
                profiles.append(
                    load_bam_candidate_genotypes(
                        sample_id=sample_id,
                        bam_path=path,
                        reference=reference,
                        sites=sites,
                        min_mapping_quality=min_mapping_quality,
                        min_base_quality=min_base_quality,
                        min_depth=donor_min_depth,
                        threads=threads,
                        pileup_region_size=pileup_region_size,
                    )
                )
            else:
                raise ValueError(
                    f"Unsupported candidate path_type for {sample_id}: {path_type}"
                )
    return profiles


def source_alt_fraction(
    record: CountRecord,
    profiles: list[CandidateProfile],
    shares: list[float],
) -> float:
    used_share = sum(shares)
    value = max(0.0, 1.0 - used_share) * record.site.af
    for profile, share in zip(profiles, shares, strict=True):
        value += share * profile.genotypes.get(record.site.key, record.site.af)
    return value


def source_log_likelihood(
    records: Iterable[CountRecord],
    *,
    profiles: list[CandidateProfile],
    shares: list[float],
    total_contamination_fraction: float,
    base_error: float,
) -> float:
    return sum(
        site_log_likelihood(
            record,
            contamination_fraction=total_contamination_fraction,
            contaminant_alt_fraction=source_alt_fraction(record, profiles, shares),
            base_error=base_error,
        )
        for record in records
    )


def candidate_log_likelihood_deltas(
    records: list[CountRecord],
    profiles: list[CandidateProfile],
    *,
    total_contamination_fraction: float,
    base_error: float,
) -> tuple[float, dict[str, float]]:
    unknown_ll = source_log_likelihood(
        records,
        profiles=[],
        shares=[],
        total_contamination_fraction=total_contamination_fraction,
        base_error=base_error,
    )
    deltas: dict[str, float] = {}
    for profile in profiles:
        donor_ll = source_log_likelihood(
            records,
            profiles=[profile],
            shares=[1.0],
            total_contamination_fraction=total_contamination_fraction,
            base_error=base_error,
        )
        deltas[profile.sample_id] = donor_ll - unknown_ll
    return unknown_ll, deltas


def fit_donor_attribution(
    records: Iterable[CountRecord],
    profiles: list[CandidateProfile],
    *,
    total_contamination_fraction: float,
    min_depth: int = 4,
    max_depth: int = 250,
    min_sites: int = 20,
    max_candidate_sources: int = 8,
    base_error: float = DEFAULT_BASE_ERROR,
) -> AttributionResult:
    usable = filtered_records(records, min_depth=min_depth, max_depth=max_depth)
    if len(usable) < min_sites:
        raise ValueError(
            f"Only {len(usable)} usable sites after depth filters; need at least {min_sites}"
        )
    if not profiles or total_contamination_fraction <= 0.0:
        unknown_ll = source_log_likelihood(
            usable,
            profiles=[],
            shares=[],
            total_contamination_fraction=total_contamination_fraction,
            base_error=base_error,
        )
        return AttributionResult(
            total_contamination_fraction=total_contamination_fraction,
            unknown_contamination_fraction=total_contamination_fraction,
            donor_weights={},
            donor_log_likelihood_delta={},
            log_likelihood=unknown_ll,
            unknown_only_log_likelihood=unknown_ll,
        )

    unknown_ll, deltas = candidate_log_likelihood_deltas(
        usable,
        profiles,
        total_contamination_fraction=total_contamination_fraction,
        base_error=base_error,
    )
    ranked_profiles = sorted(
        profiles,
        key=lambda profile: deltas.get(profile.sample_id, -math.inf),
        reverse=True,
    )[:max_candidate_sources]
    shares = [0.0 for _ in ranked_profiles]
    best_ll = unknown_ll
    steps = [0.5, 0.25, 0.10, 0.05, 0.02, 0.01, 0.005]
    for step in steps:
        improved = True
        while improved:
            improved = False
            best_candidate = shares
            candidate_vectors: list[list[float]] = []
            for i in range(len(shares)):
                if sum(shares) + step <= 1.0 + 1.0e-12:
                    vector = shares.copy()
                    vector[i] += step
                    candidate_vectors.append(vector)
                if shares[i] >= step:
                    vector = shares.copy()
                    vector[i] -= step
                    candidate_vectors.append(vector)
                for j in range(len(shares)):
                    if i == j or shares[j] < step:
                        continue
                    vector = shares.copy()
                    vector[i] += step
                    vector[j] -= step
                    candidate_vectors.append(vector)
            for vector in candidate_vectors:
                candidate_ll = source_log_likelihood(
                    usable,
                    profiles=ranked_profiles,
                    shares=vector,
                    total_contamination_fraction=total_contamination_fraction,
                    base_error=base_error,
                )
                if candidate_ll > best_ll + 1.0e-6:
                    best_ll = candidate_ll
                    best_candidate = vector
                    improved = True
            shares = best_candidate

    donor_weights = {
        profile.sample_id: total_contamination_fraction * share
        for profile, share in zip(ranked_profiles, shares, strict=True)
        if share > 0.0
    }
    unknown_fraction = total_contamination_fraction * max(0.0, 1.0 - sum(shares))
    return AttributionResult(
        total_contamination_fraction=total_contamination_fraction,
        unknown_contamination_fraction=unknown_fraction,
        donor_weights=donor_weights,
        donor_log_likelihood_delta=deltas,
        log_likelihood=best_ll,
        unknown_only_log_likelihood=unknown_ll,
    )


def write_summary(
    path: str | os.PathLike[str],
    *,
    sample_id: str,
    estimate: ScalarEstimate,
    attribution: AttributionResult | None,
) -> None:
    fieldnames = [
        "sample_id",
        "method",
        "contamination_fraction",
        "contamination_pct",
        "ci_low_fraction",
        "ci_high_fraction",
        "unknown_contamination_fraction",
        "unknown_contamination_pct",
        "site_count",
        "read_count",
        "mean_depth",
        "log_likelihood",
        "null_log_likelihood",
        "delta_log_likelihood",
        "source_delta_log_likelihood",
    ]
    unknown_fraction = (
        attribution.unknown_contamination_fraction
        if attribution is not None
        else estimate.contamination_fraction
    )
    source_delta = (
        attribution.log_likelihood - attribution.unknown_only_log_likelihood
        if attribution is not None
        else ""
    )
    row = {
        "sample_id": sample_id,
        "method": "genotype_free_site_mix",
        "contamination_fraction": f"{estimate.contamination_fraction:.6g}",
        "contamination_pct": f"{100.0 * estimate.contamination_fraction:.6g}",
        "ci_low_fraction": f"{estimate.ci_low:.6g}",
        "ci_high_fraction": f"{estimate.ci_high:.6g}",
        "unknown_contamination_fraction": f"{unknown_fraction:.6g}",
        "unknown_contamination_pct": f"{100.0 * unknown_fraction:.6g}",
        "site_count": str(estimate.site_count),
        "read_count": str(estimate.read_count),
        "mean_depth": f"{estimate.mean_depth:.6g}",
        "log_likelihood": f"{estimate.log_likelihood:.6g}",
        "null_log_likelihood": f"{estimate.null_log_likelihood:.6g}",
        "delta_log_likelihood": f"{estimate.log_likelihood - estimate.null_log_likelihood:.6g}",
        "source_delta_log_likelihood": (
            f"{source_delta:.6g}" if isinstance(source_delta, float) else source_delta
        ),
    }
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerow(row)


def write_donor_rows(
    path: str | os.PathLike[str],
    *,
    sample_id: str,
    attribution: AttributionResult,
) -> None:
    fieldnames = [
        "sample_id",
        "source_rank",
        "source_sample_id",
        "is_unknown_source",
        "contamination_fraction",
        "contamination_pct",
        "single_source_delta_log_likelihood",
    ]
    rows = [
        {
            "sample_id": sample_id,
            "source_rank": "",
            "source_sample_id": "UNKNOWN",
            "is_unknown_source": "true",
            "contamination_fraction": f"{attribution.unknown_contamination_fraction:.6g}",
            "contamination_pct": f"{100.0 * attribution.unknown_contamination_fraction:.6g}",
            "single_source_delta_log_likelihood": "",
        }
    ]
    ranked = sorted(
        attribution.donor_weights.items(),
        key=lambda item: item[1],
        reverse=True,
    )
    for rank, (donor_id, weight) in enumerate(ranked, start=1):
        rows.append(
            {
                "sample_id": sample_id,
                "source_rank": str(rank),
                "source_sample_id": donor_id,
                "is_unknown_source": "false",
                "contamination_fraction": f"{weight:.6g}",
                "contamination_pct": f"{100.0 * weight:.6g}",
                "single_source_delta_log_likelihood": f"{attribution.donor_log_likelihood_delta.get(donor_id, 0.0):.6g}",
            }
        )
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Estimate same-species contamination without target genotypes."
    )
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--bam", help="Input BAM/CRAM for the target sample.")
    input_group.add_argument(
        "--counts-tsv",
        help="Precomputed allele-count TSV for testing or reuse.",
    )
    parser.add_argument("--sample-id", required=True)
    parser.add_argument("--reference", help="Reference FASTA required for BAM/CRAM input.")
    parser.add_argument("--sites-vcf", help="Common biallelic SNP VCF with INFO/AF.")
    parser.add_argument("--candidate-manifest", help="Optional donor manifest TSV.")
    parser.add_argument("--output", required=True, help="Summary TSV output.")
    parser.add_argument("--donor-output", help="Optional donor/source TSV output.")
    parser.add_argument("--min-af", type=float, default=0.01)
    parser.add_argument("--max-af", type=float, default=0.99)
    parser.add_argument("--max-sites", type=int, default=0)
    parser.add_argument("--min-depth", type=int, default=4)
    parser.add_argument("--max-depth", type=int, default=250)
    parser.add_argument("--min-sites", type=int, default=20)
    parser.add_argument("--donor-min-depth", type=int, default=8)
    parser.add_argument("--min-base-quality", type=int, default=20)
    parser.add_argument("--min-mapping-quality", type=int, default=20)
    parser.add_argument(
        "--threads",
        type=int,
        default=1,
        help="Parallel samtools mpileup region workers for BAM/CRAM inputs.",
    )
    parser.add_argument(
        "--pileup-region-size",
        type=int,
        default=25_000_000,
        help=(
            "Genomic span in bases per mpileup region chunk; use 0 to chunk "
            "by whole contig."
        ),
    )
    parser.add_argument("--max-contamination", type=float, default=0.5)
    parser.add_argument("--grid-step", type=float, default=0.001)
    parser.add_argument("--base-error", type=float, default=DEFAULT_BASE_ERROR)
    parser.add_argument("--max-candidate-sources", type=int, default=8)
    return parser


def run(args: argparse.Namespace) -> int:
    if args.counts_tsv:
        records = records_from_counts_tsv(args.counts_tsv)
        sites = [record.site for record in records]
    else:
        if not args.reference:
            raise ValueError("--reference is required with --bam")
        if not args.sites_vcf:
            raise ValueError("--sites-vcf is required with --bam")
        sites = load_sites(
            args.sites_vcf,
            min_af=args.min_af,
            max_af=args.max_af,
            max_sites=args.max_sites,
        )
        print(
            "site_mix: loaded "
            f"{len(sites)} marker sites; using {args.threads} mpileup worker(s) "
            f"and {args.pileup_region_size} bp region chunks",
            file=sys.stderr,
            flush=True,
        )
        records = pileup_counts(
            bam=args.bam,
            reference=args.reference,
            sites=sites,
            min_mapping_quality=args.min_mapping_quality,
            min_base_quality=args.min_base_quality,
            threads=args.threads,
            pileup_region_size=args.pileup_region_size,
        )
        print(
            f"site_mix: collected pileup counts for {len(records)} sites",
            file=sys.stderr,
            flush=True,
        )

    estimate = estimate_scalar_contamination(
        records,
        min_depth=args.min_depth,
        max_depth=args.max_depth,
        min_sites=args.min_sites,
        max_contamination=args.max_contamination,
        grid_step=args.grid_step,
        base_error=args.base_error,
    )

    attribution: AttributionResult | None = None
    if args.candidate_manifest:
        if not args.reference:
            raise ValueError("--reference is required with --candidate-manifest")
        profiles = load_candidate_manifest(
            manifest_path=args.candidate_manifest,
            sites=sites,
            reference=args.reference,
            min_mapping_quality=args.min_mapping_quality,
            min_base_quality=args.min_base_quality,
            donor_min_depth=args.donor_min_depth,
            threads=args.threads,
            pileup_region_size=args.pileup_region_size,
        )
        attribution = fit_donor_attribution(
            records,
            profiles,
            total_contamination_fraction=estimate.contamination_fraction,
            min_depth=args.min_depth,
            max_depth=args.max_depth,
            min_sites=args.min_sites,
            max_candidate_sources=args.max_candidate_sources,
            base_error=args.base_error,
        )
    elif args.donor_output:
        attribution = fit_donor_attribution(
            records,
            [],
            total_contamination_fraction=estimate.contamination_fraction,
            min_depth=args.min_depth,
            max_depth=args.max_depth,
            min_sites=args.min_sites,
            base_error=args.base_error,
        )

    write_summary(args.output, sample_id=args.sample_id, estimate=estimate, attribution=attribution)
    if args.donor_output and attribution is not None:
        write_donor_rows(args.donor_output, sample_id=args.sample_id, attribution=attribution)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return run(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
