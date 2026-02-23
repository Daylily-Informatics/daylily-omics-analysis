🧱 Poster Title

From 30× Genomes to Application-Defined Genome Specifications

Subtitle:

Moving from coverage targets to outcome-aligned performance metrics across accuracy, context, cost, and time.

LSMC logo
QR code
GitHub / data link

🔵 COLUMN 1 — Why 30× Is No Longer Enough
Section 1: What 30× Actually Encodes

Short bullets:

Mean mapped depth (not uniform coverage)

Often evaluated in bounded high-confidence regions

Aggregated summary metrics hide stratified heterogeneity

Platform- and reference-dependent behavior

Add small box:

Coverage is a scalar.
Genomes are multi-dimensional systems.

Figure 1 — The Canonical 30× Genome

Precision vs Recall (HG003, ILMN 30×, GATK)

Caption:

Even within a single 30× genome, variant-class performance differs.

Add mini table of:

SNPts

SNPtv

DEL_50

INS_50

INDEL_50

This visually reinforces heterogeneity.

🔵 COLUMN 2 — A 30× Genome Is Not One Thing
Figure 2A — Stratified Fscore Distributions

Boxplots:

hg38-SNP

hg38-DEL_50

hg38-INS_50

hg38-pan equivalents

hybrid equivalents

Caption:

Holding depth constant does not hold performance constant.

Figure 2B — Cost vs Performance

Scatter:

X = Fscore
Y = Secondary-analysis-cost

Caption:

Performance exists on a cost surface.

Figure 2C — Runtime vs Performance

X = Runtime (analysis hours)
Y = Fscore

Caption:

Turnaround time is a first-class constraint in clinical contexts.

Box: What 30× Does Not Specify

ROI completeness (e.g., ClinVar genes)

Difficult-region recovery

Structural variant performance

Reference bias impact

Cost ceilings

Turnaround guarantees

This transitions cleanly to the centerpiece.

🔵 COLUMN 3 — The Application-Defined Genome

This column is dominated by stacked heatmaps.

🔥 Centerpiece Figure — Multi-Perspective Heatmap Stack

Stack 3–4 panels vertically.

Each heatmap uses same rows (platform × depth × pipeline), but different columns.

Panel 1 — Genome-Wide Small Variant Performance

Columns:

SNP Fscore (hg38)

DEL_50 Fscore

INS_50 Fscore

SV recall (if available)

Caption:

Genome-wide small-variant view.

Panel 2 — ROI-Focused Performance (e.g., ClinVar Genes)

Columns:

ROI callable fraction

ROI SNP Fscore

ROI indel Fscore

Difficult-region recall within ROI

Caption:

Performance within clinically relevant regions differs from genome-wide metrics.

This is powerful.

It visually proves “application changes ranking.”

Panel 3 — Cost and Time Constraints

Columns:

Secondary-analysis-cost

Sequencing cost (if available)

Time to first usable sequence data

Total analysis runtime

Caption:

Some configurations optimize cost or turnaround at the expense of other dimensions.

Panel 4 (Optional, Strong Move) — Application Priority Weighting

Reorder rows by:

Rare disease priority

Oncology priority

Cost-sensitive population screening priority

This shows the same data sorted differently.

That’s disruptive — in a good way.

🟠 Application-First Framing Panel

Title:

Application-First Genomic Capability

Paragraph:

Instead of specifying genomes by coverage alone, we define application-specific performance targets across accuracy, context, cost, and time.

Then:

Application → Required metrics → Acceptable tradeoffs → Optimal configuration

One simple diagram.

No marketing language.

🟣 Methods & Transparency Band (Bottom)

Sample: HG003

Benchmark: GIAB vX.X

Stratifications used

Reference builds compared (hg38, pangenome)

Alignment/caller stacks

Depth mixtures evaluated

Cost tracking methodology

Runtime tracking methodology

Limitations:

Single sample

Benchmark region bounded

Some analyses still running (data snapshot as of AGBT date)

This increases credibility.

📚 Reference Section

Compact but authoritative.

Include citations from your Deep Research report 

agbt_deepresearch_citations

:

Krusche et al., Nat Biotechnol 2019 (GA4GH benchmarking best practices)

Dwarshuis et al., Nat Methods 2024 (GIAB stratifications)

Wagner et al., Nat Biotechnol 2022 (CMRG benchmark)

Kosugi et al., Genome Biol 2019 (SV evaluation)

Li et al., Genome Med 2021 (reference build effects)

Liao et al., Nature 2023 (HPRC pangenome)

Benjamini & Speed 2012 (GC bias)

Jennings et al., J Mol Diagn 2017 (clinical validation guidance)

Keep them small font, two-column reference list.

Why This Poster Will Impress

It shows:

Breadth of platforms

Depth mixtures

Reference comparisons

Stratified benchmarking

Cost tracking

Runtime tracking

Application-specific evaluation

Engineering maturity

It feels like a capability, not a concept.


# AGBT POSTER GUIDANCE
6. Design Details That Matter

Practical stuff that separates good from forgettable:

Consistent color semantics across plots

Axis labels that include units

Human-readable large numbers (3.6M not 3600000)

Rounded F-scores (0.987 not 0.98742391)

No tiny legends

Avoid rainbow palettes

Avoid cramming supplemental data


7. Make It Conversation-Optimized

The best AGBT posters are built for dialogue:

They enable:

“Wait, how did you stratify?”

“Did you try ONT duplex?”

“What about segmental duplications?”

“What’s the cost delta at 10k genomes?”

A poster should be an invitation to technical argument.


Gudiance
If someone from Broad, Google DeepVariant team, or PacBio could read your poster and not feel slightly challenged, it’s not strong enough.


5) Methods: minimum viable credibility

Methods should be just enough to let someone judge validity:

Data sources + sample IDs (or cohorts)

Reference(s) + versions

Toolchain versions + key parameters

Evaluation definitions (ROIs, truth sets, stratification)

Everything else goes behind a QR.

) Typography that respects viewing distance

For a 36×48 poster (common at AGBT):

Title: ~110–150 pt

Section headers: ~60–80 pt

Body text: ~28–34 pt

Figure axis labels: ~24–30 pt (never smaller than ~22)
If you’re tempted to go smaller, you have too much text.

AGBT posters that win are predictable:

3 columns (or 2 columns with a giant central figure)

Strong alignment grid

Consistent spacing

Clear section order: Problem → Approach → Results → Implications

8) Text is “caption-first”, not paragraph-first

Every figure gets a title that states the conclusion.

Captions answer: what, how measured, key n/ROI, what to notice.

9) Color is semantic, not decorative

Use color to encode meaning (e.g., tech, ROI type, reference choice).

Keep the palette tight.

Use patterns/markers so it still works for colorblind readers.


10) The “So what?” is not optional

End with a box called Implications / Recommendations:

What should a lab/buyer/researcher do differently tomorrow?

What metric/spec should replace the naive one?

What decision changes because of your result?

11) QR codes that actually matter

Put 1–2 QR codes only:

Preprint / extended methods + definitions

Repo with exact commands + configs + data availability statement
Bonus: a single-page “poster companion” with all figures in readable form.

12) Fit the social reality

A strong poster also makes conversation easy:

Include 2–3 “hooks” (short provocative subclaims)

Put your contact + handle in a visible footer

Don’t bury the punchline in the conclusion section nobody reaches