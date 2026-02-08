Hybrid model bundles exist (but the email does NOT give their direct URLs)

Sentieon’s public “sentieon-models” index indicates there are dedicated hybrid bundles (Illumina+ONT, Illumina+PacBio, Ultima+ONT, etc.).
So for hybrid, you should use the appropriate hybrid bundle (not the pure ONT bundle).

1) Bash command templates for pipelines
Common env you’ll set once
# Threads on your 192 vCPU box (leave headroom if you want)
export T=192

# Paths you control
export WORK=/data/work
export OUT=/data/out
export REF=/data/ref/GRCh38.fa                # ASSUMPTION: GRCh38; change if you’re using hg19/b37
export DBSNP=/data/ref/dbsnp.vcf.gz           # optional (recommended if you have it)
export DIPLOID_BED=/data/ref/diploid.bed      # optional (if you’re restricting evaluation regions)

# Model bundles (from the email)
export BUNDLE_ILL_PANGENOME=/data/models/SentieonIlluminaPangenomeRealignWGS1.0.bundle
export BUNDLE_ONT=/data/models/DNAscopeONT2.2.bundle

# Hybrid bundle (NOT provided in the email; you must choose the right one)
export BUNDLE_HYB_ILL_ONT=/data/models/Illumina_ONT_WGS.bundle  # placeholder filename

1A) Short-read (Illumina) pipeline: alignment + SNV/indel + SV
Recommended by the email: Sentieon pangenome pipeline in sentieon-cli

Sentieon’s CLI release notes indicate the modern pipeline name is sentieon-pangenome (replacing earlier pangenome).

Command template (one sample, paired FASTQs):

# Inputs
SAMPLE=HG002
R1=/data/reads/${SAMPLE}.R1.fastq.gz
R2=/data/reads/${SAMPLE}.R2.fastq.gz

# Outputs
mkdir -p "${OUT}/${SAMPLE}/pangenome"

# Pangenome pipeline (alignment + variant calling; SV behavior depends on your sentieon-cli config/pipeline)
sentieon-cli sentieon-pangenome \
  -t "${T}" \
  -r "${REF}" \
  -m "${BUNDLE_ILL_PANGENOME}" \
  --fastq "${R1}" "${R2}" \
  --rgsm "${SAMPLE}" \
  "${OUT}/${SAMPLE}/pangenome/${SAMPLE}.vcf.gz"


What’s “in scope” here: alignment + small variants are definitely part of the pangenome pipeline; SV handling may be included depending on pipeline options/version (Sentieon has SV components in their short-read workflows generally, and their DNAscope stack includes SV tooling like SVsolver).
If you want SV as a distinct explicit stage (more auditable), use the explicit DNAscope SV tooling path below.

Explicit short-read SV stage (Sentieon SVsolver) — if you want it spelled out

Sentieon’s docs indicate DNAscope can do structural variant calling and references “SVsolver” as the SV component.

Template (run after you have an aligned BAM):

# Example: assuming you have an aligned BAM from your short-read pipeline:
BAM=/data/aln/${SAMPLE}.bam

sentieon driver \
  -t "${T}" \
  -r "${REF}" \
  -i "${BAM}" \
  --algo SVSolver \
  "${OUT}/${SAMPLE}/sv/${SAMPLE}.sv.vcf.gz"

1B) Long-read pipeline (ONT or PacBio): SNV/indel calling

A published command-line synopsis for sentieon-cli dnascope-longread is:

sentieon-cli dnascope-longread \
  -r REFERENCE \
  --fastq INPUT_FASTQ ... \
  --readgroups READGROUP ... \
  -m MODEL_BUNDLE \
  [-d DBSNP] \
  [-b DIPLOID_BED] \
  [-t NUMBER_THREADS] \
  [-g] \
  --tech HiFi|ONT \
  sample.vcf.gz

If you start from FASTQs (most correct for the CLI)

ONT example:

SAMPLE=HG001_ONT
FQ=/data/ont/${SAMPLE}.fastq.gz   # you must produce this if you only have BAMs

