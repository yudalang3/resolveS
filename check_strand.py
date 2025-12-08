#!/usr/bin/env python3
"""
Strand bias analysis tool for NGS data
Processes count files and performs comprehensive strand bias analysis
"""

import sys
import math
from typing import List, Tuple


class StrandStats:
    """Data class to store all statistics"""
    def __init__(self, filename: str, fwd: int, rev: int, total: int,
                 fwd_ratio: float, rev_ratio: float, f2r_ratio: float,
                 log2_f2r: float, relative_diff: float, chi2: float,
                 p_value: float, cohens_h: float, cramers_v: float,
                 bayes_factor: float, epsilon: float, hellinger: float,
                 entropy: float, strandedness: str):
        self.filename = filename
        self.strandedness = strandedness
        self.fwd = fwd
        self.rev = rev
        self.total = total
        self.fwd_ratio = fwd_ratio
        self.rev_ratio = rev_ratio
        self.f2r_ratio = f2r_ratio
        self.log2_f2r = log2_f2r
        self.relative_diff = relative_diff
        self.chi2 = chi2
        self.p_value = p_value
        self.cohens_h = cohens_h
        self.cramers_v = cramers_v
        self.bayes_factor = bayes_factor
        self.epsilon = epsilon
        self.hellinger = hellinger
        self.entropy = entropy


def compute_proportions(fwd: int, rev: int) -> Tuple[float, float, float]:
    """
    Calculate proportions of forward and reverse strands

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        (forward ratio, reverse ratio, forward/reverse ratio)
    """
    total = fwd + rev
    if total == 0:
        return 0.0, 0.0, float('nan')

    fwd_ratio = fwd / total
    rev_ratio = rev / total

    # Avoid division by zero
    f2r_ratio = fwd / rev if rev > 0 else float('inf')

    return fwd_ratio, rev_ratio, f2r_ratio


def compute_f2r_ratio_logfc(fwd: int, rev: int, pseudo_count: float = 0.5) -> float:
    """
    Calculate log2 value of forward/reverse ratio (Log2 Fold Change)

    Using pseudocount to avoid division by zero and log(0) issues

    Args:
        fwd: Forward strand count
        rev: Reverse strand count
        pseudo_count: Pseudocount, default 0.5

    Returns:
        log2(fwd/rev)
    """
    # Add pseudocount
    fwd_adj = fwd + pseudo_count
    rev_adj = rev + pseudo_count

    return math.log2(fwd_adj / rev_adj)


def compute_relative_difference(fwd: int, rev: int) -> float:
    """
    Calculate relative difference (Relative Difference)

    Formula: |fwd - rev| / ((fwd + rev) / 2)
    Range: 0 (completely equal) to 2 (one is 0)

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        Relative difference value
    """
    total = fwd + rev
    if total == 0:
        return float('nan')

    mean = total / 2.0
    return abs(fwd - rev) / mean


def compute_chi_test(fwd: int, rev: int) -> Tuple[float, float]:
    """
    Calculate chi-square test chi-square value and P-value

    Null hypothesis: Forward and reverse strand distribution is 50:50
    Degrees of freedom: df = 1

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        (chi-square value, P-value)
    """
    total = fwd + rev
    if total == 0:
        return float('nan'), float('nan')

    expected = total / 2.0

    # Chi-square calculation
    chi2 = ((fwd - expected) ** 2 / expected) + ((rev - expected) ** 2 / expected)

    # P-value calculation (chi-square distribution with df=1)
    p_value = math.erfc(math.sqrt(chi2 / 2.0))

    return chi2, p_value


def compute_cohens_h(fwd: int, rev: int) -> float:
    """
    Calculate Cohen's h effect size

    Used to compare the magnitude of difference between two proportions
    Formula: h = 2 * (arcsin(sqrt(p1)) - arcsin(sqrt(p2)))

    Interpretation:
        |h| < 0.2: Small effect
        0.2 <= |h| < 0.5: Medium effect
        0.5 <= |h| < 0.8: Large effect
        |h| >= 0.8: Very large effect

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        Cohen's h value
    """
    total = fwd + rev
    if total == 0:
        return float('nan')

    p_observed = fwd / total  # Observed forward strand proportion
    p_expected = 0.5  # Expected forward strand proportion

    # Cohen's h formula
    phi_observed = 2 * math.asin(math.sqrt(p_observed))
    phi_expected = 2 * math.asin(math.sqrt(p_expected))

    return phi_observed - phi_expected


