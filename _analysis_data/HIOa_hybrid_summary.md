# HIOa Hybrid ILMN+ONT Workflow Summary Report

**Generated**: 2026-02-18 11:59:03

**Genome Build**: hg38_broad

**Sample**: HG003 (Ashkenazi Jewish Father)

**Matrix**: 9 ILMN coverages (1x–40x) × 7 ONT coverages (1x–30x) = 63 units

**Workflow Config**: `-T 1 -j 20 -k -p` (1 retry, 20 concurrent jobs)

## Unit Status Summary

| Status | Count |
|---|---|
| ✅ Complete | 12 |
| 🔄 In Progress | 12 |
| ❌ Failed/Pending | 39 |
| **Total** | **63** |

### Status Matrix (SR↓ × ONT→)

| SR \ ONT | 1x | 3x | 7x | 10x | 15x | 20x | 30x |
|---|---|---|---|---|---|---|---|
| **1x** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **3x** | ✅ | 🔄 | ❌ | ❌ | ❌ | ❌ | ❌ |
| **5x** | 🔄 | 🔄 | ❌ | ❌ | ❌ | ❌ | ❌ |
| **7x** | 🔄 | 🔄 | ❌ | 🔄 | ❌ | ❌ | ❌ |
| **10x** | ❌ | ❌ | ❌ | 🔄 | ❌ | ❌ | ❌ |
| **15x** | ✅ | 🔄 | 🔄 | ❌ | ❌ | ❌ | ❌ |
| **20x** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **30x** | ✅ | ✅ | ✅ | 🔄 | ❌ | ❌ | ❌ |
| **40x** | ❌ | ✅ | 🔄 | 🔄 | ✅ | ❌ | ❌ |

## Concordance Metrics (giabHC footprint, completed units)

### F-scores by Variant Class

| Unit | SNPts | SNPtv | DEL_50 | INS_50 | Indel_50 |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.1799 | 0.1391 | 0.2084 | 0.2038 | 0.1305 |
| SR3x-ONT1x | 0.2607 | 0.2039 | 0.2465 | 0.2447 | 0.2797 |
| SR15x-ONT1x | 0.3078 | 0.2331 | 0.2415 | 0.2412 | 0.3219 |
| SR20x-ONT1x | 0.3126 | 0.2345 | 0.2400 | 0.2399 | 0.3191 |
| SR20x-ONT3x | 0.2992 | 0.2200 | 0.2383 | 0.2382 | 0.3190 |
| SR20x-ONT7x | 0.2859 | 0.2057 | 0.2362 | 0.2360 | 0.3187 |
| SR20x-ONT10x | 0.2805 | 0.1999 | 0.2352 | 0.2349 | 0.3187 |
| SR30x-ONT1x | 0.3202 | 0.2374 | 0.2387 | 0.2391 | 0.3128 |
| SR30x-ONT3x | 0.3070 | 0.2238 | 0.2375 | 0.2378 | 0.3129 |
| SR30x-ONT7x | 0.2930 | 0.2095 | 0.2354 | 0.2355 | 0.3128 |
| SR40x-ONT3x | 0.3124 | 0.2262 | 0.2378 | 0.2377 | 0.3092 |
| SR40x-ONT15x | 0.2854 | 0.2001 | 0.2336 | 0.2334 | 0.3088 |

### Detailed Metrics (Precision / Recall / FN / FP)

#### SNPts

