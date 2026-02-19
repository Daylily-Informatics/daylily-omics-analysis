headnode=ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@34.209.187.6
create and attach to a tmux session that is named <analysis_description>-datetimewseconds , which will stay open after the job is done or fails
run `bash` `source ~/.bashrc`

then clone a day analysis dir with `day-clone`
use `day-clone -w ssh -t <branch> -d <analysis_description>-<datetimewithsec>`, which when done will clone the daylily-omics-analysis repo to `/fsx/analysis_results/ubuntu/<analysis_description>/daylily-omics-analysis/`. You can then cd to that dir.

 and copy the described `<samples.tsv>` and `<units.tsv>` files to `config/` 

# HG003 Test Data samples.tsv and units.tsv files
# single platform 3x coverage 
.test_data/data/stress_tests/{ont,ilmn,pb,ug,roche}/hg003/3x/{samples,units}.tsv

# hybrid 2 unit tests

## ILLMN+ONT
.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/{units,samples}.tsv

## ULTIMA+ONT
.test_data/data/agbt_2026/prod/hybrid/ultima_ont_expanded_testfix/{units,samples}.tsv


# Single-platform tests

ONT only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdont_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdont_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

ILMN ONLY
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1"` 


ILMN ALL



dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf produce_bwa_mem2_sort_bam produce_deep19_vcf produce_clair3_vcf produce_oct_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1" "-n"`
 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_snv_concordances produce_sentieon_bwa_sort_bam produce_sentD_vcf produce_bwa_mem2_sort_bam produce_deep19_vcf produce_clair3_vcf produce_oct_vcf dedup_doppelmark produce_alignstats" "-p -j 20 -k -T 1"` 


PB only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdpb_vcf produce_alignstats produce_snv_concordances" "-p -j 2 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdpb_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

