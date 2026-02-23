# HIOa Hybrid ILMN+ONT Workflow — Heatmap Report

**Generated**: 2026-02-18 14:19:10

| Parameter | Value |
|---|---|
| Genome Build | hg38_broad |
| Sample | HG003 (Ashkenazi Jewish Father) |
| Variant Caller | Sentieon DNAscope Hybrid ILMN+ONT (sentdhio) |
| Concordance Footprint | giabHC (GIAB high-confidence regions) |
| Matrix | 10 ILMN coverages × 7 ONT coverages = 70 units |
| Workflow Config | `-T 1 -j 20 -k -p` (1 retry, 20 concurrent) |

## Unit Status

| Status | Count |
|---|---|
| ✅ Complete (concordance done) | 19 |
| 🔄 Running | 5 |
| ✗ Failed | 30 |
| **Total** | **63** |

---

## F-score Heatmaps — giabHC

### SNPts (giabHC)

![SNPts F-score — giabHC](HIOa_fscore_snpts_giabhc.png)

### SNPtv (giabHC)

![SNPtv F-score — giabHC](HIOa_fscore_snptv_giabhc.png)

### INS_50 (giabHC)

![INS_50 F-score — giabHC](HIOa_fscore_ins_50_giabhc.png)

### INS_gt50 (giabHC)

![INS_gt50 F-score — giabHC](HIOa_fscore_ins_gt50_giabhc.png)

### DEL_50 (giabHC)

![DEL_50 F-score — giabHC](HIOa_fscore_del_50_giabhc.png)

### DEL_gt50 (giabHC)

![DEL_gt50 F-score — giabHC](HIOa_fscore_del_gt50_giabhc.png)

### Indel_50 (giabHC)

![Indel_50 F-score — giabHC](HIOa_fscore_indel_50_giabhc.png)

### Indel_gt50 (giabHC)

![Indel_gt50 F-score — giabHC](HIOa_fscore_indel_gt50_giabhc.png)

### All (giabHC)

![All F-score — giabHC](HIOa_fscore_all_giabhc.png)

---

## F-score Heatmaps — ClinVar Genes

### SNPts (ClinVar Genes)

![SNPts F-score — ClinVar Genes](HIOa_fscore_snpts_clinvar_genes.png)

### SNPtv (ClinVar Genes)

![SNPtv F-score — ClinVar Genes](HIOa_fscore_snptv_clinvar_genes.png)

### INS_50 (ClinVar Genes)

![INS_50 F-score — ClinVar Genes](HIOa_fscore_ins_50_clinvar_genes.png)

### INS_gt50 (ClinVar Genes)

![INS_gt50 F-score — ClinVar Genes](HIOa_fscore_ins_gt50_clinvar_genes.png)

### DEL_50 (ClinVar Genes)

![DEL_50 F-score — ClinVar Genes](HIOa_fscore_del_50_clinvar_genes.png)

### DEL_gt50 (ClinVar Genes)

![DEL_gt50 F-score — ClinVar Genes](HIOa_fscore_del_gt50_clinvar_genes.png)

### Indel_50 (ClinVar Genes)

![Indel_50 F-score — ClinVar Genes](HIOa_fscore_indel_50_clinvar_genes.png)

### Indel_gt50 (ClinVar Genes)

![Indel_gt50 F-score — ClinVar Genes](HIOa_fscore_indel_gt50_clinvar_genes.png)

### All (ClinVar Genes)

![All F-score — ClinVar Genes](HIOa_fscore_all_clinvar_genes.png)

---

## F-score Heatmaps — hg38 whole genome

### SNPts (hg38 whole genome)

![SNPts F-score — hg38 whole genome](HIOa_fscore_snpts_hg38.png)

### SNPtv (hg38 whole genome)

![SNPtv F-score — hg38 whole genome](HIOa_fscore_snptv_hg38.png)

### INS_50 (hg38 whole genome)

![INS_50 F-score — hg38 whole genome](HIOa_fscore_ins_50_hg38.png)

### INS_gt50 (hg38 whole genome)

![INS_gt50 F-score — hg38 whole genome](HIOa_fscore_ins_gt50_hg38.png)

### DEL_50 (hg38 whole genome)

![DEL_50 F-score — hg38 whole genome](HIOa_fscore_del_50_hg38.png)

### DEL_gt50 (hg38 whole genome)

![DEL_gt50 F-score — hg38 whole genome](HIOa_fscore_del_gt50_hg38.png)

### Indel_50 (hg38 whole genome)

![Indel_50 F-score — hg38 whole genome](HIOa_fscore_indel_50_hg38.png)

### Indel_gt50 (hg38 whole genome)

![Indel_gt50 F-score — hg38 whole genome](HIOa_fscore_indel_gt50_hg38.png)

### All (hg38 whole genome)

![All F-score — hg38 whole genome](HIOa_fscore_all_hg38.png)


---

## Runtime Heatmap

Total wall-clock time per unit (all stages: alignment, dedup, variant calling, concordance).

![Runtime Heatmap](HIOa_runtime_heatmap.png)

### Runtime Matrix (minutes)

