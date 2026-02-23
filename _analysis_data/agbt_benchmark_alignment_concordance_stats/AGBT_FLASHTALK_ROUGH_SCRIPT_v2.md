# AGBT Speaker Gudiance

> Three slides maximum

> 3 minutes maximum. Slides fade out after 1.75 min.

> Tuesday, plenary session @ 11:45am ET.

> pptx only, delivered the night prior.

> Check in @ speaker prep room 1hr prior to scheduled presentation time.

--------
Slide 1

The Human 30× Genome

This is what most of us mean when we say “a 30× genome.”

HG003.
Illumina NovaSeq.
2×150.
GIAB high-confidence regions.
GATK.

Precision and recall look excellent.

For more than a decade, 30× has been shorthand for “good enough.”

But 30× is a depth target — not a quality specification.

And reducing genome quality to coverage has become increasingly misleading.

Even within this canonical 30× genome, performance varies across variant classes.

And more importantly:

Quality is not absolute.
It is application-defined.

A rare disease lab, an oncology workflow, and a population screening program do not need the same genome.

Yet we keep specifying them with the same scalar.

Slide 2

The Human 30× Genome Is Not One Thing

Now hold depth constant.

Same sample.
Nominally 30×.

But change the reference.
Change the aligner.
Change the caller.
Add hybrid reads.
Change the analysis stack.

Here are distributions across performance metrics:

Fscore — stratified by build and variant class.
Cost.
Runtime.

There is spread in every dimension.

So when someone says, “We deliver 30× genomes,” the real question is:

Thirty × of what?
Optimized for which outcome?
At what cost?
At what turnaround time?

Thirty × collapses a multi-dimensional system into a single number.

That’s convenient.

But it’s no longer sufficient.

Slide 3

The Application-Centric Human Genome

Depth standardized benchmarking.
It served its purpose.

But genome quality is a vector.

Here is the same sample across platforms, mixtures, and depths — evaluated across multiple dimensions.

Some configurations improve SV recovery.
Some reduce cost.
Some shorten time to answer.
Some improve difficult-region recall.

Applications dictate which dimensions matter.

So instead of specifying genomes by coverage alone, we should specify them by measurable targets across dimensions:

Accuracy in defined regions.
Performance in difficult contexts.
Cost ceilings.
Turnaround guarantees.

That’s not a philosophical shift.
It’s an engineering one.

At LSMC, we’re building an application-first genomic capability — where platform, reference, pipeline, depth, cost, and time are tunable variables aligned to a defined specification.

Bring the application requirements.

We’ll help identify the configuration that meets them.

If you’d like to see the stratifications, full matrices, and how we’re approaching application-first genomic capabilities at LSMC, please visit me at poster ####.




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