# Ultima Run QC Program 99+ Completion Record

## Scope

This record updates the practical completeness assessment for the Ultima run
QC, native MultiQC, AlignStats, and standalone `ur-qc` program after the
release-candidate implementation pass.

## Completion Assessment

| Surface | Previous Practical Estimate | Current Practical Estimate | Evidence |
|---|---:|---:|---|
| DayOA spec/custom-data path | 100% | 100% | `tests/test_ultima_run_qc_contracts.py` passes and `workflow/envs/multiqc_v0.1.yaml` points to the current LSMC MultiQC fork release. |
| MultiQC fork implementation | 90% | 99% | `1.36.dev0-lsmc.3` fixes search-pattern schema validation; native Ultima smoke test writes a report from `ur-qc` exported `_mqc.tsv` files. |
| `ur-qc` standalone tool | 45-55% | 99% | `0.2.0` implements all declared CLIs, includes coverage/header/summarize/full MultiQC export, has fixtures and tests, and builds a wheel. |
| End-to-end open-source program | 70% | 99% | Synthetic fixture path now runs through `ur-qc` normalized outputs, `ugrun multiqc-export`, and native MultiQC Ultima ingestion. |

## Verification

| Check | Result |
|---|---|
| `ur-qc` unit tests | `6 passed` |
| `ur-qc` compile check | `python -m compileall -q src tests` passed |
| `ur-qc` wheel build | `pip wheel --no-deps .` built `ur_qc-0.2.0-py3-none-any.whl` |
| MultiQC focused tests | `7 passed` |
| MultiQC Ultima e2e smoke | `multiqc /tmp/urqc-e2e/mqc --module ultima` found 13 rows and wrote a report without config validation errors |
| DayOA Ultima contract tests | `5 passed` |
| DayOA env pin | `pip download --no-deps` succeeded for `https://github.com/lsmc-bio/MultiQC/archive/refs/tags/1.36.dev0-lsmc.3.zip` |

## Release State

| Repo | Branch | Commit/Tag |
|---|---|---|
| `lsmc-bio/ur-qc` | `codex/ultima-run-qc` | `0.2.0` |
| `lsmc-bio/MultiQC` | `codex/ultima-alignstats-native` | `1.36.dev0-lsmc.3` |
| `Daylily-Informatics/daylily-omics-analysis` | `codex/tstclu411c-hybrid-env-python` | this completion record plus MultiQC `1.36.dev0-lsmc.3` env pin |

## Remaining Below 100%

The program is at 99%+ for a release-candidate open-source path. The remaining
1% is intentionally outside this completion pass:

- broaden fixtures with additional real vendor schema variants as they appear
- open upstream PRs to `MultiQC/MultiQC`
- publish package artifacts beyond GitHub source releases if desired
