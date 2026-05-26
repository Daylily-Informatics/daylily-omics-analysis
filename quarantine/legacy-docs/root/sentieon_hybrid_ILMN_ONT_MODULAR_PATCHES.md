> **Historical design note.** This file captures an earlier modular hybrid investigation. Verify current behavior against the `workflow/rules/sent_hybrid_*_modular.smk` files and current tests before using it as guidance.

REQUIRED PATCHES

Below are minimal patches that move the modular workflow toward CLI-equivalent behavior for the items you listed. They are written as unified diffs against sent_hybrid_ilmn_ont_modular.smk (rule names referenced exactly as in your file).

Patch 1 — Fix Stage1 to match CLI pipeline

Why: CLI Stage1 is defined by sentieon_cli/command_strings.py: hybrid_stage1 and invoked in sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.call_variants. Modular Stage1 currently never runs bwa mem and never creates {output.bam}.

diff --git a/sent_hybrid_ilmn_ont_modular.smk b/sent_hybrid_ilmn_ont_modular.smk
@@ rule sentdhiom_stage1:
     shell:
         """
         set -euo pipefail
         export PATH=$PATH:/fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/
@@
         echo "Starting Stage1 at $(date)" >> {log}
@@
         INS_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
             --temp_dir $TMPDIR \
             $LR_RG_ARGS -i {input.lr_cram} \
             --algo HybridStage1 \
             --model {params.model}/HybridStage1_ins.model \
             --fa_file {output.ins_fa} \
             --bed_file {output.ins_bed} \
             -"
 
-        samtools index {output.hap_bam}
+        # Match sentieon-cli hybrid stage1:
+        #   cat <(stage1_driver) <(ins_driver) | sentieon bwa mem -R "@RG\tID:hybrid-18893\tSM:{hybrid_rg_sm}" -x HybridStage1_bwa.model ref - | sentieon util sort --sam2bam
+        # (sentieon_cli/command_strings.py: hybrid_stage1 ; sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.call_variants)
+        unset bwt_max_mem
+
+        cat <( eval "$HAP_CMD" ) <( eval "$INS_CMD" ) \
+          | sentieon bwa mem \
+              -R "@RG\tID:hybrid-18893\tSM:{config[sentdhio][sample_sm]}" \
+              -t {params.use_threads} \
+              -x {params.model}/HybridStage1_bwa.model \
+              {params.huref} \
+              - 2>> {log} \
+          | sentieon util sort \
+              -i - \
+              -t {params.use_threads} \
+              -o {output.bam} \
+              --sam2bam >> {log} 2>&1
 
         echo "Stage1 completed at $(date)" >> {log}
         """

Notes grounded in CLI source:

The readgroup string in CLI Stage1 is hardcoded to ID:hybrid-18893 and SM:{self.hybrid_rg_sm} (sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.call_variants).

The bwa model used is HybridStage1_bwa.model (sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.call_variants, sentieon_cli/command_strings.py: hybrid_stage1).

The wrapper removes bwt_max_mem for stage1 bwa (sentieon_cli/command_strings.py: hybrid_stage1), which the patch mirrors with unset bwt_max_mem.

Patch 2 — Make transfer match CLI build_transfer_jobs semantics

Why: CLI’s transfer is not bcftools annotate. It is merge-trim logic with shard handling (sentieon_cli/transfer.py: build_transfer_jobs plus sentieon_cli/command_strings.py: cmd_bcftools_merge_trim and cmd_bcftools_view_regions).

This patch replaces the annotate-based transfer with a python-driven implementation that runs the same bcftools/trimalt pattern and a final concat without -aD (because CLI passes xargs ["--no-version","--threads",cores] to bcftools_concat).

diff --git a/sent_hybrid_ilmn_ont_modular.smk b/sent_hybrid_ilmn_ont_modular.smk
@@ rule sentdhiom_transfer:
     shell:
-        r"""
+        r"""
         set -euo pipefail
 
         if [ -n "{params.pop_vcf}" ] && [ -f "{params.pop_vcf}" ]; then