sentieon-cli dnascope-longread \
  -t "${T}" \
  -r "${REF}" \
  -m "${BUNDLE_ONT}" \
  --tech ONT \
  ${DBSNP:+-d "${DBSNP}"} \
  ${DIPLOID_BED:+-b "${DIPLOID_BED}"} \
  --fastq "${FQ}" \
  --readgroups "ID:${SAMPLE}\tSM:${SAMPLE}\tPL:ONT" \
  "${OUT}/${SAMPLE}/longread/${SAMPLE}.vcf.gz"


PacBio HiFi example (NOTE: email says PacBio model “soon”; you likely need a HiFi bundle distinct from ONT):

SAMPLE=HG002_HIFI
FQ=/data/hifi/${SAMPLE}.fastq.gz  # again, if you only have BAMs you must produce FASTQ

# Placeholder: you need the actual HiFi model bundle path from Sentieon.
BUNDLE_HIFI=/data/models/DNAscopeHiFi.bundle

sentieon-cli dnascope-longread \
  -t "${T}" \
  -r "${REF}" \
  -m "${BUNDLE_HIFI}" \
  --tech HiFi \
  ${DBSNP:+-d "${DBSNP}"} \
  ${DIPLOID_BED:+-b "${DIPLOID_BED}"} \
  --fastq "${FQ}" \
  --readgroups "ID:${SAMPLE}\tSM:${SAMPLE}\tPL:PACBIO" \
  "${OUT}/${SAMPLE}/longread/${SAMPLE}.vcf.gz"

If you only have BAMs (as in the email)

The email’s long-read inputs are mostly BAMs, not FASTQs. The sentieon-cli dnascope-longread synopsis above is FASTQ-based.

So you have two realistic options:

Convert BAM → FASTQ (keeps you aligned with the sentieon-cli dnascope-longread interface)

Use Sentieon’s driver-based long-read appnote pipeline (scripted) rather than the CLI wrapper

I’m not guessing the exact driver pipeline steps without the specific Sentieon protocol text you mentioned (you said they sent protocols, but the attached email doesn’t include step-by-step commands).

1C) Long-read SV calling (PacBio HiFi / ONT): LongReadSV

Sentieon’s LongReadSV appnote gives the canonical call form:

SAMPLE=HG001_ONT
BAM=/data/ont/${SAMPLE}.bam

mkdir -p "${OUT}/${SAMPLE}/sv"

sentieon driver \
  -t "${T}" \
  -r "${REF}" \
  -i "${BAM}" \
  --algo LongReadSV \
  "${OUT}/${SAMPLE}/sv/${SAMPLE}.sv.vcf.gz"

1D) Hybrid pipeline (short + long): sentieon-cli dnascope-hybrid

Published synopsis for the hybrid CLI command:

sentieon-cli dnascope-hybrid \
  -r REFERENCE \
  --sr-aln SR_ALN [SR_ALN …] \
  --lr_aln LR_ALN [LR_ALN …] \
  -m MODEL_BUNDLE \
  [-d DBSNP] \
  [-b DIPLOID_BED] \
  [-t NUMBER_THREADS] \
  sample.vcf.gz


Concrete example (Illumina BAM + ONT BAM):

SAMPLE=HG002
SR_BAM=/data/aln/${SAMPLE}.illumina.bam   # produced by your short-read pipeline
LR_BAM=/data/aln/${SAMPLE}.ont.bam        # from ONT (or aligned by minimap2 etc)

mkdir -p "${OUT}/${SAMPLE}/hybrid"

sentieon-cli dnascope-hybrid \
  -t "${T}" \
  -r "${REF}" \
  -m "${BUNDLE_HYB_ILL_ONT}" \
  ${DBSNP:+-d "${DBSNP}"} \
  ${DIPLOID_BED:+-b "${DIPLOID_BED}"} \
  --sr-aln "${SR_BAM}" \
  --lr_aln "${LR_BAM}" \
  "${OUT}/${SAMPLE}/hybrid/${SAMPLE}.hybrid.vcf.gz"


Important: choose the correct hybrid model bundle. Sentieon publicly lists distinct bundles for Illumina+ONT vs Illumina+PacBio vs Ultima+ONT, etc.

2) Spot-safe “download everything from the email” script

This script:

downloads into a structured directory

is idempotent (re-run safe)

uses curl with resume for HTTPS

optionally uses rclone for parallelism (you said you have it)

records a .complete marker per file so spot interruptions don’t cause “start over” behavior

Save as: fetch_sentieon_email_inputs.sh

#!/usr/bin/env bash
set -euo pipefail

# ---------- config ----------
ROOT="${ROOT:-/data}"
DL="${DL:-${ROOT}/downloads}"
MODELS="${MODELS:-${ROOT}/models}"
LOG="${LOG:-${ROOT}/logs}"
mkdir -p "${DL}" "${MODELS}" "${LOG}"

# rclone tuning (optional)
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-16}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-32}"

# ---------- helpers ----------
log() { printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "${LOG}/fetch.log" >&2; }

# Download a URL to a destination file with resume + completion marker.
# Uses curl; if rclone is present, can swap to rclone for faster multi-part.
fetch_url() {
  local url="$1"
  local dest="$2"
  local marker="${dest}.complete"

  mkdir -p "$(dirname "${dest}")"

  if [[ -f "${marker}" && -s "${dest}" ]]; then
    log "SKIP (complete): ${dest}"
    return 0
  fi

  log "GET: ${url}"
  log " ->  ${dest}"

  # If rclone exists, it's often more resilient on spot instances.
  if command -v rclone >/dev/null 2>&1; then
    # rclone can copy http(s) to local path.
    # --partial keeps partials; re-run resumes safely.
    rclone copyurl \
      --transfers "${RCLONE_TRANSFERS}" \
      --checkers "${RCLONE_CHECKERS}" \
      --retries 20 \
      --low-level-retries 50 \
      --retry-sleep 10s \
      --timeout 1m \
      --contimeout 30s \
      --stats 30s \
      --partial \
      "${url}" "${dest}" \
      || {
        log "ERROR: rclone copyurl failed for ${url}"
        return 1
      }
  else
    # curl resume
    curl -L --fail --retry 20 --retry-all-errors --connect-timeout 30 --speed-time 30 --speed-limit 10240 \
      -C - -o "${dest}" "${url}"
  fi

  # Basic sanity: non-empty
  if [[ ! -s "${dest}" ]]; then
    log "ERROR: downloaded file is empty: ${dest}"
    return 1
  fi

  touch "${marker}"
  log "DONE: ${dest}"
}

# ---------- model bundles (explicit in email) ----------
fetch_models() {
  log "Downloading model bundles..."

  fetch_url \
    "https://s3.amazonaws.com/sentieon-release/other/SentieonIlluminaPangenomeRealignWGS1.0.bundle" \
    "${MODELS}/SentieonIlluminaPangenomeRealignWGS1.0.bundle"

  fetch_url \
    "https://s3.amazonaws.com/sentieon-release/other/DNAscopeONT2.2.bundle" \
    "${MODELS}/DNAscopeONT2.2.bundle"

  log "NOTE: Hybrid and PacBio/Ultima bundles are not directly linked in the email."
}

# ---------- short-read fastqs ----------
fetch_illumina_google_brain() {
  local base="https://s3.amazonaws.com/genomics-benchmark-datasets/google-brain/fastq/novaseq"

  log "Downloading Illumina (Google Brain) FASTQs..."

  for hg in HG001 HG002 HG003 HG004 HG005; do
    fetch_url "${base}/wgs_pcr_free/30x/${hg}.novaseq.pcr-free.30x.R1.fastq.gz" \
      "${DL}/illumina/google_brain/wgs_pcr_free_30x/${hg}.R1.fastq.gz"
    fetch_url "${base}/wgs_pcr_free/30x/${hg}.novaseq.pcr-free.30x.R2.fastq.gz" \
      "${DL}/illumina/google_brain/wgs_pcr_free_30x/${hg}.R2.fastq.gz"

    fetch_url "${base}/wgs_pcr_plus/30x/${hg}.novaseq.pcr-plus.30x.R1.fastq.gz" \
      "${DL}/illumina/google_brain/wgs_pcr_plus_30x/${hg}.R1.fastq.gz"
    fetch_url "${base}/wgs_pcr_plus/30x/${hg}.novaseq.pcr-plus.30x.R2.fastq.gz" \
      "${DL}/illumina/google_brain/wgs_pcr_plus_30x/${hg}.R2.fastq.gz"
  done
}