def compute_cramers_v(fwd: int, rev: int) -> float:
    """
    Calculate Cramér's V effect size

    For 2x1 case (comparing observed vs expected values), simplified to:
    V = sqrt(chi2 / n)

    Interpretation:
        V < 0.1: Negligible
        0.1 <= V < 0.3: Small effect
        0.3 <= V < 0.5: Medium effect
        V >= 0.5: Large effect

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        Cramér's V value
    """
    total = fwd + rev
    if total == 0:
        return float('nan')

    chi2, _ = compute_chi_test(fwd, rev)

    # For 2x1 table, degrees of freedom k = min(r-1, c-1) = 1
    # V = sqrt(chi2 / (n * k)) = sqrt(chi2 / n)
    return math.sqrt(chi2 / total)


def compute_bayes_factor(fwd: int, rev: int) -> float:
    """
    Calculate Bayes Factor - Method to solve large sample size issues

    Core advantages of this method:
    1. Does not automatically tend toward "significant" as sample size increases
    2. Can support null hypothesis (not just reject)
    3. Provides continuous measure of evidence strength

    We compare two hypotheses:
    - H0: p = 0.5 (uniform distribution of forward and reverse strands)
    - H1: p ≠ 0.5 (non-uniform distribution of forward and reverse strands, using Beta(1,1) prior)

    Using Savage-Dickey density ratio method to calculate BF01 (evidence supporting H0)

    Interpretation of BF01:
        BF01 > 100: Extreme evidence for uniform distribution
        30 < BF01 <= 100: Very strong evidence for uniform distribution
        10 < BF01 <= 30: Strong evidence for uniform distribution
        3 < BF01 <= 10: Moderate evidence for uniform distribution
        1 < BF01 <= 3: Weak evidence for uniform distribution
        1/3 < BF01 <= 1: Weak evidence for non-uniform distribution
        1/10 < BF01 <= 1/3: Moderate evidence for non-uniform distribution
        1/30 < BF01 <= 1/10: Strong evidence for non-uniform distribution
        1/100 < BF01 <= 1/30: Very strong evidence for non-uniform distribution
        BF01 <= 1/100: Extreme evidence for non-uniform distribution

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        Bayes factor BF01
    """
    total = fwd + rev
    if total == 0:
        return float('nan')

    # Using Savage-Dickey density ratio
    # Prior: Beta(1, 1) = Uniform(0, 1)
    # Posterior: Beta(fwd + 1, rev + 1)
    # BF01 = posterior density at p=0.5 / prior density at p=0.5

    # Prior density at p=0.5 (Beta(1,1) = 1 everywhere)
    prior_density = 1.0

    # Posterior Beta(fwd+1, rev+1) density at p=0.5
    # PDF of Beta distribution: f(x; a, b) = x^(a-1) * (1-x)^(b-1) / B(a, b)
    # At x=0.5: f(0.5) = 0.5^(a-1) * 0.5^(b-1) / B(a, b)
    #                   = 0.5^(a+b-2) / B(a, b)

    a = fwd + 1
    b = rev + 1

    # Calculate log(BF01) to avoid numerical overflow
    # log(posterior_density) = (a+b-2)*log(0.5) - log(B(a,b))
    # log(B(a,b)) = lgamma(a) + lgamma(b) - lgamma(a+b)

    log_beta = math.lgamma(a) + math.lgamma(b) - math.lgamma(a + b)
    log_posterior_density = (a + b - 2) * math.log(0.5) - log_beta
    log_prior_density = math.log(prior_density)  # = 0

    log_bf01 = log_posterior_density - log_prior_density
    bf01 = math.exp(log_bf01)

    return bf01

def compute_effect_size_epsilon(fwd: int, rev: int) -> float:
    """
    Epsilon 效应大小：样本大小不敏感的度量

    Epsilon = |p1 - p2| / sqrt(p1*(1-p1) + p2*(1-p2))
    其中 p1 是实际比例，p2 是期望比例（0.5）

    这个指标不会随着样本量增大而自动变大，更适合比较不同样本量的结果

    Args:
        fwd: 正链数量
        rev: 负链数量

    Returns:
        Epsilon 效应大小
    """
    total = fwd + rev
    if total == 0:
        return 0.0

    p1 = fwd / total
    p2 = 0.5

    numerator = abs(p1 - p2)
    denominator = math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))

    if denominator == 0:
        return 0.0

    epsilon = numerator / denominator

    return epsilon


