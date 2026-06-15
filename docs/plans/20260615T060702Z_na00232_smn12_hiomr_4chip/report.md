# NA00232 SMN12 Four-Chip HiOMR Gate Report

Created: 2026-06-15T06:17:00Z

## Outcome

The requested `NA00232` run was not launched.

Reason: exact `NA00232` ONT chip3 barcode18 data is absent. The current headnode has the ILMN 20x FASTQs and ONT chip1, chip2, and chip4 barcode18 data, but not chip3 barcode18. I did not substitute chip4-only or run a three-chip analysis under the four-chip request.

## Evidence

Inspection command:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_inspect_inputs_runtime.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_inspect_inputs_runtime.json
```

- SSM command id: `bae50010-f7b0-41dd-af19-79fe915eed0f`
- Cluster/headnode: `dyecX4`, `i-05815cdeec4a6dad8`
- ILMN R1/R2 exist:
  - `NA00232-SMN_S46_ds20x_R1_001.fastq.gz`, `17262515732` bytes
  - `NA00232-SMN_S46_ds20x_R2_001.fastq.gz`, `17800937474` bytes
- Staged ONT barcode18 counts:
  - `chip1`: `73`
  - `chip2`: `73`
  - `chip3`: `0`
  - `chip4`: `73`
- Bounded raw mount check:
  - `/fsx/run_dir_mounts/20260513_ONT_HG003` has only one barcode18 FASTQ, `1556` bytes, from `PBM13745`.
  - It has zero barcode18 FASTQs for the staged 4NA chip flowcell names `PBM13545`, `PBM14931`, and `PBM13048`.

## Runtime Gate

Current runtime assets are visible on FSx:

- Sentieon runtime root: `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03`
- `SentieonIlluminaWGS2.2.bundle`, `127015170` bytes
- `DNAscopeONT2.3.bundle`, `925744416` bytes
- HapSMA SMN support BEDs, Clair3 R10 model files, and hg38_broad map-ont `.mmi`

Local DayOA `jem-dev` per-rule env YAMLs pin `sentieon=202503.03`, `sentieon-cli==1.6.3`, and `segdup-caller@v0.6.0`.

## Comparison Boundary

No new caller comparison is possible from this request because the four-chip analysis did not run.

The prior `NA00232` evidence remains:

| unit | sentieon stack | smncopy | sentieon segdup | sma_finder | hapsma |
| --- | --- | --- | --- | --- | --- |
| chip1-chip2 | 202503.02 | `0/1` | `0/1` | `has SMA` | mean SMN coverage `7.71`, no-call/no-phase-set |
| chip4-only-sub-for-missing-chip3 | 202503.02 | `0/1` | `0/1` | `has SMA` | mean SMN coverage `3.32`, no-call/low-coverage |

A current-stack higher-coverage assessment requires actual `NA00232` chip3 barcode18 input or explicit approval to run a non-four-chip substitute.
