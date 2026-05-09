# TMPDIR Pattern Audit Report

> Historical audit note: this report captures the state observed on
> 2026-02-13. Treat it as a dated debugging record, not canonical current
> operator guidance. Re-check the referenced rules before using any status or
> command snippet here as current truth.

**Date:** 2026-02-13  
**Auditor:** Forge (Augment Agent)  
**Scope:** Resource-intensive Snakemake rules (alignment, deduplication, variant calling)

## Required Pattern

All rules must follow this pattern:

```bash
timestamp=$(date +%Y%m%d%H%M%S)
export TMPDIR=/dev/shm/<workflow_prefix>_tmp_$timestamp
export SENTIEON_TMPDIR=$TMPDIR
mkdir -p "$TMPDIR"
export APPTAINER_HOME=$TMPDIR
trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT
```

Optional: Append `_$$` to timestamp for additional uniqueness.

---

## Alignment Workflows

### ✅ `workflow/rules/sentieon.smk` (Illumina BWA-MEM)
- **TMPDIR pattern:** ✅ `/dev/shm/sentieon_tmp_$timestamp`
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Status:** COMPLIANT

### ✅ `workflow/rules/sentieon_gatk.smk` (Illumina BWA-MEM GATK mode)
- **TMPDIR pattern:** ✅ `/dev/shm/sentieon_tmp_$timestamp` (2 rules)
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Status:** COMPLIANT

### ✅ `workflow/rules/sentmm2_align_sort.smk` (Illumina minimap2)
- **TMPDIR pattern:** ✅ `/dev/shm/sentmm2_tmp_${timestamp}_$$`
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Additional hardening:** ✅ TMPDIR validation, diagnostic logging
- **Status:** COMPLIANT (BEST PRACTICE)

### ✅ `workflow/rules/sentmm2ont_align_sort.smk` (ONT minimap2)
- **TMPDIR pattern:** ✅ `/dev/shm/sentmm2ont_tmp_${timestamp}_$$`
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Additional hardening:** ✅ TMPDIR validation, diagnostic logging
- **Status:** COMPLIANT (BEST PRACTICE)

### ⚠️ `workflow/rules/strobe_align_sort.smk` (strobealign)
- **TMPDIR pattern:** ✅ `/dev/shm/strobe_tmp_$timestamp` (2 rules)
- **SENTIEON_TMPDIR:** ❌ NOT exported (rule 1), ✅ Exported (rule 2)
- **Trap command:** ✅ Present
- **Issue:** First rule missing `export` keyword for TMPDIR
- **Status:** NEEDS FIX

**Code (Line 62):**
```bash
TMPDIR=/dev/shm/strobe_tmp_$timestamp;  # Missing export
```

**Should be:**
```bash
export TMPDIR=/dev/shm/strobe_tmp_$timestamp;
```

### ✅ `workflow/rules/sent_aln_sort_snv.smk` (Sentieon pangenome)
- **TMPDIR pattern:** ✅ `/dev/shm/sentpg_tmp_${timestamp}_$$`
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Additional hardening:** ✅ TMPDIR validation, diagnostic logging
- **Status:** COMPLIANT (BEST PRACTICE)

---

## Deduplication Workflows

### ⚠️ `workflow/rules/sentieon_markdup.smk`
- **TMPDIR pattern:** ✅ `/dev/shm/sentieon_mkduo_tmp_$timestamp`
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Issue:** Missing `export` keyword for TMPDIR
- **Status:** NEEDS FIX

**Code (Line 60):**
```bash
TMPDIR=/dev/shm/sentieon_mkduo_tmp_$timestamp;  # Missing export
```

**Should be:**
```bash
export TMPDIR=/dev/shm/sentieon_mkduo_tmp_$timestamp;
```

### ❌ `workflow/rules/doppelmark_sentieon.smk`
- **TMPDIR pattern:** ❌ Uses `{params.tmp_base}/dppl_sentieon_$timestamp` (not /dev/shm)
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Issue:** Uses configurable tmp_base instead of /dev/shm
- **Status:** USES /fsx/scratch (DOCUMENT SEPARATELY)