# ---------- pacbio hifi bams ----------
fetch_pacbio_hifi() {
  log "Downloading PacBio HiFi BAMs..."
  fetch_url \
    "https://downloads.pacbcloud.com/public/revio/2024Q4/WGS/GIAB_trio/HG002_rep1/m84039_241001_220042_s2.hifi_reads.bc2018.bam" \
    "${DL}/pacbio/revio_2024Q4/GIAB_trio/HG002_rep1.m84039_241001_220042.bc2018.bam"

  fetch_url \
    "https://downloads.pacbcloud.com/public/revio/2024Q4/WGS/GIAB_trio/HG002_rep2/m84039_241002_040926_s1.hifi_reads.bc2024.bam" \
    "${DL}/pacbio/revio_2024Q4/GIAB_trio/HG002_rep2.m84039_241002_040926.bc2024.bam"

  fetch_url \
    "https://downloads.pacbcloud.com/public/revio/2024Q4/WGS/GIAB_trio/HG003/m84039_241002_000337_s3.hifi_reads.bc2020.bam" \
    "${DL}/pacbio/revio_2024Q4/GIAB_trio/HG003.m84039_241002_000337.bc2020.bam"

  fetch_url \
    "https://downloads.pacbcloud.com/public/revio/2024Q4/WGS/GIAB_trio/HG004/m84039_241002_020632_s4.hifi_reads.bc2021.bam" \
    "${DL}/pacbio/revio_2024Q4/GIAB_trio/HG004.m84039_241002_020632.bc2021.bam"
}

# ---------- ont bams ----------
fetch_ont() {
  log "Downloading ONT BAMs..."
  fetch_url \
    "https://ont-open-data.s3.amazonaws.com/giab_2025.01/basecalling/sup/HG001/PAW81754/calls.sorted.bam" \
    "${DL}/ont/giab_2025.01/HG001/PAW81754.calls.sorted.bam"

  fetch_url \
    "https://ont-open-data.s3.amazonaws.com/giab_2025.01/basecalling/sup/HG002/PAW70337/calls.sorted.bam" \
    "${DL}/ont/giab_2025.01/HG002/PAW70337.calls.sorted.bam"

  fetch_url \
    "https://ont-open-data.s3.amazonaws.com/giab_2025.01/basecalling/sup/HG002/PAW71238/calls.sorted.bam" \
    "${DL}/ont/giab_2025.01/HG002/PAW71238.calls.sorted.bam"

  fetch_url \
    "https://ont-open-data.s3.amazonaws.com/giab_2025.01/basecalling/sup/HG003/PAY87794/calls.sorted.bam" \
    "${DL}/ont/giab_2025.01/HG003/PAY87794.calls.sorted.bam"

  fetch_url \
    "https://ont-open-data.s3.amazonaws.com/giab_2025.01/basecalling/sup/HG003/PAY87954/calls.sorted.bam" \
    "${DL}/ont/giab_2025.01/HG003/PAY87954.calls.sorted.bam"
}

# ---------- (optional) sentieon-cli latest ----------
fetch_sentieon_cli() {
  log "Downloading latest sentieon-cli sdist (public GitHub release; does NOT include Sentieon binaries)..."
  # Latest shown in the GitHub release listing is v1.5.1 (Jan 26, 2026). :contentReference[oaicite:12]{index=12}
  fetch_url \
    "https://github.com/Sentieon/sentieon-cli/releases/download/v1.5.1/sentieon_cli-1.5.1.tar.gz" \
    "${DL}/sentieon-cli/sentieon_cli-1.5.1.tar.gz"
}

main() {
  fetch_models
  fetch_illumina_google_brain
  fetch_pacbio_hifi
  fetch_ont
  fetch_sentieon_cli

  log "ALL DONE."
  log "NOTE: Sentieon Genomics binaries (sentieon driver, etc.) are not publicly downloadable here; you’ll need your licensed tarball from Sentieon support."
}

main "$@"