# auto_counting_withChrom.pl 后续优化建议

基于当前未提交版本的 `auto_counting_withChrom.pl` 代码检查和新旧版本差分验证，当前“一次扫描 SAM，按 MAPQ tier 聚合，再在内存中复用计数”的主优化方向是正确的。已验证的核心行为包括：

- `single` / `pair` 模式校验保持一致
- pair 模式仍只统计 first-in-pair、proper-pair 记录
- unmapped、mate-unmapped、secondary、supplementary 记录仍被过滤
- MAPQ 20 -> 10 -> 3 -> 1 的自适应降级结果与旧实现一致
- MAPQ=0 在最低阈值下仍被排除

后续优化建议按优先级如下。

---

## 1. 增加确定性 tie-breaker，避免平局排序影响检测结果

### 当前问题

当前排序只按每个 rRNA 序列的总比对数降序：

```perl
    my @sorted_chroms = sort {
        my $ta = ($chrom_fwd{$a} // 0) + ($chrom_rev{$a} // 0);
        my $tb = ($chrom_fwd{$b} // 0) + ($chrom_rev{$b} // 0);
        $tb <=> $ta;
    } keys %valid_chroms;
```

当多个序列 total count 相同时，排序会依赖 hash key 遍历顺序。这个问题不只是 debug 日志顺序不稳定：如果平局刚好发生在 top 3 / 5 / 7 / 8 的边界，可能影响投票输入集合，从而改变最终检测结果。

### 建议方案

优先使用 SAM header 中 `@SQ` 的出现顺序作为二级排序依据；如果某个序列没有 header 顺序，再 fallback 到序列名 `cmp`。这样既可复现，也更符合参考序列原始顺序。

如果暂时不想解析 header，最低限度也应增加名称排序作为稳定 fallback：

```perl
    my @sorted_chroms = sort {
        my $ta = ($chrom_fwd{$a} // 0) + ($chrom_rev{$a} // 0);
        my $tb = ($chrom_fwd{$b} // 0) + ($chrom_rev{$b} // 0);
        $tb <=> $ta || $a cmp $b;
    } keys %valid_chroms;
```

注意：`$a cmp $b` 是字典序，`chr10` 会排在 `chr2` 前。因此更推荐 `@SQ` 顺序。

---

## 2. 只在 debug 模式构建 debug rows 和列宽

### 当前问题

当前代码即使 `$DEBUG == 0`，仍会遍历 `@sorted_chroms` 构建 `@debug_rows` 并计算列宽，最后再调用不会输出内容的 `debug_print`。如果 rRNA/contig 数量较多，这部分会产生不必要的内存分配和字符串长度计算。

### 建议方案

将 `@debug_rows`、`$chrom_width` / `$fwd_width` / `$rev_width` / `$total_width` / `$major_width` 的维护放进 `if ($DEBUG)` 分支。非 debug 模式只保留必要的 fwd/rev/tie 汇总计数。

这个优化比 `split` 解包这类微优化更值得优先考虑，因为它能直接跳过整段只服务 debug 输出的工作。

---

## 3. 补充回归测试，锁定优化前后行为一致性

### 当前测试缺口

现有测试能覆盖 basic single/pair 模式和部分链特异性判定，但还没有专门覆盖这次性能优化最关键的行为边界。

### 建议新增测试场景

- MAPQ-20 时全部 insufficient，降到 MAPQ-10 / 3 / 1 后成功
- MAPQ=0 永远不参与最低阈值统计
- pair 模式过滤 second-in-pair、not proper pair、mate unmapped
- single 模式遇到 paired flag 时失败
- total count 平局时 top 3 / 5 / 7 / 8 的排序结果稳定
- 同一个人工 SAM 同时跑旧实现和新实现，输出完全一致

如果只新增一类测试，优先新增“MAPQ 降级 + flag 过滤 + tie-breaker”的人工 SAM regression test。

---

## 4. 可选：合并 bitmask 优化 flag 过滤逻辑

### 当前代码

当前实现使用多次独立位运算和分支判断，可读性较好，但热循环中分支较多。

### 可选方案

可以用常量名封装 bitmask，减少重复判断：

```perl
use constant PAIR_REQUIRED   => 0x43;  # paired (0x1), proper-pair (0x2), first-in-pair (0x40)
use constant PAIR_EXCLUDED   => 0x90c; # unmapped, mate-unmapped, secondary, supplementary
use constant SINGLE_EXCLUDED => 0x904; # unmapped, secondary, supplementary

if ($expected_mode eq 'pair') {
    next if ($flag & PAIR_REQUIRED) != PAIR_REQUIRED || ($flag & PAIR_EXCLUDED);
} else {
    next if ($flag & SINGLE_EXCLUDED);
}
```

重要修正：pair 模式的 required mask 应为 `0x43`，不是 `0x42`。`0x42` 只包含 proper-pair 和 first-in-pair，不包含 paired bit `0x1`。虽然当前代码前面已有 mode validation，使用 `0x42` 通常不会导致实际漏判，但注释和实现都不严谨。

这个优化属于微优化，建议在补齐测试后再做。

---

## 5. 可选：微调 Tier 累加循环

当前代码在最多 4 个 tier 内重复检查 `$f_tiers` / `$r_tiers`：

```perl
        for my $i (0 .. $max_tier) {
            $f += $f_tiers->[$i] // 0 if $f_tiers;
            $r += $r_tiers->[$i] // 0 if $r_tiers;
        }
```

可以改为：

```perl
        if ($f_tiers) {
            $f += $f_tiers->[$_] // 0 for 0 .. $max_tier;
        }
        if ($r_tiers) {
            $r += $r_tiers->[$_] // 0 for 0 .. $max_tier;
        }
```

但这里最多只有 4 次循环，不是数十到数百次。收益预计很小，主要价值是让意图稍微更清楚。

---

## 6. 可选：`split` 解包赋值

当前代码：

```perl
        my @fields = split /\t/, $_, 6;
        next if @fields < 2;
        my $flag = $fields[1];
```

可以改为：

```perl
        my (undef, $flag, $chrom, undef, $mapq) = split /\t/, $_, 6;
        next unless defined $flag;
```

但需要保留当前行为：有 `$flag` 的 alignment record 要计入 `$alignment_records`，缺少 `$mapq` 的记录只跳过计数。这个优化的性能收益可能低于 bitmask 和 debug 懒构建，不建议优先做。

---

## 预期收益与建议顺序

已完成的一次扫描 + MAPQ tier 聚合是主要性能收益来源。后续微优化不宜预期过高，除非用大 SAM 文件 benchmark 重新验证。

建议实施顺序：

1. 增加 tie-breaker，优先使用 `@SQ` 顺序
2. 增加 regression test，覆盖 MAPQ 降级、flag 过滤和平局排序
3. 将 debug rows / 列宽计算改为只在 debug 模式执行
4. 在测试通过后，再考虑 bitmask、Tier 累加和 `split` 解包等微优化

如果没有新的 benchmark 结果，不建议继续声称这些微优化还能稳定带来 5% ~ 10% 加速。