**Code (Line 86):**
```bash
TMPDIR={params.tmp_base}/dppl_sentieon_$timestamp;
```

**Note:** This rule intentionally uses a configurable location. Check if migration to /dev/shm is desired.

---

## Variant Calling Workflows

### ✅ `workflow/rules/sent_TNscope.smk` (Tumor-normal somatic)
- **TMPDIR pattern:** ✅ `/dev/shm/senttn_tmp_$timestamp` (with random suffix)
- **SENTIEON_TMPDIR:** ✅ Exported
- **Trap command:** ✅ Present
- **Additional uniqueness:** ✅ Appends 12-char random string
- **Status:** COMPLIANT (ENHANCED)

### ⚠️ `workflow/rules/sent_snv_ont.smk` (ONT long-read)
- **TMPDIR pattern:** ✅ `/dev/shm/sentdont_tmp_$timestamp`
- **SENTIEON_TMPDIR:** ❌ NOT exported
- **Trap command:** ✅ Present
- **Issue:** Missing SENTIEON_TMPDIR export
- **Status:** NEEDS FIX

**Code (Lines 62-65):**
```bash
export TMPDIR=/dev/shm/sentdont_tmp_$timestamp;
mkdir -p $TMPDIR;
export APPTAINER_HOME=$TMPDIR;
trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
```

**Should add:**
```bash
export SENTIEON_TMPDIR=$TMPDIR;
```

### ❌ `workflow/rules/sent_snv_pb.smk` (PacBio HiFi)
- **TMPDIR pattern:** ❌ Uses `/fsx/scratch/sentdpb_tmp_$timestamp` (not /dev/shm)
- **SENTIEON_TMPDIR:** ❌ NOT exported
- **Trap command:** ✅ Present
- **Issues:**
  1. Uses /fsx/scratch instead of /dev/shm
  2. Missing SENTIEON_TMPDIR export
- **Status:** NEEDS MIGRATION + FIX

**Code (Lines 57-60):**
```bash
export TMPDIR=/fsx/scratch/sentdpb_tmp_$timestamp;
mkdir -p $TMPDIR;
export APPTAINER_HOME=$TMPDIR;
trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
```

**Should be:**
```bash
export TMPDIR=/dev/shm/sentdpb_tmp_$timestamp;
export SENTIEON_TMPDIR=$TMPDIR;
mkdir -p $TMPDIR;
export APPTAINER_HOME=$TMPDIR;
trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
```

### ⚠️ `workflow/rules/sent_snv_ontr.smk` (ONT R10.4+)
- **TMPDIR pattern:** ✅ `/dev/shm/sentdontr_tmp_$timestamp`
- **SENTIEON_TMPDIR:** ❌ NOT exported
- **Trap command:** ✅ Present
- **Issue:** Missing SENTIEON_TMPDIR export
- **Status:** NEEDS FIX

**Should add after line 53:**
```bash
export SENTIEON_TMPDIR=$TMPDIR;
```

### ⚠️ `workflow/rules/sent_hybrid_ilmn_ont.smk` (ILMN+ONT hybrid)
- **TMPDIR pattern:** ⚠️ `/dev/shm/sentdontr_tmp_$timestamp` (wrong prefix)
- **SENTIEON_TMPDIR:** ❌ NOT exported
- **Trap command:** ✅ Present
- **Issues:**
  1. Uses `sentdontr` prefix instead of `sentdhio`
  2. Missing SENTIEON_TMPDIR export
- **Status:** NEEDS FIX

**Code (Line 55):**
```bash
export TMPDIR=/dev/shm/sentdontr_tmp_$timestamp;
```

**Should be:**
```bash
export TMPDIR=/dev/shm/sentdhio_tmp_$timestamp;
export SENTIEON_TMPDIR=$TMPDIR;
```

