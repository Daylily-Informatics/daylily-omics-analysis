how can i match this behavior in the modular?

The modular pipeline does not implement CLI’s SM validation and conditional SR replace_rg behavior (sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.validate_readgroups, sentieon_cli/dnascope_hybrid.py: RgInfo.__init__).

The modular pipeline does not implement CLI’s optional read_filter behavior (sentieon_cli/dnascope_hybrid.py: RgInfo.__init__).
Thought for 26m 34s

To match CLI, you need to reproduce exactly two code paths from sentieon_cli/dnascope_hybrid.py:

SM validation + “hybrid_rg_sm / hybrid_set_rg” selection

sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.validate_readgroups()

It iterates all @RG tags from LR + SR (and SR fastq RG strings if provided), errors if any RG is missing SM, errors if it sees multiple different SM values unless --rgsm is set, and sets:

hybrid_set_rg = True if rgsm else False

hybrid_rg_sm = rgsm if rgsm else first_seen_SM

Conditional SR replace_rg + optional read_filter expansion

sentieon_cli/dnascope_hybrid.py:RgInfo.__init__()

LR always gets LR:1 in replace_rg; LR SM is overridden only when hybrid_set_rg is true.

SR gets replace_rg only when hybrid_set_rg is true.

read_filter strings are expanded per RGID as "<filter>,rgid=<ID>", and SR also gets UltimaReadFilter,rgid=<ID> only when shortread_tech.upper() == "ULTIMA".

And you must propagate the resulting lists stage-by-stage exactly like:
sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.call_variants()

Pass1: ultima + lr + sr

MapQ0: lr + sr

Stage1 (both drivers): lr

Stage3: lr + sr

Pass2: ultima + lr

Right now your modular rules (rule sentdhiom_pass1, rule sentdhiom_mapq0_bed, rule sentdhiom_stage3, rule sentdhiom_pass2) only build LR replace_rg locally and don’t implement SM validation or read_filter propagation.

One path I’d actually use: generate an RG manifest once, then consume it everywhere

Create a single Snakemake rule that:

Reads @RG lines from LR + SR headers using the same mechanism as CLI’s sentieon_cli/command_strings.py:get_rg_lines() (it runs samtools view -H <aln>) and parsing as sentieon_cli/util.py:parse_rg_line() (tab-split, then split tags on the first colon).

Implements validate_readgroups() semantics.

Implements RgInfo.__init__() outputs: LR replace_rg list, SR replace_rg list (conditional), and read_filter lists.

Writes rg_info.json into your tmp dir.

Then in each driver rule, you load that JSON and generate:

per-input --replace_rg blocks (LR always; SR only when hybrid_set_rg true)

stage-specific --read_filter blocks (matching call_variants())

This avoids copy-paste drift and matches the CLI structure directly.

Minimal patch
0) Add config knobs that correspond to CLI args

These map 1:1 to what validate_readgroups() and RgInfo.__init__() use:

sentdhio:
  rgsm: ""            # empty means “no override”, like not passing --rgsm
  lr_read_filter: ""  # empty means disabled
  sr_read_filter: ""  # empty means disabled
  shortread_tech: "ILLUMINA"  # or "ULTIMA"
1) Add this rule (new): sentdhiom_rginfo

This is the modular equivalent of:

sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.collect_readgroups()

sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.validate_readgroups()

sentieon_cli/dnascope_hybrid.py:RgInfo.__init__()

rule sentdhiom_rginfo:
    """Build rg_info.json implementing validate_readgroups() + RgInfo.__init__()."""
    input:
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiom/vcfs/{dchrm}/tmp/sr_dedup.bam",
    output:
        json=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiom/vcfs/{dchrm}/tmp/rg_info.json",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIOM)
    conda:
        "../envs/sentieon_v0.3.yaml"
    threads: 1
    params:
        rgsm=lambda wc: config["sentdhio"].get("rgsm", ""),
        lr_read_filter=lambda wc: config["sentdhio"].get("lr_read_filter", ""),
        sr_read_filter=lambda wc: config["sentdhio"].get("sr_read_filter", ""),
        shortread_tech=lambda wc: config["sentdhio"].get("shortread_tech", "ILLUMINA"),
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname "{output.json}")"

        python3 - <<'PY' > "{output.json}"
import json
import subprocess
import sys

lr_path = "{input.lr_cram}"
sr_path = "{input.sr_bam}"

rgsm = "{params.rgsm}"
lr_read_filter = "{params.lr_read_filter}"
sr_read_filter = "{params.sr_read_filter}"
shortread_tech = "{params.shortread_tech}"

def get_rg_lines(path):
    # Mirrors sentieon_cli/command_strings.py:get_rg_lines()
    res = subprocess.run(["samtools", "view", "-H", path], check=True, stdout=subprocess.PIPE, text=True)
    return [line for line in res.stdout.split("\n") if line.startswith("@RG")]

