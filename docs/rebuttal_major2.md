# Response to Major Comment 2 — Part 2: Why multi-mapping does not inflate or dilute the strand-bias signal

> **Reviewer concern (continued):** "…this will artificially inflate or dilute
> the strand bias signal."

Part 1 (see `rebuttal_major2.md`) explains *how* multi-mapping reads are excluded
(MAPQ filtering, single-best-hit mode, proper-pair requirement). This Part 2
addresses *why*, even in principle, the pseudo-random placement of multi-mappers
cannot systematically bias the strand signal — and why the remaining uniquely
mapped reads are sufficient for reliable detection.

---

## Response (English)

5. **Pseudo-random placement is strand-neutral and therefore cannot
   systematically inflate or dilute the strand-bias signal.** When Bowtie2
   encounters a multi-mapping read with equally scoring alignments, it
   pseudo-randomly selects one location; the read's mapping orientation at
   the chosen location is determined by the actual alignment, not by any
   strand-preferential mechanism. Because our paired-end pipeline operates
   in the default `--fr` (forward-reverse) mode with `--no-discordant`, only
   two pair orientations are possible for concordant alignments: **F1R2**
   (R1 forward, R2 reverse) and **F2R1** (R1 reverse, R2 forward). A
   pseudo-randomly placed multi-mapper is equally likely to land on an rRNA
   copy where R1 is forward or reverse, so on average it contributes equal
   noise to both the `fwd` and `rev` tallies. Crucially, it does not
   introduce a *systematic* directional bias: the expectation of its
   contribution to `Rel_Diff = (Fwd − Rev) / mean` is zero. Therefore,
   even if multi-mappers were retained, they would add symmetric noise
   rather than inflate or dilute the true strand signal.

6. **MAPQ ≥ 20 filtering removes multi-mappers before they enter the voting
   process.** As detailed in Part 1, the default MAPQ cutoff of 20
   eliminates reads that Bowtie2 could not uniquely place (MAPQ 0–1). The
   remaining reads have high mapping confidence and unambiguous strand
   orientation. Only these uniquely mapped reads participate in the
   progressive per-rRNA-sequence voting (3/3 → 4/5 → 6/7 → 7/8), so the
   detection is entirely based on clean, unambiguous signal.

7. **The progressive voting scheme is inherently robust to residual noise.**
   The detection algorithm requires *supermajority agreement* among the top
   rRNA sequences (e.g., 3 of 3 must agree at the highest confidence level).
   Even hypothetically, if a small number of multi-mappers survived the MAPQ
   filter, they would contribute symmetric noise to individual rRNA sequence
   tallies but would be highly unlikely to flip the majority vote across
   multiple independent sequences simultaneously. The multi-level voting
   design (3/3 → 4/5 → 6/7 → 7/8) further ensures that an isolated
   noisy sequence cannot override consistent signal from the others.

8. **The adaptive MAPQ ladder provides an additional safeguard.** For sparse
   libraries where very few reads pass MAPQ ≥ 20, the tool progressively
   relaxes to MAPQ ≥ 10, then ≥ 3, and finally ≥ 1 — but never to 0.
   At each tier, the detection logic is re-run from scratch: if a lower MAPQ
   tier admits multi-mappers that degrade consensus, the voting mechanism
   will report a lower confidence level (e.g., fallback) or detect
   inconsistency, alerting the user rather than silently producing a wrong
   result.

---

## 回复（中文）

5. **伪随机放置在链方向上是中性的，因此不会系统性地放大或稀释链偏好信号。**
   当 Bowtie2 遇到等分数的多重比对时，会伪随机地选择一个位置；该 read 在所选位置
   的比对方向由实际序列匹配决定，而非任何链偏好机制。由于我们的双端流程使用默认的
   `--fr`（forward-reverse）模式并开启 `--no-discordant`，concordant 比对只有两种
   pair orientation：**F1R2**（R1 正向、R2 反向）和 **F2R1**（R1 反向、R2 正向）。
   一条被伪随机放置的多重比对 read 落到 R1 正向或反向的概率相等，因此平均而言它对
   `fwd` 和 `rev` 计数的贡献是对称的，不会引入*系统性*的方向偏差——其对
   `Rel_Diff = (Fwd − Rev) / mean` 的期望贡献为零。因此即使保留多重比对，它们
   也只会增加对称噪声，而不会放大或稀释真实的链特异性信号。