### ⚠️ `workflow/rules/sent_hybrid_ug_ont.smk` (Ultima+ONT hybrid)
- **TMPDIR pattern:** ⚠️ `/dev/shm/sentdontr_tmp_$timestamp` (wrong prefix)
- **SENTIEON_TMPDIR:** ❌ NOT exported
- **Trap command:** ✅ Present
- **Issues:**
  1. Uses `sentdontr` prefix instead of `sentdhuo`
  2. Missing SENTIEON_TMPDIR export
- **Status:** NEEDS FIX

**Code (Line 55):**
```bash
export TMPDIR=/dev/shm/sentdontr_tmp_$timestamp;
```

**Should be:**
```bash
export TMPDIR=/dev/shm/sentdhuo_tmp_$timestamp;
export SENTIEON_TMPDIR=$TMPDIR;
```

---

## Summary

### Compliance Status

| Status | Count | Rules |
|--------|-------|-------|
| ✅ Fully Compliant | 6 | sentieon.smk, sentieon_gatk.smk, sentmm2_align_sort.smk, sentmm2ont_align_sort.smk, sent_aln_sort_snv.smk, sent_TNscope.smk |
| ⚠️ Needs Fix | 6 | strobe_align_sort.smk, sentieon_markdup.smk, sent_snv_ont.smk, sent_snv_ontr.smk, sent_hybrid_ilmn_ont.smk, sent_hybrid_ug_ont.smk |
| ❌ Needs Migration | 1 | sent_snv_pb.smk |
| 📋 Uses /fsx/scratch | 1 | doppelmark_sentieon.smk |

### Issues Found

1. **Missing `export TMPDIR`** (2 rules):
   - strobe_align_sort.smk (rule 1)
   - sentieon_markdup.smk

2. **Missing `export SENTIEON_TMPDIR`** (6 rules):
   - sent_snv_ont.smk
   - sent_snv_pb.smk
   - sent_snv_ontr.smk
   - sent_hybrid_ilmn_ont.smk
   - sent_hybrid_ug_ont.smk

3. **Wrong TMPDIR prefix** (2 rules):
   - sent_hybrid_ilmn_ont.smk (uses `sentdontr` instead of `sentdhio`)
   - sent_hybrid_ug_ont.smk (uses `sentdontr` instead of `sentdhuo`)

4. **Uses /fsx/scratch instead of /dev/shm** (1 rule):
   - sent_snv_pb.smk

5. **Uses configurable tmp_base** (1 rule):
   - doppelmark_sentieon.smk (intentional design)

### Recommendations

1. **Immediate fixes:** Add missing `export` statements and fix TMPDIR prefixes
2. **Migration:** Move sent_snv_pb.smk from /fsx/scratch to /dev/shm
3. **Best practice adoption:** Consider adding PID suffix (`_$$`) to all rules for collision prevention
4. **TMPDIR validation:** Consider adding validation checks (mkdir -p + existence check) to all rules
5. **Review doppelmark_sentieon.smk:** Determine if migration to /dev/shm is desired

---

## Files to Fix

1. `workflow/rules/strobe_align_sort.smk` - Add `export` to TMPDIR (line 62)
2. `workflow/rules/sentieon_markdup.smk` - Add `export` to TMPDIR (line 60)
3. `workflow/rules/sent_snv_ont.smk` - Add `export SENTIEON_TMPDIR` (after line 62)
4. `workflow/rules/sent_snv_pb.smk` - Change to /dev/shm + add SENTIEON_TMPDIR (line 57)
5. `workflow/rules/sent_snv_ontr.smk` - Add `export SENTIEON_TMPDIR` (after line 53)
6. `workflow/rules/sent_hybrid_ilmn_ont.smk` - Fix prefix + add SENTIEON_TMPDIR (line 55)
7. `workflow/rules/sent_hybrid_ug_ont.smk` - Fix prefix + add SENTIEON_TMPDIR (line 55)
