# Response to Major Comment 2 — Treatment of multi-mapping reads

> **Reviewer comment (Major 2):** The treatment of multi-mapping reads within the
> Bowtie2 step remains unspecified. Ribosomal RNA sequences are highly repetitive.
> If Bowtie2 is allowed to randomly assign multi-mapping alignments or report
> multiple alignments per read, this will artificially inflate or dilute the strand
> bias signal.

## Response (English)

We thank the reviewer for raising this important point. Multi-mapping reads are
indeed handled, and we have now made the procedure explicit in the manuscript and
documentation.

1. **Bowtie2 reports a single best alignment per read.** Bowtie2 is run in its
   default reporting mode (without `-k` or `-a`). In this mode Bowtie2 outputs
   exactly **one** best alignment per read and never emits multiple (secondary,
   `0x100`) records for the same read. Therefore the "report multiple alignments
   per read" scenario does not occur in our pipeline.

2. **Multi-mapping reads are identified by their low MAPQ and removed.** When a
   read aligns equally well to several repetitive rRNA copies, Bowtie2 places it
   pseudo-randomly at one location and assigns it a **low MAPQ (0 or 1)**. Our
   counting step filters alignments by **MAPQ ≥ 20**, which discards these
   pseudo-randomly placed multi-mappers. As a result, the strand-bias signal is
   contributed only by **uniquely mapped** reads, so it is neither inflated nor
   diluted by repetitive sequences.

3. **Whole read pairs are excluded in the paired-end pipeline.** In the default
   (paired-end) pipeline we count only read 1 (R1) of each pair and require a
   proper-pair flag (`0x2`). Because the MAPQ filter is applied to the R1 record
   that represents the fragment, a multi-mapping fragment is excluded as a whole.

4. **Robustness improvements made in response to this comment.** (i) The adaptive
   MAPQ fallback ladder used for sparse libraries now has a floor of **MAPQ ≥ 1**
   (previously it could relax to 0), so that MAPQ = 0 pure multi-mappers are
   excluded even at the most permissive setting. (ii) The fast (single-end)
   pipeline now applies the same **MAPQ ≥ 20** filter as the default pipeline.
   These changes ensure consistent multi-mapper exclusion across all modes. The
   procedure is now documented in the README (section "Multi-mapping reads").

## 回复（中文）

感谢审稿人提出这一重要问题。我们的流程实际上已对多重比对 read 进行了处理，并已在正文与
文档中明确说明该过程。

1. **Bowtie2 每条 read 只报告一条最佳比对。** Bowtie2 以默认模式运行（不加 `-k`/`-a`），
   该模式下每条 read 只输出**一条**最佳比对，绝不会对同一条 read 输出多条（secondary，
   `0x100`）记录。因此"每条 read 报告多条比对"的情形在我们的流程中不会发生。

2. **多重比对 read 通过其低 MAPQ 被识别并剔除。** 当一条 read 等同地比对到多个重复的 rRNA
   拷贝时，Bowtie2 会将其伪随机地放到某一个位置，并赋予**很低的 MAPQ（0 或 1）**。我们的
   计数步骤按 **MAPQ ≥ 20** 过滤，从而剔除这些被伪随机放置的多重比对 read。因此链偏好信号
   仅由**唯一比对**的 read 贡献，不会被重复序列放大或稀释。

3. **双端流程中整对 read 被剔除。** 在默认（双端）流程中，我们仅统计每对的 R1，并要求
   proper-pair 标志（`0x2`）。由于 MAPQ 过滤作用于代表该片段的 R1 记录，多重比对的片段会
   被整对剔除。

4. **针对该意见所做的稳健性改进。** (i) 用于稀疏文库的自适应 MAPQ 后备阶梯下限改为
   **MAPQ ≥ 1**（此前最低可放宽至 0），使 MAPQ = 0 的纯多重比对即使在最宽松档位也被排除；
   (ii) 快速（单端）流程现在应用与默认流程相同的 **MAPQ ≥ 20** 过滤。上述改动保证所有模式
   下对多重比对的排除一致。相关过程已在 README（"Multi-mapping reads / 多重比对 read 的
   处理"一节）中说明。

## Code references

- Alignment, default mode (no `-k`/`-a`): `bin/default_align_by_bowtie2.sh`,
  `bin/fast_align_by_bowtie2.sh`
- MAPQ filter (paired-end counting): `bin/default_counting_withChrom.pl`
  (`@MAPQ_LEVELS = (20, 10, 3, 1)`; per-read `MAPQ` check; R1-only + `0x2`)
- MAPQ filter (single-end counting): `bin/fast_count_sam_primary.sh`
  (`mapq < 20` dropped into the `low_mapq` column)

---

## Pending follow-up items（回复中承诺但仍需落实的事项）

以下是基于上面 rebuttal 回复内容对照代码库后发现的待办/不一致：

### 1. ❌ README.md 缺少 "Multi-mapping reads" 章节

回复第 4 点写道：

> The procedure is now documented in the README (section "Multi-mapping reads").

**但英文 README.md 中还没有这个章节。** 中文 README_zh.md 已经有了
（"多重比对 read 的处理"一节，含 MAPQ 过滤逻辑说明），需要在英文 README
中补写对应的 "Multi-mapping reads" section。

> **建议位置**：与中文 README 对齐，放在 "MAPQ Progressive Strategy" 之后、
> "Strand Type Determination" 之前，或作为 "Technical Details" 下的独立子章节。

### 2. ⚠️ README.md L173 仍写 `MAPQ-20/10/3/0`（应为 `/1`）

```
- `MAPQ_Filter`: final MAPQ cutoff used (`MAPQ-20/10/3/0`)  ← 过时
```

代码已改为 `@MAPQ_LEVELS = (20, 10, 3, 1)`，需同步更新为 `MAPQ-20/10/3/1`。

### 3. ⚠️ README_zh.md L169 同样的问题

```
- `MAPQ_Filter`：最终采用的 MAPQ 阈值（`MAPQ-20/10/3/0`）  ← 过时
```

应改为 `MAPQ-20/10/3/1`。

### 4. ✅ 代码层面已完成的改动

以下已确认落实：

| 改动 | 状态 | 位置 |
|------|------|------|
| MAPQ 阶梯 `(20,10,3,0)` → `(20,10,3,1)` | ✅ | `default_counting_withChrom.pl` L72 |
| 单端流程 MAPQ ≥ 20 过滤 | ✅ | `fast_count_sam_primary.sh` L66-73 |
| 代码注释与头部文档已同步 | ✅ | `default_counting_withChrom.pl` L7-9, L61-62, L70-71 |
| 中文 README "多重比对 read 的处理" 章节 | ✅ | `README_zh.md` |