def compute_hellinger_distance(fwd: int, rev: int) -> float:
    """
    Hellinger距离：测量两个概率分布的差异
    范围：0到1

    H(p,q) = sqrt(0.5 * sum((sqrt(p_i) - sqrt(q_i))^2))

    这个距离在统计意义上更稳定，对样本大小不敏感

    Args:
        fwd: 正链数量
        rev: 负链数量

    Returns:
        Hellinger距离
    """
    total = fwd + rev
    if total == 0:
        return 0.0

    p_fwd = fwd / total
    p_rev = rev / total

    # 期望分布（0.5, 0.5）
    q_fwd = 0.5
    q_rev = 0.5

    # H = sqrt(0.5 * ((sqrt(p1)-sqrt(q1))^2 + (sqrt(p2)-sqrt(q2))^2))
    h_dist = math.sqrt(
        0.5 * (
                (math.sqrt(p_fwd) - math.sqrt(q_fwd)) ** 2 +
                (math.sqrt(p_rev) - math.sqrt(q_rev)) ** 2
        )
    )

    return h_dist


def compute_normalized_entropy(fwd: int, rev: int) -> float:
    """
    归一化熵：衡量分布的"纯度"
    如果完全均匀分布（50:50），熵为1
    如果完全不均匀，熵接近0

    这是一个样本大小不敏感的指标

    Args:
        fwd: 正链数量
        rev: 负链数量

    Returns:
        熵值（0-1，1表示完全均匀）
    """
    total = fwd + rev
    if total == 0:
        return 0.0

    p_fwd = fwd / total
    p_rev = rev / total

    # 避免log(0)
    epsilon = 1e-10
    p_fwd = max(p_fwd, epsilon)
    p_rev = max(p_rev, epsilon)

    # Shannon熵
    entropy = -p_fwd * math.log2(p_fwd) - p_rev * math.log2(p_rev)

    # 归一化（最大熵为1）
    normalized_entropy = entropy / 1.0  # log2(2) = 1

    return normalized_entropy

def determine_strandedness(total: int, relative_diff: float, f2r_ratio: float) -> str:
    """
    Determine strandedness based on total count, relative difference, and F2R ratio
    
    Criteria:
    1. Total > 3000: Otherwise cannot infer, return 'insufficient-data'
    2. Rel_Diff > 1: Strand-specific sequencing; otherwise non-specific (fr-unstranded)
    3. F2R_Ratio > 1: fr-firststrand; otherwise fr-secondstrand
    
    Args:
        total: Total count (forward + reverse)
        relative_diff: Relative difference value
        f2r_ratio: Forward to reverse ratio
    
    Returns:
        Strandedness type: 'fr-firststrand', 'fr-secondstrand', 'fr-unstranded', or 'insufficient-data'
    """
    # Check if total count is sufficient
    if total <= 3000:
        return 'insufficient-data'
    
    # Check if strand-specific
    if relative_diff <= 1:
        return 'fr-unstranded'
    
    # Determine strand orientation
    if f2r_ratio > 1:
        return 'fr-firststrand'
    else:
        return 'fr-secondstrand'


def analyze_strand_bias(fwd: int, rev: int, name: str) -> StrandStats:
    """
    Comprehensive analysis of forward/reverse strand preference

    Args:
        fwd: Forward strand count
        rev: Reverse strand count
        name: The identifier

    Returns:
        StrandStats object containing all statistics
    """
    total = fwd + rev

    # Calculate various statistics
    fwd_ratio, rev_ratio, f2r_ratio = compute_proportions(fwd, rev)
    log2_f2r = compute_f2r_ratio_logfc(fwd, rev)
    relative_diff = compute_relative_difference(fwd, rev)
    chi2, p_value = compute_chi_test(fwd, rev)
    cohens_h = compute_cohens_h(fwd, rev)
    cramers_v = compute_cramers_v(fwd, rev)
    bayes_factor = compute_bayes_factor(fwd, rev)

    epsilon = compute_effect_size_epsilon(fwd, rev)
    hellinger = compute_hellinger_distance(fwd, rev)
    entropy = compute_normalized_entropy(fwd, rev)
    
    # Determine strandedness using the new criteria
    strandedness = determine_strandedness(total, relative_diff, f2r_ratio)

    return StrandStats(
        filename=name,
        fwd=fwd,
        rev=rev,
        total=total,
        fwd_ratio=fwd_ratio,
        rev_ratio=rev_ratio,
        f2r_ratio=f2r_ratio,
        log2_f2r=log2_f2r,
        relative_diff=relative_diff,
        chi2=chi2,
        p_value=p_value,
        cohens_h=cohens_h,
        cramers_v=cramers_v,
        bayes_factor=bayes_factor,
        epsilon=epsilon,
        hellinger=hellinger,
        entropy=entropy,
        strandedness=strandedness
    )