| Unit | Fscore | Precision | Recall | FN | FP |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.1799 | 0.1369 | 0.2623 | 50,151 | 112,454 |
| SR3x-ONT1x | 0.2607 | 0.1675 | 0.5870 | 28,061 | 198,175 |
| SR15x-ONT1x | 0.3078 | 0.1852 | 0.9094 | 6,134 | 270,976 |
| SR20x-ONT1x | 0.3126 | 0.1884 | 0.9184 | 5,528 | 267,979 |
| SR20x-ONT3x | 0.2992 | 0.1784 | 0.9269 | 4,947 | 289,127 |
| SR20x-ONT7x | 0.2859 | 0.1686 | 0.9385 | 4,166 | 313,277 |
| SR20x-ONT10x | 0.2805 | 0.1648 | 0.9414 | 3,970 | 323,061 |
| SR30x-ONT1x | 0.3202 | 0.1937 | 0.9225 | 5,246 | 260,113 |
| SR30x-ONT3x | 0.3070 | 0.1838 | 0.9305 | 4,706 | 279,720 |
| SR30x-ONT7x | 0.2930 | 0.1735 | 0.9393 | 4,108 | 302,892 |
| SR40x-ONT3x | 0.3124 | 0.1877 | 0.9302 | 4,730 | 272,588 |
| SR40x-ONT15x | 0.2854 | 0.1680 | 0.9456 | 3,682 | 317,010 |

#### SNPtv

| Unit | Fscore | Precision | Recall | FN | FP |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.1391 | 0.0949 | 0.2605 | 25,986 | 87,272 |
| SR3x-ONT1x | 0.2039 | 0.1233 | 0.5891 | 14,434 | 147,165 |
| SR15x-ONT1x | 0.2331 | 0.1338 | 0.9063 | 3,277 | 205,277 |
| SR20x-ONT1x | 0.2345 | 0.1345 | 0.9143 | 2,995 | 205,685 |
| SR20x-ONT3x | 0.2200 | 0.1248 | 0.9241 | 2,653 | 226,501 |
| SR20x-ONT7x | 0.2057 | 0.1156 | 0.9359 | 2,241 | 250,352 |
| SR20x-ONT10x | 0.1999 | 0.1119 | 0.9380 | 2,166 | 260,195 |
| SR30x-ONT1x | 0.2374 | 0.1363 | 0.9206 | 2,774 | 203,917 |
| SR30x-ONT3x | 0.2238 | 0.1272 | 0.9281 | 2,513 | 222,488 |
| SR30x-ONT7x | 0.2095 | 0.1179 | 0.9368 | 2,208 | 244,827 |
| SR40x-ONT3x | 0.2262 | 0.1289 | 0.9267 | 2,561 | 219,043 |
| SR40x-ONT15x | 0.2001 | 0.1119 | 0.9435 | 1,975 | 261,606 |

#### DEL_50

| Unit | Fscore | Precision | Recall | FN | FP |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.2084 | 0.1480 | 0.3516 | 18,471 | 57,658 |
| SR3x-ONT1x | 0.2465 | 0.1515 | 0.6601 | 9,938 | 108,045 |
| SR15x-ONT1x | 0.2415 | 0.1386 | 0.9345 | 1,798 | 159,456 |
| SR20x-ONT1x | 0.2400 | 0.1375 | 0.9449 | 1,503 | 161,545 |
| SR20x-ONT3x | 0.2383 | 0.1363 | 0.9477 | 1,425 | 163,771 |
| SR20x-ONT7x | 0.2362 | 0.1348 | 0.9520 | 1,308 | 166,556 |
| SR20x-ONT10x | 0.2352 | 0.1341 | 0.9544 | 1,242 | 167,936 |
| SR30x-ONT1x | 0.2387 | 0.1365 | 0.9495 | 1,368 | 162,794 |
| SR30x-ONT3x | 0.2375 | 0.1356 | 0.9531 | 1,272 | 164,686 |
| SR30x-ONT7x | 0.2354 | 0.1342 | 0.9565 | 1,180 | 167,276 |
| SR40x-ONT3x | 0.2378 | 0.1359 | 0.9538 | 1,251 | 164,291 |
| SR40x-ONT15x | 0.2336 | 0.1330 | 0.9598 | 1,090 | 169,579 |

#### INS_50

