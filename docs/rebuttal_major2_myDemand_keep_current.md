# Major 2 response: retaining best-alignment reporting with MAPQ-controlled multi-mapper handling

Major 2. The treatment of multi-mapping reads within the Bowtie2 step remains unspecified. Ribosomal RNA sequences are highly repetitive. If Bowtie2 is allowed to randomly assign multi-mapping alignments or report multiple alignments per read, this will artificially inflate or dilute the strand bias signal.

Response: We thank the reviewer for raising this important point. We agree that rRNA references contain repetitive and homologous sequences, and that multi-mapping reads must be handled explicitly. After evaluating a stricter unique-only strategy, we retained the current best-alignment plus MAPQ-filtering design because it provides a better balance between specificity and usable signal, especially for rRNA-depleted or otherwise sparse libraries.

## Why we do not use strict unique-only filtering as the default

A strict unique-only rule, such as running Bowtie2 with `-k 2` and discarding any fragment for which a second valid placement is reported, is conservative. However, it is also too aggressive for the purpose of strand-type inference from rRNA-derived reads. In depleted libraries, the number of informative rRNA fragments can already be very small. Removing every fragment with any detectable alternative rRNA placement can push otherwise usable samples into low-confidence fallback or insufficient-data categories.

For resolveS, the goal is not to assign every read to its exact biological rRNA copy. The goal is to estimate the library-level strand orientation. For that purpose, a representative best alignment is sufficient when the orientation is clear and the mapping quality is acceptable. Excessively strict positional uniqueness can discard informative orientation signal without improving the fragment-level strand observation.

## Current multi-mapping strategy

resolveS therefore keeps Bowtie2 in its default reporting mode, without `-k` or `-a`. In this mode, Bowtie2 reports one alignment per read or read pair rather than emitting multiple secondary alignments for every possible placement. This does not mean every reported alignment is mathematically unique; rather, Bowtie2 reports a representative best alignment and uses the relationship between best and alternative placements to estimate MAPQ.

The downstream counting step then controls ambiguous placements by MAPQ and paired-end constraints:

1. The paired-end pipeline uses Bowtie2 in default `--fr` mode with `--no-mixed` and `--no-discordant`, so only concordant paired-end placements are considered.
2. The counting step uses only primary R1 records from proper pairs (`0x2`) and excludes unmapped, secondary, and supplementary records.
3. The default analysis starts at `MAPQ >= 20`, so high-confidence placements dominate the progressive rRNA-sequence voting.
4. For sparse libraries, the adaptive ladder may relax to `MAPQ >= 10`, `>= 3`, and finally `>= 1`, but never to `MAPQ >= 0`. Thus the most ambiguous MAPQ=0 placements remain excluded even at the most permissive level.

This strategy intentionally avoids both extremes: it does not accept all multi-mapping signal blindly, but it also does not discard nearly all rRNA-derived fragments in sparse samples.

## Why multi-mapping does not systematically inflate or dilute the strand call

The reviewer is correct that random placement among repeated rRNA copies could affect positional assignment. However, resolveS uses these reads to infer strand orientation, not exact rRNA copy of origin. Under the paired-end `--fr` model with discordant and mixed alignments suppressed, accepted proper pairs have only two coupled orientations:

- F1R2: R1 forward, R2 reverse
- F2R1: R1 reverse, R2 forward

Therefore, R1 alone provides one fragment-level orientation observation. R2 is used during paired-end alignment and proper-pair validation, but it is not an independent strand vote. Counting both mates would double-count the same fragment-level event.

For stranded libraries, reads generated from the same RNA molecule retain the same strand relationship regardless of which homologous rRNA copy receives the representative best placement. For unstranded libraries, sense and antisense observations are expected to be balanced. Residual low-level ambiguity therefore contributes noise, but it is not expected to create a systematic directional bias in the strand-type call.

## Evidence from SRR9844293

The SRR9844293 example illustrates the issue and the current safeguard. Bowtie2 reported:

```text
298 (0.01%) aligned concordantly exactly 1 time
12380 (0.25%) aligned concordantly >1 times
```

This confirms that multi-placement paired-end alignments exist in rRNA references. However, the final resolveS call for this sample used `MAPQ-20` and passed at the highest progressive voting level (`3of3`), returning `fr-unstranded`. Thus, in this concrete example, the strand call was based on high-confidence MAPQ-filtered signal, not on the most ambiguous MAPQ=0 multi-mappers.

## Revised manuscript wording

We clarified the treatment of multi-mapping reads in the Bowtie2 step. Bowtie2 is run in its default reporting mode, without `-k` or `-a`, so the pipeline receives one representative best alignment per read or read pair rather than multiple reported placements. Because rRNA references are repetitive, such representative alignments are not assumed to be mathematically unique. Instead, resolveS controls ambiguity downstream using paired-end concordance, primary-alignment filtering, and MAPQ thresholds. The paired-end pipeline counts only primary R1 records from proper pairs; it starts with `MAPQ >= 20` and, only for sparse libraries, adaptively relaxes to lower thresholds down to a floor of `MAPQ >= 1`, never including MAPQ=0 placements. This preserves sufficient orientation signal for depleted libraries while excluding the most ambiguous multi-mapping reads. Because concordant FR paired-end orientations are deterministically coupled, R1 provides one independent orientation observation per fragment, and R2 should not be counted as a second independent vote.

## Practical position

We considered a strict unique-only alternative, but it is not appropriate as the default for this tool. It maximizes positional certainty at the cost of losing too many informative rRNA-derived fragments in low-signal samples. The current method is a sensitivity-preserving, MAPQ-controlled compromise: it retains useful strand-orientation information while preventing the most ambiguous multi-mappers from driving the call.