def read_counts_file(filepath: str) -> List[Tuple[int, int, str]]:
    """
    Read count file - process all lines in the file
    # Data like this
    #4000000 3117 37696 3959187 0 0 /home/dell/projects/estimate_strand4NGS/test_data/ss/1-1/1-1_1.fq.gz
    #4000000 3117 37696 3959187 0 0 /home/dell/projects/estimate_strand4NGS/test_data/ss/1-1/1-1_1.fq.gz

    Args:
        filepath: File path

    Returns:
        List of tuples (forward count, reverse count, base file name, line number)
    """
    results = []

    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f):
            line = line.strip()
            if not line:  # Skip empty lines
                continue
                
            parts = line.split()
            if len(parts) < 3:
                raise ValueError(f"File format error on line {line_num+1}, need at least 3 columns: {filepath}")

            fwd = int(parts[1])
            rev = int(parts[2])
            name = str(parts[6])
            results.append((fwd, rev, name))
            
    return results


def format_stats_table(stats_list: List[StrandStats], sep: str = "\t") -> str:
    """
    Format statistical results as table

    Args:
        stats_list: List of StrandStats objects
        sep: Separator

    Returns:
        Formatted table string
    """
    # Table header
    headers = [
        "File",
        "Strandedness",
        "Fwd",
        "Rev",
        "Total",
        "Fwd_Ratio",
        "Rev_Ratio",
        "F2R_Ratio",
        "Log2_F2R",
        "Rel_Diff",
        "Chi2",
        "P_value",
        "Cohens_h",
        "Cramers_V",
        "Bayes_Factor",
        "Epsilon",
        "Hellinger",
        "Entropy"
    ]

    lines = [sep.join(headers)]

    for s in stats_list:
        row = [
            s.filename,
            s.strandedness,
            str(s.fwd),
            str(s.rev),
            str(s.total),
            f"{s.fwd_ratio:.6f}",
            f"{s.rev_ratio:.6f}",
            f"{s.f2r_ratio:.6f}" if not math.isinf(s.f2r_ratio) else "Inf",
            f"{s.log2_f2r:.6f}",
            f"{s.relative_diff:.6f}",
            f"{s.chi2:.6f}",
            f"{s.p_value:.6e}",
            f"{s.cohens_h:.6f}",
            f"{s.cramers_v:.6f}",
            f"{s.bayes_factor:.6e}",
            f"{s.epsilon:.6f}",
            f"{s.hellinger:.6f}",
            f"{s.entropy:.6f}"
        ]
        lines.append(sep.join(row))

    return "\n".join(lines)


# def stats_to_dataframe(stats_list: List[StrandStats]) -> pd.DataFrame:
#     """
#     Convert list of StrandStats to pandas DataFrame
#
#     Args:
#         stats_list: List of StrandStats objects
#
#     Returns:
#         pandas DataFrame with all statistics
#     """
#     if not stats_list:
#         return pd.DataFrame()
#
#     data = []
#     for stats in stats_list:
#         row = {
#             "File": stats.filename,
#             "Forward": stats.fwd,
#             "Reverse": stats.rev,
#             "Total": stats.total,
#             "FWD_Prop": stats.fwd_ratio,
#             "REV_Prop": stats.rev_ratio,
#             "F2R_Ratio": stats.f2r_ratio if not math.isinf(stats.f2r_ratio) else float('inf'),
#             "Log2FC": stats.log2_f2r,
#             "Rel_Diff": stats.relative_diff,
#             "Chi2": stats.chi2,
#             "P_Value": stats.p_value,
#             "Cohens_h": stats.cohens_h,
#             "Cramers_V": stats.cramers_v,
#             "Bayes_Factor": stats.bayes_factor,
#             "Bayes_Interpretation": stats.bayes_interpretation,
#             "Epsilon": stats.epsilon,
#             "Hellinger": stats.hellinger,
#             "Entropy": stats.entropy
#         }
#         data.append(row)
#
#     return pd.DataFrame(data)