| SR \ ONT | 0x
(ILMN only) | 0.5x
(tgt 1x) | 1.6x
(tgt 3x) | 3.6x
(tgt 7x) | 5.2x
(tgt 10x) | 7.8x
(tgt 15x) | 10.4x
(tgt 20x) |
|---|---|---|---|---|---|---|---|
| **0x** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **1x** | ✗ | 181 | 1 | 1 | 1 | 2 | 2 |
| **3x** | ✗ | 205 | 313 | 1 | 1 | 2 | 2 |
| **5x** | ✗ | 139 | 195 | 1 | 1 | 2 | 2 |
| **7x** | ✗ | 186 | 195 | 1 | 1 | 2 | 2 |
| **10x** | ✗ | 0 | 1 | 1 | 1 | 2 | 2 |
| **15x** | ✗ | 206 | 305 | 367 | 1 | 2 | 2 |
| **20x** | ✗ | 186 | 304 | 309 | 367 | 2 | 2 |
| **30x** | ✗ | 758 | 725 | 335 | 369 | 2 | 2 |
| **40x** | ✗ | 0 | 356 | 368 | 1 | 782 | 2 |

---

## Cost Heatmap

Total compute cost per unit (USD, pro-rated by thread allocation on shared nodes).

![Cost Heatmap](HIOa_cost_heatmap.png)

### Cost Matrix (USD)

| SR \ ONT | 0x
(ILMN only) | 0.5x
(tgt 1x) | 1.6x
(tgt 3x) | 3.6x
(tgt 7x) | 5.2x
(tgt 10x) | 7.8x
(tgt 15x) | 10.4x
(tgt 20x) |
|---|---|---|---|---|---|---|---|
| **0x** | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **1x** | ✗ | $7.86 | $0.00 | $0.01 | $0.01 | $0.02 | $0.02 |
| **3x** | ✗ | $8.64 | $13.85 | $0.01 | $0.01 | $0.02 | $0.02 |
| **5x** | ✗ | $5.31 | $9.54 | $0.01 | $0.01 | $0.02 | $0.02 |
| **7x** | ✗ | $7.51 | $9.55 | $0.01 | $0.01 | $0.02 | $0.02 |
| **10x** | ✗ | $0.00 | $0.00 | $0.01 | $0.01 | $0.02 | $0.02 |
| **15x** | ✗ | $8.40 | $13.25 | $16.25 | $0.01 | $0.02 | $0.02 |
| **20x** | ✗ | $7.38 | $13.21 | $13.32 | $16.18 | $0.02 | $0.02 |
| **30x** | ✗ | $35.46 | $33.83 | $14.65 | $16.28 | $0.02 | $0.02 |
| **40x** | ✗ | $0.00 | $15.73 | $16.26 | $0.01 | $36.49 | $0.02 |

---

## Summary Statistics (completed units only)

| Metric | Min | Mean | Median | Max |
|---|---|---|---|---|
| SNPts Fscore | 0.3271 | 0.9111 | 0.9907 | 0.9973 |
| Runtime (min) | 0 | 133 | 2 | 782 |
| Cost (USD) | $0.00 | $5.91 | $0.02 | $36.49 |

**Total cost (all units with data)**: $319.39

**Total runtime (all units with data)**: 120.1 hours

---

## Key Observations

- **Best SNPts F-score**: SR40x-ONT0x = **0.9973**
- **Worst SNPts F-score**: SR1x-ONT0x = **0.3271**
- **Cheapest unit**: SR10x-ONT1x = **$0.00**
- **Most expensive unit**: SR40x-ONT15x = **$36.49**
- **Failed units**: 30/63 (48%)
- **Still running**: 5/63

### Failed Units

| Unit | Failure Reason |
|---|---|
| SR1x-ONT3x | sentdhio_snv failed (no diagnostic) |
| SR1x-ONT7x | sentdhio_snv failed (no diagnostic) |
| SR1x-ONT10x | sentdhio_snv failed (no diagnostic) |
| SR1x-ONT15x | sentdhio_snv failed (no diagnostic) |
| SR1x-ONT20x | sentdhio_snv failed (no diagnostic) |
| SR3x-ONT7x | sentdhio_snv failed (no diagnostic) |
| SR3x-ONT10x | sentdhio_snv failed (no diagnostic) |
| SR3x-ONT15x | sentdhio_snv failed (no diagnostic) |
| SR3x-ONT20x | sentdhio_snv failed (no diagnostic) |
| SR5x-ONT7x | sentdhio_snv failed (no diagnostic) |
| SR5x-ONT10x | sentdhio_snv failed (no diagnostic) |
| SR5x-ONT15x | sentdhio_snv failed (no diagnostic) |
| SR5x-ONT20x | sentdhio_snv failed (no diagnostic) |
| SR7x-ONT7x | sentdhio_snv failed (no diagnostic) |
| SR7x-ONT15x | sentdhio_snv failed (no diagnostic) |
| SR7x-ONT20x | sentdhio_snv failed (no diagnostic) |
| SR10x-ONT1x | sentdhio_snv failed (no diagnostic) |
| SR10x-ONT3x | sentdhio_snv failed (no diagnostic) |
| SR10x-ONT7x | sentdhio_snv failed (no diagnostic) |
| SR10x-ONT15x | Spot reclamation |
| SR10x-ONT20x | Spot reclamation |
| SR15x-ONT10x | Spot reclamation |
| SR15x-ONT15x | sentdhio_snv failed (no diagnostic) |
| SR15x-ONT20x | sentdhio_snv failed (no diagnostic) |
| SR20x-ONT15x | Spot reclamation |
| SR20x-ONT20x | Spot reclamation |
| SR30x-ONT15x | Spot reclamation |
| SR30x-ONT20x | Spot reclamation |
| SR40x-ONT1x | Spot reclamation |
| SR40x-ONT20x | sentdhio_snv failed (no diagnostic) |