6. **MAPQ ≥ 20 过滤在投票之前即剔除了多重比对。** 如 Part 1 所述，默认 MAPQ 阈值
   20 会剔除 Bowtie2 无法唯一定位的 read（MAPQ 0–1）。剩余的 read 具有高比对置信
   度和明确的链方向。只有这些唯一比对的 read 参与渐进式 rRNA 序列投票
   （3/3 → 4/5 → 6/7 → 7/8），因此检测完全基于干净、无歧义的信号。

7. **渐进式投票机制对残余噪声具有内在鲁棒性。** 检测算法要求 top rRNA 序列之间达成
   *绝对多数一致*（如最高置信度要求 3 条中 3 条全部一致）。即使假设有少量多重比对
   通过了 MAPQ 过滤，它们也只会对个别 rRNA 序列的计数贡献对称噪声，而极不可能同时
   翻转多条独立 rRNA 序列的多数投票结果。多级投票设计（3/3 → 4/5 → 6/7 → 7/8）
   进一步确保单条噪声序列不会覆盖其他序列的一致信号。

8. **自适应 MAPQ 阶梯提供了额外的安全保障。** 对于通过 MAPQ ≥ 20 的 read 极少的稀
   疏文库，工具会逐步放宽至 MAPQ ≥ 10、≥ 3、≥ 1——但绝不至 0。在每一档，检测逻辑
   都会从头重新运行：如果较低的 MAPQ 档位引入的多重比对破坏了共识，投票机制将报告
   较低的置信度（如 fallback）或检测到不一致性，从而提醒用户而非静默地产生错误结果。

---

## Proposed manuscript text addition（建议补充到正文的文字）

> **建议位置**：Methods — "Strand detection pipeline" 段末，紧接多重比对处理说明之后。

### English draft

> Because Bowtie2 operates in default `--fr` paired-end mode with
> `--no-discordant`, only two concordant pair orientations are produced:
> F1R2 (read 1 forward, read 2 reverse) and F2R1 (read 1 reverse, read 2
> forward). Pseudo-random placement of multi-mapping reads is
> orientation-neutral — it contributes equal noise to both strand tallies —
> so it cannot systematically inflate or dilute the strand-bias signal.
> Nevertheless, all multi-mapping reads are excluded by the default MAPQ ≥ 20
> filter before the strand-voting step, ensuring the detection relies
> exclusively on uniquely mapped reads.

### 中文草稿

> 由于 Bowtie2 以默认的 `--fr` 双端模式并开启 `--no-discordant` 运行，只会产生两种
> concordant pair 方向：F1R2（read 1 正向、read 2 反向）和 F2R1（read 1 反向、
> read 2 正向）。多重比对 read 的伪随机放置在方向上是中性的——它对两个链计数的
> 贡献对称——因此不会系统性地放大或稀释链偏好信号。尽管如此，所有多重比对 read 仍
> 通过默认 MAPQ ≥ 20 过滤在链投票步骤之前被剔除，确保检测完全依赖唯一比对的 read。

---

## Code references

- Bowtie2 `--fr` mode (default, no `--ff`/`--rf`): `bin/default_align_by_bowtie2.sh` L47-53
- `--no-discordant` flag: `bin/default_align_by_bowtie2.sh` L49
- Only R1 examined (`0x40`): `bin/default_counting_withChrom.pl` L115
- R1 strand check (`0x10`): `bin/default_counting_withChrom.pl` L138-142
  - `0x10` set → `chrom_rev++` → F2R1 configuration
  - `0x10` not set → `chrom_fwd++` → F1R2 configuration
- Proper-pair requirement (`0x2`): `bin/default_counting_withChrom.pl` L133-136
- MAPQ filter: `bin/default_counting_withChrom.pl` L129-132

---

