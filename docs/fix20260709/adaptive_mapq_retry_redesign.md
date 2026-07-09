# Adaptive MAPQ 重试策略重新设计

## 问题回顾

### 已修复的第一个 Bug
原来的条件只检查 `detection_level ne 'all-insufficient-fallback'`，导致 `only-0-rRNAs-fallback` 时误判为成功。

### 当前仍存在的问题
程序在 MAPQ=3 时得到 `all-insufficient-fallback`（9 条 rRNA 全部 reads 不足），全局 fallback 给出 `fr-firststrand`（fwd:2 vs rev:7）。由于 `final_type = 'fr-firststrand'` 不是 `'insufficient-data'`，程序就停止了。

**但这个结果可靠吗？**

下面是该样本在各 MAPQ 阈值下的实际比对情况（包含 MAPQ >= 0）：

| MAPQ 阈值 | rRNA 数 | 总 reads | ≥18 reads 的 rRNA 数 | fwd | rev | Rel_Diff |
|-----------|--------|---------|---------------------|-----|-----|----------|
| ≥ 20 | 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| ≥ 10 | 0 | 0 | 0 / 0 | 0 | 0 | 0 |
| **≥ 3** | **9** | **25** | **0 / 9** | **2** | **7** | **-1.11** |
| **≥ 1** | **33** | **60** | **0 / 33** | **9** | **23** | **-0.875** |
| **≥ 0** | **109** | **252** | **1 / 109** | **44** | **56** | **-0.24** |

> [!NOTE]
> 从上表可以看出：
> 1. 在 MAPQ=3 时，虽然判定为 `fr-firststrand`，但数据量太少（仅 25 个 reads 散布在 9 个 rRNA 上，且没有一个 rRNA 的 reads 数达到 18 阈值）。
> 2. 降到 MAPQ=1 时，有 33 条 rRNA 和 60 个 reads，判定依然是 `fr-firststrand`，数据量显著增加。
> 3. 如果降到 MAPQ=0（包含多重比对 reads），虽然数据量大（252 reads），但 Rel_Diff 变为了 -0.24，即变成 unstranded 趋势（这是因为 MAPQ=0 的多重比对 reads 会无序地堆积在许多 rRNA 序列上，引入大量随机噪声）。这也是程序设计“最低降至 MAPQ=1，不降到 0”的初衷：**排除纯随机的多重比对噪声**。
>
> 综上，在还有更低 MAPQ 档位（如从 3 降到 1）可用时，如果前一档位数据不充分，应该继续降阈值。

---

## 概念解释与重试逻辑拓展

用户提出：`only-3-rRNAs-fallback`，`only-4~7-rRNAs-fallback` 代表什么意思？为什么它们也应该降低 MAPQ 重试？

### 1. 这些 Detection Level 的具体含义

resolveS 采用的是 **渐进式多数判定（Progressive Majority Detection）** 机制，层层递进：
- **Level 1 (前 3 选 3)**：前 3 条最丰度 rRNA 的链方向必须 100% 一致（3of3）。
- **Level 2 (前 5 选 4)**：前 5 条 rRNA 中必须有 4 条一致（4of5）。
- **Level 3 (前 7 选 6)**：前 7 条 rRNA 中必须有 6 条一致（6of7）。
- **Level 4 (前 8 选 7)**：前 8 条 rRNA 中必须有 7 条一致（7of8）。

如果在某个 MAPQ 阈值下：
* **“3 条但 Level 1 失败” (`only-3-rRNAs-fallback`)**：
  我们找到了 3 条满足 reads 数（≥18）的 rRNA。但由于它们的方向不一致（例如 2 个 fwd，1 个 rev），导致 Level 1 (3of3) 判定失败。因为总共只找到了 3 条 valid rRNA，达不到 Level 2 所需的 5 条，因此判定直接中断，走向全局 fallback。
* **“有数据但级别不够” (`only-4~7-rRNAs-fallback`)**：
  同理，例如找到了 4 条 valid rRNA。Level 1 判定失败了，我们想去尝试 Level 2。但 Level 2 至少需要 **5 条** 序列来投票。我们手里只有 4 条，连投票候选人都凑不齐。因此中断，走向全局 fallback。

### 2. 为什么它们也应该继续降低 MAPQ 重试？

当发生 `only-3-rRNAs-fallback` 或 `only-4~7-rRNAs-fallback` 时，说明当前的 MAPQ 过滤可能太严格，把一些本来属于其他 rRNA 序列的 reads 过滤掉了。

如果我们**降低 MAPQ**，会有两种极好的改善可能：
1. **增加现有 rRNA 的 reads 数**：原本某些 rRNA 因为 reads 数少于 18 条被排除在 valid 之外，降阈值后它们的 reads 超过 18 条，从而成为 valid 序列。
2. **发现更多新的 rRNA 序列**：增加 `total_chroms`，这让我们能够凑齐 5 条、7 条甚至 8 条 rRNA 候选，从而满足进入更高 Level 判定的条件，让多数投票机制生效，避免直接退化到简陋的全局 fallback。