| Unit | Fscore | Precision | Recall | FN | FP |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.2038 | 0.1479 | 0.3278 | 18,945 | 53,216 |
| SR3x-ONT1x | 0.2447 | 0.1515 | 0.6357 | 10,440 | 102,035 |
| SR15x-ONT1x | 0.2412 | 0.1388 | 0.9221 | 2,126 | 156,106 |
| SR20x-ONT1x | 0.2399 | 0.1377 | 0.9326 | 1,833 | 158,764 |
| SR20x-ONT3x | 0.2382 | 0.1364 | 0.9376 | 1,698 | 161,358 |
| SR20x-ONT7x | 0.2360 | 0.1349 | 0.9432 | 1,544 | 164,585 |
| SR20x-ONT10x | 0.2349 | 0.1341 | 0.9445 | 1,509 | 165,851 |
| SR30x-ONT1x | 0.2391 | 0.1369 | 0.9404 | 1,615 | 160,479 |
| SR30x-ONT3x | 0.2378 | 0.1360 | 0.9448 | 1,497 | 162,661 |
| SR30x-ONT7x | 0.2355 | 0.1344 | 0.9492 | 1,378 | 165,677 |
| SR40x-ONT3x | 0.2377 | 0.1359 | 0.9460 | 1,460 | 162,735 |
| SR40x-ONT15x | 0.2334 | 0.1330 | 0.9527 | 1,281 | 168,122 |

#### Indel_50

| Unit | Fscore | Precision | Recall | FN | FP |
|---|---|---|---|---|---|
| SR1x-ONT1x | 0.1305 | 0.1821 | 0.1017 | 6,228 | 3,166 |
| SR3x-ONT1x | 0.2797 | 0.1876 | 0.5492 | 2,682 | 14,147 |
| SR15x-ONT1x | 0.3219 | 0.1936 | 0.9531 | 430 | 36,383 |
| SR20x-ONT1x | 0.3191 | 0.1913 | 0.9612 | 366 | 38,370 |
| SR20x-ONT3x | 0.3190 | 0.1912 | 0.9621 | 357 | 38,381 |
| SR20x-ONT7x | 0.3187 | 0.1910 | 0.9620 | 359 | 38,456 |
| SR20x-ONT10x | 0.3187 | 0.1910 | 0.9624 | 355 | 38,460 |
| SR30x-ONT1x | 0.3128 | 0.1866 | 0.9660 | 328 | 40,672 |
| SR30x-ONT3x | 0.3129 | 0.1867 | 0.9667 | 321 | 40,650 |
| SR30x-ONT7x | 0.3128 | 0.1866 | 0.9663 | 325 | 40,691 |
| SR40x-ONT3x | 0.3092 | 0.1840 | 0.9686 | 304 | 41,663 |
| SR40x-ONT15x | 0.3088 | 0.1836 | 0.9701 | 289 | 41,752 |

### Summary Statistics (across completed units)

| Variant Class | Mean Fscore | Median Fscore | Min Fscore | Max Fscore |
|---|---|---|---|---|
| SNPts | 0.2870 | 0.2992 | 0.1799 | 0.3202 |
| SNPtv | 0.2111 | 0.2200 | 0.1391 | 0.2374 |
| DEL_50 | 0.2358 | 0.2378 | 0.2084 | 0.2465 |
| INS_50 | 0.2352 | 0.2378 | 0.2038 | 0.2447 |
| Indel_50 | 0.2970 | 0.3129 | 0.1305 | 0.3219 |

## Coverage Metrics (all units)