def print_detailed_report(stats: StrandStats):
    """
    Print detailed analysis report

    Args:
        stats: StrandStats object
    """
    print("=" * 60)
    print(f"Strand preference analysis report: {stats.filename}")
    print("=" * 60)

    print("\n[Basic Statistics]")
    print(f"  Forward strand: {stats.fwd:,}")
    print(f"  Reverse strand: {stats.rev:,}")
    print(f"  Total         : {stats.total:,}")

    print("\n[Proportion Statistics]")
    print(f"  Forward ratio: {stats.fwd_ratio:.4f} ({stats.fwd_ratio * 100:.2f}%)")
    print(f"  Reverse ratio: {stats.rev_ratio:.4f} ({stats.rev_ratio * 100:.2f}%)")
    print(f"  F/R ratio: {stats.f2r_ratio:.4f}")
    print(f"  Log2(F/R): {stats.log2_f2r:.4f}")
    print(f"  Relative difference: {stats.relative_diff:.4f}")

    print("\n[Chi-square Test]")
    print(f"  Chi-square value: {stats.chi2:.4f}")
    print(f"  P-value: {stats.p_value:.4e}")
    if stats.p_value < 0.05:
        print("  Conclusion: P < 0.05, distribution significantly non-uniform")
    else:
        print("  Conclusion: P >= 0.05, uniform distribution")

    print("\n[Effect Size]")
    print(f"  Cohen's h: {stats.cohens_h:.4f}", end="")
    h_abs = abs(stats.cohens_h)
    if h_abs < 0.2:
        print(" (Small effect)")
    elif h_abs < 0.5:
        print(" (Medium effect)")
    elif h_abs < 0.8:
        print(" (Large effect)")
    else:
        print(" (Very large effect)")

    print(f"  Cramér's V: {stats.cramers_v:.4f}", end="")
    if stats.cramers_v < 0.1:
        print(" (Negligible)")
    elif stats.cramers_v < 0.3:
        print(" (Small effect)")
    elif stats.cramers_v < 0.5:
        print(" (Medium effect)")
    else:
        print(" (Large effect)")

    print("\n[Bayesian Analysis] (Recommended for large samples)")
    print(f"  Bayes factor (BF01): {stats.bayes_factor:.4e}")
    print("  Note: BF01 > 1 supports uniform distribution hypothesis, BF01 < 1 supports non-uniform distribution hypothesis")

    print("\n[Strandedness]")
    print(f"  Type: {stats.strandedness}")

    print("\n" + "=" * 60)


def demo_sample_size_effect():
    """
    Demonstrate the effect of sample size on different methods
    """
    print("\n" + "=" * 60)
    print("[Demo] Effect of sample size on statistical methods")
    print("=" * 60)
    print("\nAssuming true ratio is 51:49 (slight deviation)")
    print("-" * 60)

    # Different sample sizes, but same ratio (51:49)
    test_cases = [
        (51, 49, "n=100"),
        (510, 490, "n=1,000"),
        (5100, 4900, "n=10,000"),
        (51000, 49000, "n=100,000"),
        (510000, 490000, "n=1,000,000"),
    ]

    print(f"{'Sample size':<15} {'P-value':<12} {'Cohen_h':<10} {'Cramer_V':<10} {'BF01':<12} {'Bayes interpretation'}")
    print("-" * 80)

    stats_list = []
    for fwd, rev, name in test_cases:
        stats = analyze_strand_bias(fwd, rev, name)
        stats_list.append(stats)

    # df = stats_to_dataframe(stats_list)
    # print(df.to_string(index=False))

    print("\nObservations:")
    print("1. P-values decrease sharply as sample size increases → Almost certainly 'significant' with large samples")
    print("2. Cohen's h remains stable → True effect size unchanged")
    print("3. Cramér's V decreases with sample size → Not suitable for this scenario")
    print("4. Bayes factor provides more robust judgment → Not 'biased' by sample size")


def run_input_file_lists(file_list):
    stats_list = []
    for filepath in file_list:
        try:
            # Read all lines from the file
            file_data = read_counts_file(filepath)
            
            # Process each line in the file
            for fwd, rev, name in file_data:
                stats = analyze_strand_bias(fwd, rev, name)
                stats_list.append(stats)
                
        except FileNotFoundError:
            print(f"Error: File not found {filepath}")
        except ValueError as e:
            print(f"Error: {e}")
    return stats_list


def main():
    """Main function"""
    if len(sys.argv) < 2:
        # Demo mode
        print("Usage: python check_strand.py <file.counts.txt> [output.tsv]")
    else:
        input_file = sys.argv[1]
        stats_list = run_input_file_lists([input_file])
        my_str = format_stats_table(stats_list)
        # df = stats_to_dataframe(stats_list)
        if len(sys.argv) >= 3:
            output_file = sys.argv[2]
            with open(output_file, "w") as f:
                f.write(my_str)
        else:
            print(my_str)





if __name__ == "__main__":
    main()