因此，**凡是因为 rRNA 候选数量不足、或者丰度不够而退化到 fallback 的，都应该降低 MAPQ 重试**！

---

## 重新设计的重试决策表

根据上述逻辑，我们将重试逻辑彻底理清：

| 类别 | detection_level | 含义 | 降低 MAPQ 能否改善 | 是否重试 |
|------|----------------|------|:--:|:--:|
| **数据空缺** | `only-0-rRNAs-fallback` | 零条 rRNA 序列 | ✅ 寻找更多 reads / rRNA | **✅ 重试** |
| **数据空缺** | `only-1-rRNAs-fallback` | 仅 1 条 rRNA 序列 | ✅ 寻找更多 reads / rRNA | **✅ 重试** |
| **数据空缺** | `only-2-rRNAs-fallback` | 仅 2 条 rRNA 序列 | ✅ 寻找更多 reads / rRNA | **✅ 重试** |
| **级别不够** | `only-3-rRNAs-fallback` | 3 条 rRNA 但 Level 1 失败 | ✅ 寻找更多以进入 Level 2 | **✅ 重试** |
| **级别不够** | `only-4-rRNAs-fallback` | 4 条 rRNA 但达不到 Level 2 | ✅ 寻找更多以进入 Level 2 | **✅ 重试** |
| **级别不够** | `only-5-rRNAs-fallback` | 5 条 rRNA 但达不到 Level 3 | ✅ 寻找更多以进入 Level 3 | **✅ 重试** |
| **级别不够** | `only-6-rRNAs-fallback` | 6 条 rRNA 但达不到 Level 3 | ✅ 寻找更多以进入 Level 3 | **✅ 重试** |
| **级别不够** | `only-7-rRNAs-fallback` | 7 条 rRNA 但达不到 Level 4 | ✅ 寻找更多以进入 Level 4 | **✅ 重试** |
| **数据稀疏** | `all-insufficient-fallback` | 8+ 条 rRNA 但全部丰度不足 | ✅ 增加丰度，使其满足判定 | **✅ 重试** |
| **数据冲突** | `4of8-split-fallback` | 达到最高级8条，但 4:4 严重对半冲突 | ❌ 降低只会引入更多噪声 | ❌ 不重试 |
| **数据冲突** | `multi-of8-fallback` | 达到最高级8条，但多方严重分裂冲突 | ❌ 降低只会引入更多噪声 | ❌ 不重试 |
| **检测成功** | `3of3`, `4of5`, `6of7`, `7of8` | 渐进判定成功，无需 fallback | — | ❌ 不重试 |

---

## 修复方案：极简判断逻辑

我们发现，“不重试” 的条件其实只有两个：
1. **成功通过了渐进判定**（没有 `-fallback` 后缀）。
2. **在最高级 Level 4 发生了严重冲突**（即 `4of8-split-fallback` 或 `multi-of8-fallback`）。

除此之外的所有 fallback，均代表**数据不足**（rRNA 数不够或丰度不够），都应该降低 MAPQ 重试！

### 核心代码逻辑设计

在 Perl 循环中，可以使用如下判断：

```perl
    # 决定是否需要降低 MAPQ 阈值重试：
    # 1. 成功检测 (没有 '-fallback' 后缀) ── 停止重试
    # 2. 最高级 8 条 rRNA 发生严重冲突 (4of8-split-fallback 或 multi-of8-fallback) ── 停止重试
    # 3. 其他所有 fallback 场景 (数据量少、有效 rRNA 序列数不够) ── 降低 MAPQ 重试
    my $is_success = ($result->{detection_level} !~ /-fallback$/);
    my $is_conflict = ($result->{detection_level} =~ /^(?:4of8-split|multi-of8)-fallback$/);
    my $should_retry = !($is_success || $is_conflict);

    if (!$should_retry) {
        debug_print "\n[ADAPTIVE] Success at MAPQ=$mapq\n";
        last;
    }
    debug_print "[ADAPTIVE] Data scarce/incomplete at MAPQ=$mapq (level: $result->{detection_level}), trying lower MAPQ...\n";
```

---

## 变更文件与具体改动

我们需要在 `default_counting_withChrom.pl` 和 `auto_counting_withChrom.pl` 中同步修改。

### 1. 修改主要程序 `bin/default_counting_withChrom.pl`

#### 注释部分修改 (L8)
```perl
# 当遇到数据不足/不完整时，降低 MAPQ 重试
```

#### 注释部分修改 (L60)
```perl
# When detection_level indicates scarce data (e.g. only-N-rRNAs-fallback or all-insufficient-fallback), try lower MAPQ:
```

#### 逻辑部分修改 (L390)
将 `if ($result->{final_type} ne 'insufficient-data')` 修改为上述 `$should_retry` 逻辑。

### 2. 修改主要程序 `bin/auto_counting_withChrom.pl`
同步上述修改。