| Unit | WgsCoverageMean | WgsCoverageMedian | Status |
|---|---|---|---|
| SR1x-ONT1x | 0.52 | 0 | ✅ |
| SR1x-ONT3x | 1.56 | 1 | ❌ |
| SR1x-ONT7x | 3.64 | 3 | ❌ |
| SR1x-ONT10x | 5.20 | 5 | ❌ |
| SR1x-ONT15x | 7.80 | 8 | ❌ |
| SR1x-ONT20x | 10.35 | 10 | ❌ |
| SR1x-ONT30x | 15.64 | 16 | ❌ |
| SR3x-ONT1x | 0.52 | 0 | ✅ |
| SR3x-ONT3x | 1.56 | 1 | 🔄 |
| SR3x-ONT7x | 3.64 | 3 | ❌ |
| SR3x-ONT10x | 5.20 | 5 | ❌ |
| SR3x-ONT15x | 7.80 | 8 | ❌ |
| SR3x-ONT20x | 10.35 | 10 | ❌ |
| SR3x-ONT30x | 15.64 | 16 | ❌ |
| SR5x-ONT1x | 0.52 | 0 | 🔄 |
| SR5x-ONT3x | 1.56 | 1 | 🔄 |
| SR5x-ONT7x | 3.64 | 3 | ❌ |
| SR5x-ONT10x | 5.20 | 5 | ❌ |
| SR5x-ONT15x | 7.80 | 8 | ❌ |
| SR5x-ONT20x | 10.35 | 10 | ❌ |
| SR5x-ONT30x | 15.64 | 16 | ❌ |
| SR7x-ONT1x | 0.52 | 0 | 🔄 |
| SR7x-ONT3x | 1.56 | 1 | 🔄 |
| SR7x-ONT7x | 3.64 | 3 | ❌ |
| SR7x-ONT10x | 5.20 | 5 | 🔄 |
| SR7x-ONT15x | 7.80 | 8 | ❌ |
| SR7x-ONT20x | 10.35 | 10 | ❌ |
| SR7x-ONT30x | 15.64 | 16 | ❌ |
| SR10x-ONT1x | 0.52 | 0 | ❌ |
| SR10x-ONT3x | 1.56 | 1 | ❌ |
| SR10x-ONT7x | 3.64 | 3 | ❌ |
| SR10x-ONT10x | 5.20 | 5 | 🔄 |
| SR10x-ONT15x | 7.80 | 8 | ❌ |
| SR10x-ONT20x | 10.35 | 10 | ❌ |
| SR10x-ONT30x | 15.64 | 16 | ❌ |
| SR15x-ONT1x | 0.52 | 0 | ✅ |
| SR15x-ONT3x | 1.56 | 1 | 🔄 |
| SR15x-ONT7x | 3.64 | 3 | 🔄 |
| SR15x-ONT10x | 5.20 | 5 | ❌ |
| SR15x-ONT15x | 7.80 | 8 | ❌ |
| SR15x-ONT20x | 10.35 | 10 | ❌ |
| SR15x-ONT30x | 15.64 | 16 | ❌ |
| SR20x-ONT1x | 0.52 | 0 | ✅ |
| SR20x-ONT3x | 1.56 | 1 | ✅ |
| SR20x-ONT7x | 3.64 | 3 | ✅ |
| SR20x-ONT10x | 5.20 | 5 | ✅ |
| SR20x-ONT15x | 7.80 | 8 | ❌ |
| SR20x-ONT20x | 10.35 | 10 | ❌ |
| SR20x-ONT30x | 15.64 | 16 | ❌ |
| SR30x-ONT1x | 0.52 | 0 | ✅ |
| SR30x-ONT3x | 1.56 | 1 | ✅ |
| SR30x-ONT7x | 3.64 | 3 | ✅ |
| SR30x-ONT10x | 5.20 | 5 | 🔄 |
| SR30x-ONT15x | 7.80 | 8 | ❌ |
| SR30x-ONT20x | 10.35 | 10 | ❌ |
| SR30x-ONT30x | 15.64 | 16 | ❌ |
| SR40x-ONT1x | 0.52 | 0 | ❌ |
| SR40x-ONT3x | 1.56 | 1 | ✅ |
| SR40x-ONT7x | 3.64 | 3 | 🔄 |
| SR40x-ONT10x | 5.20 | 5 | 🔄 |
| SR40x-ONT15x | 7.80 | 8 | ✅ |
| SR40x-ONT20x | 10.35 | 10 | ❌ |
| SR40x-ONT30x | 15.64 | 16 | ❌ |

## Compute Benchmarks

**Total cost across all units**: $283.29

**Total wall time across all units**: 104.2 hours

### Per-Unit Cost & Runtime (completed units)

