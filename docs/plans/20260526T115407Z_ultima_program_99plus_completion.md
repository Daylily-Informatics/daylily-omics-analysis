# Ultima Run QC Program 100 Percent Completion Record

## Scope

This record updates the practical completeness assessment for the Ultima run
QC, native MultiQC, AlignStats, and standalone `ur-qc` program after the
release-candidate implementation pass and the final duplicate-sample hardening
pass.

## Completion Assessment

| Surface | Previous Practical Estimate | Current Practical Estimate | Evidence |
|---|---:|---:|---|
| DayOA spec/custom-data path | 100% | 100% | `tests/test_ultima_run_qc_contracts.py` passes and `workflow/envs/multiqc_v0.1.yaml` points to the current LSMC MultiQC fork release. |
| MultiQC fork implementation | 90% | 100% | `1.36.dev0-lsmc.4` keeps the LSMC dark-mode fork behavior, fails duplicate sample IDs by default in core data-source tracking and custom content, removes duplicated Ultima / AlignStats parser logic, and passes strict Ultima e2e smoke. |
| `ur-qc` standalone tool | 45-55% | 100% | `0.3.1` implements all declared CLIs, strict expected-manifest inventory behavior, trimmer histograms, quality quantiles, contamination companion outputs, duplicate-safe MultiQC export, fixtures, tests, and wheel build. |
| End-to-end open-source program | 70% | 100% | Synthetic fixture path now runs through `ur-qc` normalized outputs, `ugrun multiqc-export`, native MultiQC Ultima ingestion under `--strict`, and DayOA installs the tagged LSMC fork release. |

## Verification

| Check | Result |
|---|---|
| `ur-qc` unit tests | `8 passed` |
| `ur-qc` compile check | `python -m compileall -q src tests` passed |
| `ur-qc` wheel build | `pip wheel --no-deps .` built `ur_qc-0.3.1-py3-none-any.whl` |
| MultiQC focused tests | `10 passed` |
| MultiQC Ultima e2e smoke | `multiqc /tmp/urqc-100-e2e/mqc --module ultima --strict` found 17 rows and wrote a report without config validation errors |
| DayOA Ultima contract tests | `5 passed` |
| DayOA env pin | `pip download --no-deps` succeeded for `https://github.com/lsmc-bio/MultiQC/archive/refs/tags/1.36.dev0-lsmc.4.zip` |

## Release State

| Repo | Branch | Commit/Tag |
|---|---|---|
| `lsmc-bio/ur-qc` | `codex/ultima-run-qc` | `0.3.1` |
| `lsmc-bio/MultiQC` | `codex/ultima-alignstats-native` | `1.36.dev0-lsmc.4` |
| `Daylily-Informatics/daylily-omics-analysis` | `codex/tstclu411c-hybrid-env-python` | this completion record plus MultiQC `1.36.dev0-lsmc.4` env pin |

## Residual Maintenance

The release-candidate open-source path is complete for the requested product
surface. Future work is normal maintenance: additional real vendor schema
variants, upstream PR refinement, and optional package publication beyond
GitHub source releases.
