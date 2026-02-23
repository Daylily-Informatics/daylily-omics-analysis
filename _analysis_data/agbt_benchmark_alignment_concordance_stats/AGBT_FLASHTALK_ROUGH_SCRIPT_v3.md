## Constraints

- 3 slides max, 3 minutes max
- Slides fade out at ~2:15, so land the punchline by ~1:35
- Minimal on-slide text: title + plot annotations only

---s

## Slide 1 — The Human Genome F-score(30x)

**On-slide title:** The Human Genome F-score(30x) 
*(Plot: precision/recall; HG003; Illumina; 2×150; GIAB HC; GATK)*

**Spoken (≈35–45s):**  
Hello, my name is John Major ( I am head of systems at LSMC? ). I am thrilled to be back at AGBT and eager to share an application first approach to evaluating genome quality.

When most of us say a 30× genome, we mean something like this: What F-score for SNVs fo we expect from Illumina, 2×150 read data, benchmarked with a GIAsB sample in it's published high-confidence regions. Variants called with a 'generally accepted best practices' pipeline, traditionally gatk. 

This plot of precision/recall/f-score by variant class performance w/in these constraints is extremely commonplace, and is what many people have in mind when 30x is used as a proxy for genome quality. 


But **30× is a depth target, not a quality specification.** 


**Slide 1 landing line:** The 30x proxy for genome quality has always collapsed a fair amount of variation. Even here, in one of the most widely used visualizations of variant calling performance, this single metric variant class, the single scalar is doing a poor job of describing how these variants behave. <next slide>

---

## Slide 2 — Variability in Characteristics of 30x Genomes    

**On-slide title:** Variability in Characteristics of 30x Genomes
*(Plot: distributions across F-score by build/variant class + cost + runtime)*

**Spoken (≈35–45s):**  
30x is defined by a loosely shared set of assumptions that yields data of a variable quality.  



What you get isn’t one 30× genome. You get a **distribution**: F-score shifts by genome build and variant class, costs move, runtimes move.

So when 30x is set as a target and proxy for quality, what is left unspecified:

- Optimized for which failure modes?
- Cost tradeoffs? Does your budget allow for maxumum accuracy, or are you willing to accept a less accurate result to save money? Is maximizing accuracy at any cost serving your applications goals?
- At what turnaround time? Does your application demand rapid results?
- Non high-confidence regions? Special callers?

30× collapses an engineering system into one number. It’s convenient. It’s also no longer sufficient.

**Slide 2 landing line:** Presented here, are aggregate data for multiple seq platforms and analysis pipelines - all 30x, all for HG003. Accuracy, cost and time to result all play a significant role in making decisions about what is the right 30x genome for your application. Here we can see that changes in post-sequening steps can have a large impact on the final result. <next slide>

---

## Slide 3 — The Application-Centric Human Genome

The applications WGS data support is diverse and are increasinly underserved by a one-size-fits-all approach. 

**On-slide title:** The Application-Centric Human Genome  
*(Plot: multi-dim matrix across platforms/mixtures/depths; ROI vs genome-wide; cost/time)*

**Spoken (≈35–45s):**  

But at this point, **genome quality is a vector.** Here’s the same sample across platforms, mixtures, and depths, evaluated across multiple dimensions.

Some configurations buy you SV recovery.  
Some buy you difficult-region recall.  
Some buy you lower cost.  
Some buy you time-to-answer.

The application decides which dimensions matter, and how they’re weighted.

So instead of specifying genomes by coverage alone, we should specify them with measurable targets across dimensions:

- accuracy in defined regions of interest
- performance in difficult contexts
- cost ceilings
- turnaround guarantees

That’s not philosophical. It’s an engineering spec.

At LSMC, we’re building application-first genomics where platform, reference, pipeline, depth, cost, and time are tunable variables matched to a defined requirement.

**Close (one sentence):** Bring the application spec; we’ll help map it to the configuration that actually meets it.

**Footer / poster callout (optional spoken add-on, 5s):** If you want the full stratifications and matrices, I’m at poster ####.

---

...
Depth-standardized benchmarking served its purpose. With so many seuencing platforms, analysis options, and vaired applicationsneeds to interrogate areas outside the high-confidence regions of the genome, a one-size-fits-all approach is no longer sufficient. In fact, with so many variables to consider, coverage alone is likely to result in finding a suboptimal solution for a givn project (in both directions, you may be wasting resources on unhelpful data, or missing oppotunities to do more if freed from a single number proxy).

## Delivery Notes (fast)

- Aim to hit Slide 3 by ~1:05 and finish your close by ~1:35 (fade safety).
- Keep one reframe sentence per slide:
  - Slide 1: 30× is depth, not spec
  - Slide 2: same depth, different genome
  - Slide 3: quality is a vector; specify by application