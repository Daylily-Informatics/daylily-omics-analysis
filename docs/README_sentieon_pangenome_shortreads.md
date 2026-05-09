# Sentieon Pangenome Short-Read Workflows

These rules are current Daylily integrations for Sentieon pangenome-aware short-read and Ultima workflows. They run inside the normal `daylily-ephemeral-cluster` headnode/FSx environment and assume Daylily reference resources are mounted under `/fsx/data`.

## Targets

| Target | Input route | Output VCF |
| --- | --- | --- |
| `produce_pangenome_sr_vcf` | Illumina paired FASTQs from `units.tsv` | `results/day/<build>/<sample>/align/pangenome_sr/spmd/snv/sentpg/<sample>.pangenome_sr.spmd.sentpg.snv.sort.vcf.gz` |
| `produce_pangenome_ug_vcf` | Ultima CRAM/CRAI staged through the `ug` path | `results/day/<build>/<sample>/align/pangenome_ug/spmd/snv/sentpg/<sample>.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz` |

Both targets use `sentieon-cli sentieon-pangenome`; the workflow does not require operators to build `.xg` or `.snarls` files manually.

## Required Resources

The local and Slurm profile templates provide the resource keys used by the rules:

- `sentieon_pangenome_sr.gbz`
- `sentieon_pangenome_sr.hapl`
- `sentieon_pangenome_sr.model`
- `sentieon_pangenome_sr.canonical_bed`
- `sentieon_pangenome_sr.dbsnp`
- matching `sentieon_pangenome_ug.*` keys for Ultima
- population VCF and reference FASTA entries from `config/supporting_files/*.yaml`

Production resources should be staged by the Daylily reference-data process and visible under `/fsx/data`. Use `daylily-ec` for workset staging and manifest delivery, then run these rules from the analysis clone after `source dyoainit` and `dy-a slurm <build>`.

## Example Commands

Dry-run first:

```bash
dy-r produce_pangenome_sr_vcf \
  --config 'aligners=["pangenome_sr"]' 'dedupers=["spmd"]' 'snv_callers=["sentpg"]' \
  -p -j 100 -k -n
```

Ultima pangenome path:

```bash
dy-r produce_pangenome_ug_vcf \
  --config 'aligners=["pangenome_ug"]' 'dedupers=["spmd"]' 'snv_callers=["sentpg"]' \
  -p -j 100 -k -n
```

Remove `-n` only after the DAG and staged manifests are correct.

## Code Evidence

- `workflow/rules/sentieon_pangenome_shortreads.smk`
- `workflow/rules/sentieon_pangenome_ug.smk`
- `workflow/Snakefile`
- `config/day_profiles/*/templates/rule_config.yaml`
