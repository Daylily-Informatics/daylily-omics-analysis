# NA00232 SMN12 HiOMR Chip1+2+4 Report

Created: 2026-06-15T07:55:00Z

## Outcome

The original exact four-chip request remains blocked because `NA00232` ONT chip3 barcode18 data is absent.

After user approval, I ran the approved substitute:

- ILMN 20x `NA00232`
- ONT chip1 + chip2 + chip4 barcode18
- 219 ONT FASTQs total
- current DayOA `jem-dev` checkout `13b324a52ba8a5b2edb12dd685403c8e8cddd6c2`
- Sentieon `202503.03`, `sentieon-cli==1.6.3`, `segdup-caller==0.6.0`
- Sentieon HiOMR segdup restricted to `SMN1`
- HTD callers `smn12`, `smaca`, `sma_finder`, `hapsma`

The live DayOA run completed successfully: `20 of 20 steps (100%) done`, `WORKFLOW SUCCESS`, `RETURN CODE: 0`.

## Result Summary

| caller | result | evidence |
| --- | --- | --- |
| SMNCopyNumberCaller / `smn12` | `SMN1=0`, `SMN2=1`, `isSMA=true`, `PASS:Majority`, median depth `27.33` | `ssm_collect_chip124_results.json` |
| Sentieon HiOMR segdup SMN1 | `SMN1=0`, `SMN2=1`; `sentieon=202503.03`; `segdup-caller=0.6.0` | `SMN1.yaml`, collected in `ssm_collect_chip124_results.json` |
| Broad `sma_finder` | `has SMA`, confidence `13`, `0/14` C840 reads with SMN1 base C | `sma_finder.summary.json`, collected |
| HapSMA | mean SMN-region coverage `11.031685`; still `NO_PHASE_SET` / `no_call_no_phase_set` | `hapsma.summary.tsv`, collected |
| SMAca | completed; MQC row did not expose direct SMN1/SMN2 CN fields; summary coverage has avg `SMN1=4.7176`, avg `SMN2=7.0050` | `smaca.summary.tsv`, collected |

The orthogonal MQC table marks rows `discordant` because some callers report affected status or no direct CN rather than all reporting the same CN pair. The decisive CN/status callers are directionally concordant for the expected SMA-positive sample.

## Comparison

Prior `NA00232` evidence from the 202503.02 two-unit run:

| unit | stack | SMNCopy | Sentieon segdup | sma_finder | HapSMA |
| --- | --- | --- | --- | --- | --- |
| chip1+chip2 | 202503.02 | `0/1` | `0/1` | `has SMA` | mean coverage `7.71`, no-call/no-phase-set |
| chip4-only substitute | 202503.02 | `0/1` | `0/1` | `has SMA` | mean coverage `3.32`, no-call/low-coverage |
| chip1+chip2+chip4 | 202503.03 | `0/1`, `PASS:Majority` | `0/1` | `has SMA` | mean coverage `11.031685`, still no-call/no-phase-set |

Conclusion: the new Sentieon stack plus higher ONT coverage did not change the main SMA-positive interpretation because SMNCopy, Sentieon segdup, and sma-finder were already calling the expected result. It did improve HapSMA coverage over both prior units, but HapSMA still did not produce a usable phase-set call.

## Evidence Files

- Live success poll: `ssm_poll_live_chip124_9.json`, SSM `96bcb7cf-9873-4522-81a1-e568d7647e8f`
- Result collection: `ssm_collect_chip124_results.json`, SSM `ed1d97c4-d9bd-4d0a-93b8-3244ea3152b0`
- Config metadata: `chip124_manifest_metadata.json`
- Samples/units: `samples_chip124.tsv`, `units_chip124.tsv`
- Remote workdir: `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis`