def parse_rg_line(rg_line):
    # Mirrors sentieon_cli/util.py:parse_rg_line()
    tags = rg_line.split("\t")[1:]
    d = dict()
    for tag in tags:
        if ":" not in tag:
            continue
        k, v = tag.split(":", 1)
        d[k] = v
    return d

# Collect RG dicts in the same high-level order as validate_readgroups():
# LR alignments first, then SR alignments (sentieon_cli/dnascope_hybrid.py:collect_readgroups()).
lr_rg_dicts = [parse_rg_line(x) for x in get_rg_lines(lr_path)]
sr_rg_dicts = [parse_rg_line(x) for x in get_rg_lines(sr_path)]

# validate_readgroups() semantics (sentieon_cli/dnascope_hybrid.py:validate_readgroups())
hybrid_rg_sm = ""
rg_sm_tag = None

for rg_d in (lr_rg_dicts + sr_rg_dicts):
    sm = rg_d.get("SM")
    if not sm:
        sys.stderr.write("Found a readgroup without a SM tag: %s\n" % (str(rg_d),))
        sys.exit(2)

    if not rg_d.get("ID"):
        # CLI logs error but does not exit here (validate_readgroups()).
        sys.stderr.write("Found a readgroup without an ID tag: %s\n" % (str(rg_d),))

    if rg_sm_tag is None:
        rg_sm_tag = sm
        hybrid_rg_sm = sm
    elif (rg_sm_tag != sm) and (not rgsm):
        sys.stderr.write(
            "Input readgroup '%s' has a different RG-SM tag from previously seen alignment files. "
            "found='%s' expected='%s'. Please set rgsm to override.\n"
            % (str(rg_d), sm, rg_sm_tag)
        )
        sys.exit(2)

hybrid_set_rg = True if rgsm else False
if rgsm:
    hybrid_rg_sm = rgsm

# RgInfo.__init__() semantics (sentieon_cli/dnascope_hybrid.py:RgInfo.__init__)
lr_replace_rg = []
lr_rg_read_filter = []
for rg_d in lr_rg_dicts:
    rgid = rg_d.get("ID")
    new_sm = hybrid_rg_sm if hybrid_set_rg else rg_d.get("SM")
    lr_replace_rg.append("%s=ID:%s\\tSM:%s\\tLR:1" % (rgid, rgid, new_sm))
    if lr_read_filter:
        lr_rg_read_filter.append("%s,rgid=%s" % (lr_read_filter, rgid))

sr_replace_rg = []
sr_rg_read_filter = []
ultima_read_filter = []
for rg_d in sr_rg_dicts:
    rgid = rg_d.get("ID")
    new_sm = hybrid_rg_sm if hybrid_set_rg else rg_d.get("SM")
    if hybrid_set_rg:
        sr_replace_rg.append("%s=ID:%s\\tSM:%s" % (rgid, rgid, new_sm))
    if sr_read_filter:
        sr_rg_read_filter.append("%s,rgid=%s" % (sr_read_filter, rgid))
    if shortread_tech.upper() == "ULTIMA":
        ultima_read_filter.append("UltimaReadFilter,rgid=%s" % (rgid,))