| Unit | Status | Total Cost | Total Wall (min) | VC Cost | VC Wall (min) | Conc Cost | Conc Wall (min) |
|---|---|---|---|---|---|---|---|
| SR1x-ONT1x | ✅ | $7.86 | 181.5 | $7.86 | 181.1 | $0.00 | 0.0 |
| SR1x-ONT3x | ❌ | $0.00 | 0.6 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR1x-ONT7x | ❌ | $0.01 | 1.0 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR1x-ONT10x | ❌ | $0.01 | 1.3 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR1x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR1x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR1x-ONT30x | ❌ | $0.02 | 2.8 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT1x | ✅ | $8.64 | 204.8 | $8.64 | 204.4 | $0.00 | 0.0 |
| SR3x-ONT3x | 🔄 | $0.00 | 0.6 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT7x | ❌ | $0.01 | 1.0 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT10x | ❌ | $0.01 | 1.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR3x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT1x | 🔄 | $4.80 | 98.3 | $4.80 | 98.0 | $0.00 | 0.0 |
| SR5x-ONT3x | 🔄 | $0.00 | 0.6 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT7x | ❌ | $0.01 | 1.0 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT10x | ❌ | $0.01 | 1.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR5x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT1x | 🔄 | $6.98 | 142.6 | $6.98 | 142.2 | $0.00 | 0.0 |
| SR7x-ONT3x | 🔄 | $0.00 | 0.6 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT7x | ❌ | $0.01 | 1.0 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT10x | 🔄 | $0.01 | 1.3 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR7x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT1x | ❌ | $0.00 | 0.3 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT3x | ❌ | $0.00 | 0.6 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT7x | ❌ | $0.01 | 1.0 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT10x | 🔄 | $0.01 | 1.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR10x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR15x-ONT1x | ✅ | $8.40 | 206.1 | $8.40 | 205.8 | $0.00 | 0.0 |
| SR15x-ONT3x | 🔄 | $12.68 | 258.9 | $12.68 | 258.4 | $0.00 | 0.0 |
| SR15x-ONT7x | 🔄 | $15.66 | 320.1 | $15.66 | 319.1 | $0.00 | 0.0 |
| SR15x-ONT10x | ❌ | $0.01 | 1.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR15x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR15x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR15x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR20x-ONT1x | ✅ | $7.38 | 185.6 | $7.37 | 185.2 | $0.00 | 0.0 |
| SR20x-ONT3x | ✅ | $13.21 | 304.5 | $13.20 | 303.9 | $0.00 | 0.0 |
| SR20x-ONT7x | ✅ | $13.32 | 308.5 | $13.31 | 307.5 | $0.00 | 0.0 |
| SR20x-ONT10x | ✅ | $16.18 | 366.9 | $16.17 | 365.5 | $0.00 | 0.0 |
| SR20x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR20x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR20x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR30x-ONT1x | ✅ | $35.46 | 757.6 | $35.46 | 757.3 | $0.00 | 0.0 |
| SR30x-ONT3x | ✅ | $33.83 | 725.1 | $33.82 | 724.6 | $0.00 | 0.0 |
| SR30x-ONT7x | ✅ | $14.65 | 335.0 | $14.64 | 334.0 | $0.00 | 0.0 |
| SR30x-ONT10x | 🔄 | $15.70 | 320.9 | $15.69 | 319.6 | $0.00 | 0.0 |
| SR30x-ONT15x | ❌ | $0.02 | 1.9 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR30x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR30x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR40x-ONT1x | ❌ | $0.00 | 0.3 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR40x-ONT3x | ✅ | $15.73 | 356.0 | $15.73 | 355.4 | $0.00 | 0.0 |
| SR40x-ONT7x | 🔄 | $15.68 | 320.3 | $15.67 | 319.3 | $0.00 | 0.0 |
| SR40x-ONT10x | 🔄 | $0.01 | 1.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR40x-ONT15x | ✅ | $36.49 | 781.6 | $36.48 | 779.7 | $0.00 | 0.0 |
| SR40x-ONT20x | ❌ | $0.02 | 2.4 | $0.00 | 0.0 | $0.00 | 0.0 |
| SR40x-ONT30x | ❌ | $0.02 | 2.5 | $0.00 | 0.0 | $0.00 | 0.0 |

## Failed Units