Ultima only (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdug_vcf produce_alignstats produce_snv_concordances" "-p -j 2 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdug_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1"` 

Roche only
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_deep19_r_vcf produce_alignstats produce_snv_concordances" "-p -j 6 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_deep19_r_vcf produce_alignstats produce_snv_concordances" "-p -j 6 -k -T 1"`



# Hybrid tests

## Ultima+ONT cli and modular
Hybrid CLI Ultima+ONT (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuo_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuo_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" ` 


Hybrid Mod Ultima+ONT (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
dryrun command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command: `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhuom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" ` 

## Ilmn+ONT cli and modular
Hybrid CLI Ilmn+ONT
copy  samples.tsv and units.tsv to config/
dryrun command= ` source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhio_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" "-n"` 
command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdhio_vcf produce_alignstats produce_snv_concordances" "-p -j 3 -k -T 1" `

Hybrid Mod Ilmn+ONT
copy  samples.tsv and units.tsv to config/
dryrun command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38_broad "produce_sentdhiom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" "-n"` 
command= `source bin/augment_setup_and_run_dayoa.bash slurm hg38 "produce_sentdhiom_vcf produce_alignstats produce_snv_concordances" "-p -j 20 -k -T 1" ` 



# OTHER TESTS DO NOT RUN THESE !!!

Hybrid Mod Ultima+PB (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38_broad &&  bin/day_run produce_sentdhupm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n


Hybrid CLI Ilmn+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhip_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Ilmn+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhipm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid CLI Ultima+PB (uses hg38_broad - Ultima CRAM aligned to hg38_broad)
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38_broad &&  bin/day_run produce_sentdhup_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n


Hybrid CLI Roche+ONT
**the cli does not support this combination**

Hybrid CLI Roche+PB
**the cli does not support this combination**

Hybrid Mod Roche+ONT
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n

Hybrid Mod Roche+PB
copy  samples.tsv and units.tsv to config/
command= source dyoainit && source bin/day_activate slurm hg38 &&  bin/day_run produce_sentdhrpm_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 -n



**Issue**: The Illumina+ONT modular workflow (`workflow/rules/sent_hybrid_ilmn_ont_modular.smk`) is missing a critical SR (short-read) duplicate marking step between alignment and variant calling.

**Current behavior**:
- `sentdhiom_sr_align` rule produces `sr_aligned.bam` directly from `sentieon bwa mem | util sort`
- `sentdhiom_pass1` rule immediately consumes `sr_aligned.bam` without any intermediate processing
- No `LocusCollector` + `Dedup` step exists for the SR BAM in the modular workflow

**Why this matters**:
- Sentieon hybrid models (HybridIlluminaONT2.0.bundle/hybrid.model) have strict input contracts for SR data
- The model expects properly duplicate-marked SR BAMs with specific tags and header hygiene
- If the SR BAM violates these expectations, the hybrid caller may silently ignore SR reads, resulting in:
  - All-zero `SAD` (Short Allele Depth) values in the VCF
  - All-zero `SPL` (Short read Phred-scaled Likelihoods) values
  - Effectively LR-only calling despite SR reads being present in the input

**Evidence**:
- The CLI (non-modular) `sentdhio` workflow includes SR duplicate marking before hybrid calling
- The modular workflow's pass1 VCF shows all-zero `SAD` values in sampled variants (though only sparse 3x SR coverage regions were checked)
- Other modular hybrid workflows (`sent_hybrid_ilmn_pb_modular.smk`) likely have the same gap

**Recommended fix**:
1. Add a new rule `sentdhiom_sr_markdup` between `sentdhiom_sr_align` and `sentdhiom_pass1`:
   - Input: `sr_aligned.bam` from alignment rule
   - Output: `sr_aligned.smd.bam` (or similar naming convention)
   - Shell commands:
     ```bash
     sentieon driver -r {huref} -i {input.bam} \
         --algo LocusCollector --fun score_info {score_file}
     
     sentieon driver -r {huref} -i {input.bam} \
         --algo Dedup --score_info {score_file} \
         --metrics {metrics_file} \
         {output.bam}
     
     samtools index {output.bam}
     ```
2. Update `sentdhiom_pass1` input to use the deduped SR BAM instead of raw aligned BAM
3. Apply the same fix to all hybrid modular workflows:
   - `sent_hybrid_ilmn_pb_modular.smk` (Illumina+PacBio)
   - `sent_hybrid_ug_ont_modular.smk` (Ultima+ONT) — if it uses pre-aligned SR, verify it's already deduped
   - `sent_hybrid_ug_pb_modular.smk` (Ultima+PacBio) — same verification
   - `sent_hybrid_roche_ont_modular.smk` (Roche+ONT) — same verification
   - `sent_hybrid_roche_pb_modular.smk` (Roche+PacBio) — same verification

**Validation after fix**:
- Re-run pass1 on the SR3x-ONT3x sample
- Check that `SAD` field in the VCF now contains non-zero values in high-coverage regions
- Compare variant counts and concordance metrics against the CLI workflow output

**Reference implementation**:
- See `workflow/rules/sentieon_markdups.smk` rule `doppelmark_sentieon_dups` for the duplicate marking pattern
- Adapt thread counts, memory, and conda environment to match `sentdhio` config section

This is the highest-priority fix because it restores contract parity with the reference CLI implementation and addresses a clear pipeline gap.


# Add a check to be sure the vcf is 1 sample




Second likely cause: your RG/SM unification is not validated, and a 2-sample VCF breaks assumptions

Sentieon-CLI does explicit readgroup validation and tries hard to ensure there is one sample identity across LR and SR.

Your modular rules do not enforce this invariant (even though you do --replace_rg on LR and set SM in SR alignment). If anything slips (multiple SR RGs, LR RGs missing, weird SMs on the long-read side, etc.), you can end up with:

caller effectively treating SR and LR as different sample contexts

SAD for the emitted sample ending up 0

High-signal check:
Inspect the pass1 VCF header and sample column:

bcftools view -h initial.vcf.gz | tail -n 3
# Look at the #CHROM header line: how many samples?


If there’s more than 1 sample column, hybrid_select.py (and your mental model) is broken: it reads v.samples[0] only.

Also check whether the VCF even defines SAD/SPL as expected:

bcftools view -h initial.vcf.gz | grep -E '##FORMAT=<ID=(SAD|SPL|LAD|LPL)\b'


If SAD is defined but always zero, it’s “SR contributes zero”.
If SAD isn’t defined (or SPL isn’t), you’re not actually producing the expected hybrid-format VCF.

6) A minimal set of “no-guess” diagnostics to run on one failing sample

Do these on the exact inputs to pass1:

A) Prove SR BAM actually contains mapped reads + RG tags
samtools view -c -F 4 sr_aligned.bam
samtools view -H sr_aligned.bam | grep '^@RG'
samtools view sr_aligned.bam | head -n 5 | cut -f1-12
# look for RG:Z:... in optional fields

B) Prove LR CRAM has RG tags and you’re actually tagging them LR:1
samtools view -H lr.cram | grep '^@RG'
# confirm your loop sees rgids:
samtools view -H lr.cram | grep '^@RG' | sed 's/.*ID:\([^\t]*\).*/\1/'

C) Inspect pass1 VCF for SAD nonzero anywhere
bcftools query -f '%CHROM\t%POS[\t%SAD]\n' initial.vcf.gz | awk '($3!="." && $3!="0" && $3!="0,0") {print; exit}'
# if nothing prints, SAD is truly never nonzero

D) Check stage2 BED size explosion
wc -l hybrid_stage2.bed
# and rough coverage:
awk '{s+=$3-$2} END{print s}' hybrid_stage2.bed


If stage2 is massive, your final SAD observation might just be “you’re mostly looking at pass2 regions”.

7) Concrete code changes I would make first (single recommended path)

Bring SR preprocessing back to parity with Sentieon-CLI for Illumina+ONT modular:

add LocusCollector + Dedup on SR aligned BAM

feed deduped SR BAM into pass1, stage1/2/3 steps wherever SR is expected

Add an explicit invariant check before pass1:

assert exactly one SM across SR + LR inputs after your rewrite strategy

fail fast if not

For Ultima hybrid, add the missing UltimaReadFilter per SR RGID in pass1.

This combination attacks both the “contract mismatch” and the “Ultima special handling” and gives you hard failure modes instead of silent SAD=0.