out = dict(
    hybrid_set_rg=hybrid_set_rg,
    hybrid_rg_sm=hybrid_rg_sm,
    lr_replace_rg=lr_replace_rg,
    sr_replace_rg=sr_replace_rg,
    lr_rg_read_filter=lr_rg_read_filter,
    sr_rg_read_filter=sr_rg_read_filter,
    ultima_read_filter=ultima_read_filter,
)
json.dump(out, sys.stdout, indent=2, sort_keys=True)
PY
        """
2) Consume rg_info.json in each relevant driver rule

This is how you match both:

conditional SR replace_rg (RgInfo.__init__())

read_filter propagation (call_variants())

Below are concrete insertions you should do inside each rule’s shell:.

Helper snippet (drop into pass1/mapq0/stage1/stage3/pass2)

This loads JSON and prints ready-to-insert CLI-style tokens.

LR_RG_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
args=[]
for s in d.get("lr_replace_rg", []):
    args += ["--replace_rg", s]
print(" ".join(args))
PY
)

SR_RG_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
args=[]
for s in d.get("sr_replace_rg", []):
    args += ["--replace_rg", s]
print(" ".join(args))
PY
)

Now stage-specific read_filter blocks, matching sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.call_variants():

 

Pass1 (ultima + lr + sr):

PASS1_RF_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
filters = d.get("ultima_read_filter", []) + d.get("lr_rg_read_filter", []) + d.get("sr_rg_read_filter", [])
args=[]
for f in filters:
    args += ["--read_filter", f]
print(" ".join(args))
PY
)

MapQ0 (lr + sr):

MAPQ0_RF_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
filters = d.get("lr_rg_read_filter", []) + d.get("sr_rg_read_filter", [])
args=[]
for f in filters:
    args += ["--read_filter", f]
print(" ".join(args))
PY
)

Stage1 (lr only):

S1_RF_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
filters = d.get("lr_rg_read_filter", [])
args=[]
for f in filters:
    args += ["--read_filter", f]
print(" ".join(args))
PY
)

Stage3 (lr + sr):

S3_RF_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
filters = d.get("lr_rg_read_filter", []) + d.get("sr_rg_read_filter", [])
args=[]
for f in filters:
    args += ["--read_filter", f]
print(" ".join(args))
PY
)

Pass2 (ultima + lr):

PASS2_RF_ARGS=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
filters = d.get("ultima_read_filter", []) + d.get("lr_rg_read_filter", [])
args=[]
for f in filters:
    args += ["--read_filter", f]
print(" ".join(args))
PY
)
Apply those to your rules

rule sentdhiom_pass1: add rginfo=.../rg_info.json to input: and then change the driver call to:

sentieon driver -r {params.huref} -t {params.use_threads} \
  --temp_dir $TMPDIR \
  $LR_RG_ARGS -i {input.lr_cram} \
  $SR_RG_ARGS -i {input.sr_bam} \
  {params.diploid_bed} \
  $PASS1_RF_ARGS \
  --algo DNAscope \
  --model {params.model}/hybrid.model \
  --pcr_indel_model none \
  {output.vcf}

This matches:

SR replace_rg being present only when hybrid_set_rg is true (RgInfo.__init__())

read_filter list composition for pass1 (call_variants())

rule sentdhiom_mapq0_bed: add rginfo input and insert $MAPQ0_RF_ARGS in the driver call:

sentieon driver ... \
  $LR_RG_ARGS -i {input.lr_cram} \
  $SR_RG_ARGS -i {input.sr_bam} \
  $MAPQ0_RF_ARGS \
  --algo HybridStage2 \
  --model .../HybridStage2_region.model \
  --all_bed {output.bed}

rule sentdhiom_stage1: add rginfo input, then:

use $LR_RG_ARGS for LR replace_rg

include $S1_RF_ARGS inside both Stage1 driver invocations (hap + ins), because CLI sets read_filter=rg_info.lr_rg_read_filter for both (call_variants())

set bwa -R ... SM: from hybrid_rg_sm (CLI uses self.hybrid_rg_sm in call_variants() when building the Stage1 bwa readgroup string)

Hybrid SM extraction:

HYBRID_SM=$(python3 - <<'PY'
import json
d=json.load(open("{input.rginfo}"))
print(d.get("hybrid_rg_sm",""))
PY
)

Then Stage1 bwa mem must use:

-R "@RG\tID:hybrid-18893\tSM:${HYBRID_SM}"

matching dnascope_hybrid.py:call_variants().

rule sentdhiom_stage3: add rginfo input; pass replace_rg for LR and SR inputs only (SR conditional via $SR_RG_ARGS), and add $S3_RF_ARGS to match call_variants() stage3 read_filter.

rule sentdhiom_pass2: add rginfo input; apply only $LR_RG_ARGS to the LR input, and include $PASS2_RF_ARGS. This matches call_variants() pass2: replace_rg=rg_info.replace_rg_args[0] and read_filter=ultima + lr.

Why this is actually equivalent to CLI (source-grounded)

Your validation and hybrid_rg_sm determination becomes a faithful reproduction of sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.validate_readgroups().

Your conditional SR replace_rg becomes a faithful reproduction of sentieon_cli/dnascope_hybrid.py:RgInfo.__init__() (SR replace only when hybrid_set_rg).

Your --read_filter token lists per stage become a faithful reproduction of how sentieon_cli/dnascope_hybrid.py:DNAscopeHybridPipeline.call_variants() concatenates:

rg_info.ultima_read_filter

rg_info.lr_rg_read_filter

rg_info.sr_rg_read_filter
differently per stage.

Do this next:

Add rule sentdhiom_rginfo exactly as above. Run it alone on one sample and inspect the produced rg_info.json.

Wire rginfo into sentdhiom_pass1, sentdhiom_mapq0_bed, sentdhiom_stage1, sentdhiom_stage3, sentdhiom_pass2. Remove the local AWK-based RGID loops from those rules.

Add sentdhio.rgsm to config and test both modes:

rgsm="" should enforce “all SM identical” and not apply SR replace_rg (CLI default).

rgsm="YOUR_SM" should override SM for both LR and SR and enable SR replace_rg (CLI --rgsm).