| Unit | SR Cov | ONT Cov | Failure Reason |
|---|---|---|---|
| SR1x-ONT3x | 1x | 3x | sentdhio_snv failed (no diagnostic output) |
| SR1x-ONT7x | 1x | 7x | sentdhio_snv failed (no diagnostic output) |
| SR1x-ONT10x | 1x | 10x | sentdhio_snv failed (no diagnostic output) |
| SR1x-ONT15x | 1x | 15x | sentdhio_snv failed (no diagnostic output) |
| SR1x-ONT20x | 1x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR1x-ONT30x | 1x | 30x | sentdhio_snv failed (no diagnostic output) |
| SR3x-ONT7x | 3x | 7x | sentdhio_snv failed (no diagnostic output) |
| SR3x-ONT10x | 3x | 10x | sentdhio_snv failed (no diagnostic output) |
| SR3x-ONT15x | 3x | 15x | sentdhio_snv failed (no diagnostic output) |
| SR3x-ONT20x | 3x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR3x-ONT30x | 3x | 30x | sentdhio_snv failed (no diagnostic output) |
| SR5x-ONT7x | 5x | 7x | sentdhio_snv failed (no diagnostic output) |
| SR5x-ONT10x | 5x | 10x | sentdhio_snv failed (no diagnostic output) |
| SR5x-ONT15x | 5x | 15x | sentdhio_snv failed (no diagnostic output) |
| SR5x-ONT20x | 5x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR5x-ONT30x | 5x | 30x | sentdhio_snv failed (no diagnostic output) |
| SR7x-ONT7x | 7x | 7x | sentdhio_snv failed (no diagnostic output) |
| SR7x-ONT15x | 7x | 15x | sentdhio_snv failed (no diagnostic output) |
| SR7x-ONT20x | 7x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR7x-ONT30x | 7x | 30x | sentdhio_snv failed (no diagnostic output) |
| SR10x-ONT1x | 10x | 1x | sentdhio_snv failed (no diagnostic output) |
| SR10x-ONT3x | 10x | 3x | sentdhio_snv failed (no diagnostic output) |
| SR10x-ONT7x | 10x | 7x | sentdhio_snv failed (no diagnostic output) |
| SR10x-ONT15x | 10x | 15x | Spot reclamation |
| SR10x-ONT20x | 10x | 20x | Spot reclamation |
| SR10x-ONT30x | 10x | 30x | Spot reclamation |
| SR15x-ONT10x | 15x | 10x | Spot reclamation |
| SR15x-ONT15x | 15x | 15x | sentdhio_snv failed (no diagnostic output) |
| SR15x-ONT20x | 15x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR15x-ONT30x | 15x | 30x | TMPDIR race condition |
| SR20x-ONT15x | 20x | 15x | Spot reclamation |
| SR20x-ONT20x | 20x | 20x | Spot reclamation |
| SR20x-ONT30x | 20x | 30x | Spot reclamation |
| SR30x-ONT15x | 30x | 15x | Spot reclamation |
| SR30x-ONT20x | 30x | 20x | Spot reclamation |
| SR30x-ONT30x | 30x | 30x | Spot reclamation |
| SR40x-ONT1x | 40x | 1x | Spot reclamation |
| SR40x-ONT20x | 40x | 20x | sentdhio_snv failed (no diagnostic output) |
| SR40x-ONT30x | 40x | 30x | Spot reclamation |

## In-Progress Units

| Unit | SR Cov | ONT Cov |
|---|---|---|
| SR3x-ONT3x | 3x | 3x |
| SR5x-ONT1x | 5x | 1x |
| SR5x-ONT3x | 5x | 3x |
| SR7x-ONT1x | 7x | 1x |
| SR7x-ONT3x | 7x | 3x |
| SR7x-ONT10x | 7x | 10x |
| SR10x-ONT10x | 10x | 10x |
| SR15x-ONT3x | 15x | 3x |
| SR15x-ONT7x | 15x | 7x |
| SR30x-ONT10x | 30x | 10x |
| SR40x-ONT7x | 40x | 7x |
| SR40x-ONT10x | 40x | 10x |