-
-            # Transfer all INFO fields from pop_vcf
-            bcftools annotate \
-                --threads {threads} \
-                -a "{params.pop_vcf}" \
-                -c INFO \
-                -Oz \
-                -o {output.vcf} \
-                {input.anno_vcf}
+            # Match sentieon-cli transfer behavior (sentieon_cli/transfer.py: build_transfer_jobs)
+            # - Compute merge_rules from pop_vcf header INFO fields with Number=A
+            # - Shard reference fai into 10Mb chunks
+            # - For contigs not in pop_vcf, subset raw_vcf by contig
+            # - Else: bcftools merge ... | python3 trimalt.py | bcftools view -W=tbi -o shard.vcf.gz
+            # - bcftools concat -W=tbi --output out --no-version --threads {threads} shard_vcfs...
+
+            python3 - << 'PY'
+import os, re, subprocess, tempfile, pathlib, sys
+
+raw_vcf = pathlib.Path("{input.anno_vcf}")
+pop_vcf = pathlib.Path("{params.pop_vcf}")
+out_vcf = pathlib.Path("{output.vcf}")
+threads = int("{threads}")
+
+# Locate trimalt.py exactly as CLI does
+from importlib_resources import files
+trim_script = pathlib.Path(str(files("sentieon_cli.scripts").joinpath("trimalt.py"))).resolve()
+
+# Temp directory like build_transfer_jobs(base_tmp_dir=self.tmp_dir)
+tmp_dir = pathlib.Path(tempfile.mkdtemp(prefix="sentdhiom_transfer_", dir=os.getcwd()))
+
+# Parse pop VCF header to get contigs and merge_rules (Number=A => sum)
+kvpat = re.compile(r'(.*?)=(".*?"|.*?)(?:,|$)')
+hdr = subprocess.run(["bcftools","view","-h",str(pop_vcf)], capture_output=True, text=True, check=True).stdout.splitlines()
+
+pop_contigs = set()
+id_fields = []
+for line in hdr:
+    if line.startswith("##contig="):
+        s = line.index("<"); e = line.index(">")
+        d = dict(kvpat.findall(line[s+1:e]))
+        if "ID" in d: pop_contigs.add(d["ID"])
+    if line.startswith("##INFO") and ",Number=A" in line:
+        s = line.index("<"); e = line.index(">")
+        d = dict(kvpat.findall(line[s+1:e]))
+        if "ID" in d: id_fields.append(d["ID"])
+merge_rules = ",".join([f"{x}:sum" for x in id_fields]) if id_fields else "AC_v20:sum,AF_v20:sum,AC_genomes:sum,AF_genomes:sum"
+
+# Read reference fai data from raw_vcf's reference index is not available here; CLI uses self.fai_data.
+# We require a .fai path in the environment via REF_FAI if you want exact contig lengths.
+# If not present, we cannot exactly reproduce shard boundaries.
+ref_fai = os.environ.get("REF_FAI")
+if not ref_fai:
+    sys.stderr.write("ERROR: REF_FAI env var not set; cannot shard like sentieon-cli determine_shards_from_fai\\n")
+    sys.exit(2)
+
+# Parse fai: contig length
+fai = {}
+with open(ref_fai, "r") as fh:
+    for line in fh:
+        fields = line.rstrip("\n").split("\t")
+        fai[fields[0]] = int(fields[1])
+
+MAX_SHARD = 10_000_000  # determine_shards_from_fai(..., 10*1000*1000)
+
+sharded_vcfs = []
+seen_missing = set()
+
+for ctg, ctg_len in fai.items():
+    if ctg not in pop_contigs:
+        if ctg in seen_missing:
+            continue
+        seen_missing.add(ctg)
+        bed = tmp_dir / f"subset_{ctg}.bed"
+        bed.write_text(f"{ctg}\t0\t{ctg_len}\n")
+        out = tmp_dir / f"subset_{ctg}.vcf.gz"
+        subprocess.run(
+            ["bcftools","view","--no-version","-W=tbi","-O","z","-o",str(out),"--regions-file",str(bed),str(raw_vcf)],
+            check=True
+        )
+        sharded_vcfs.append(out)
+        continue
+
+    start = 0
+    shard_i = 0
+    while start < ctg_len:
+        stop = min(ctg_len, start + MAX_SHARD)
+        bed = tmp_dir / f"shard_{ctg}_{shard_i}.bed"
+        bed.write_text(f"{ctg}\t{start}\t{stop}\n")
+        out = tmp_dir / f"shard_{ctg}_{shard_i}.vcf.gz"
+
+        # bcftools merge -> trimalt.py -> bcftools view, matching cmd_bcftools_merge_trim
+        merge_cmd = [
+            "bcftools","merge",
+            "--regions-file",str(bed),
+            "--no-version","--regions-overlap","pos","-m","all",
+            "-i", merge_rules,
+            str(raw_vcf), str(pop_vcf),
+        ]
+        view_cmd = ["bcftools","view","--no-version","-W=tbi","-o",str(out)]
+
+        p1 = subprocess.Popen(merge_cmd, stdout=subprocess.PIPE)
+        p2 = subprocess.Popen(["python3", str(trim_script)], stdin=p1.stdout, stdout=subprocess.PIPE)
+        p3 = subprocess.run(view_cmd, stdin=p2.stdout, check=True)
+        if p1.wait() != 0:
+            sys.exit(p1.returncode)
+        if p2.wait() != 0:
+            sys.exit(p2.returncode)
+
+        sharded_vcfs.append(out)
+        shard_i += 1
+        start = stop
+
+# Final concat: bcftools concat -W=tbi --output out --no-version --threads <cores> shards...
+subprocess.run(
+    ["bcftools","concat","-W=tbi","--output",str(out_vcf),"--no-version","--threads",str(threads), *map(str, sharded_vcfs)],
+    check=True
+)
+PY
 
         else
             cp {input.anno_vcf} {output.vcf}
         fi
 
         bcftools index --threads {threads} -t {output.vcf}
         """

This patch intentionally fails if REF_FAI is not provided, because CLI’s sharding boundaries are derived from self.fai_data which is built from the reference .fai (sentieon_cli/shard.py: parse_fai and determine_shards_from_fai, invoked in sentieon_cli/dnascope_hybrid.py: DNAscopeHybridPipeline.validate). Without a FAI, the shard graph is not reproducible from this file.

If you want this fully self-contained in Snakemake, add the reference .fai as an input and set REF_FAI in the shell block.

Patch 3 — Implement CLI-style read_filter support

Why: CLI can add multiple --read_filter flags per RG ID (sentieon_cli/dnascope_hybrid.py: RgInfo.__init__, emitted by sentieon_cli/driver.py: BaseDriver.build_cmd). Modular has no analogue.

I’m not writing a full diff here because your Snakemake file has no config keys for lr_read_filter or sr_read_filter, and adding them would require propagating to at least:

sentdhiom_pass1

sentdhiom_mapq0_bed

sentdhiom_stage1 (both HAP_CMD and INS_CMD)

sentdhiom_stage3

sentdhiom_pass2

Mechanically, it needs to match the CLI behavior:

build --read_filter "<filter>,rgid=<ID>" once per RG ID (RgInfo.__init__)

pass them as repeated --read_filter tokens (BaseDriver.build_cmd)

If you want, I can produce a concrete diff once you tell me where you want to store these in config.
