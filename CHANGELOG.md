## Changelog

### [0.7.147] - 2024-11-30
- The [README](README.md) has been walked through with a fresh AWS user, and instructions through the end of confirming the headnode can submit and run jobs works! Including running tests and the PCUI functionality works.  Whoop!
- Added a Snakemake rule, configuration hooks, and environment definition to run the [GeneToCN](https://github.com/bioinfo-ut/GeneToCN) caller within the workflow.

### [0.7.78] - 2024-11-17
- Repeated end-to-end cluster creation and giab test data running to completion. About to bless a beta release (which will have associated data).
- My intention is to stop further dev on 0.7.* and move to 0.8.* for the next round of changes.

### [0.7.37] - 2024-10-15
- Initial pre-beta release.
- Added support for pcui and running daylily in multiple AZs.
- Included scripts for cloud formation and cluster setup.
