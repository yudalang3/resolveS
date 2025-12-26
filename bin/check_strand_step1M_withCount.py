#!/usr/bin/env python3
"""
Strand bias analysis tool for NGS data - Step 1M version (Count-based)
Processes count files with 1M incremental records and performs 
strand bias analysis based on raw counts instead of ratios.
"""

import sys
import math
from typing import List, Tuple, NamedTuple

# Import from check_strand.py
from check_strand import determine_strandedness, compute_relative_difference


class CountBasedStats(NamedTuple):
    """Data class to store count-based statistics"""
    reads_count: str      # e.g., "1M", "2M"
    fwd: int              # Forward strand count
    rev: int              # Reverse strand count
    total: int            # Total = Fwd + Rev
    diff: int             # |Fwd - Rev|
    log2_fc: float        # log2(Fwd / Rev) with pseudocount
    chi2: float           # Chi-square statistic (based on raw counts)
    p_value: float        # P-value from chi-square test
    binomial_p: float     # Binomial test p-value
    strandedness: str     # Final determination


def compute_log2_fc(fwd: int, rev: int, pseudo: float = 0.5) -> float:
    """
    Compute log2 fold change with pseudocount
    
    Args:
        fwd: Forward strand count
        rev: Reverse strand count
        pseudo: Pseudocount to avoid log(0)
    
    Returns:
        log2((fwd + pseudo) / (rev + pseudo))
    """
    return math.log2((fwd + pseudo) / (rev + pseudo))


def compute_chi2_test(fwd: int, rev: int) -> Tuple[float, float]:
    """
    Chi-square goodness-of-fit test against 50:50 null hypothesis
    
    This is directly based on raw counts:
    Chi2 = (Fwd - E)^2/E + (Rev - E)^2/E, where E = (Fwd+Rev)/2
    
    Args:
        fwd: Forward strand count
        rev: Reverse strand count
    
    Returns:
        (chi2 statistic, p-value)
    """
    total = fwd + rev
    if total == 0:
        return float('nan'), float('nan')
    
    expected = total / 2.0
    chi2 = ((fwd - expected) ** 2 + (rev - expected) ** 2) / expected
    
    # P-value using complementary error function (approximation for df=1)
    p_value = math.erfc(math.sqrt(chi2 / 2.0))
    
    return chi2, p_value


def compute_binomial_p(fwd: int, rev: int) -> float:
    """
    Two-tailed binomial test p-value (exact test based on raw counts)
    
    Tests if observed (fwd, rev) significantly differs from 50:50
    Uses normal approximation for large n
    
    Args:
        fwd: Forward strand count
        rev: Reverse strand count
    
    Returns:
        Two-tailed p-value
    """
    n = fwd + rev
    if n == 0:
        return float('nan')
    
    # Normal approximation for binomial (valid when n is large)
    # Z = (X - np) / sqrt(np(1-p)), where p = 0.5
    p = 0.5
    mean = n * p
    std = math.sqrt(n * p * (1 - p))
    
    if std == 0:
        return 1.0
    
    z = abs(fwd - mean) / std
    
    # Two-tailed p-value using complementary error function
    p_value = math.erfc(z / math.sqrt(2))
    
    return p_value


def analyze_counts(fwd: int, rev: int, label: str) -> CountBasedStats:
    """
    Analyze strand bias using raw counts
    
    Args:
        fwd: Forward strand count
        rev: Reverse strand count
        label: Label for this record (e.g., "1M")
    
    Returns:
        CountBasedStats object
    """
    total = fwd + rev
    diff = abs(fwd - rev)
    log2_fc = compute_log2_fc(fwd, rev)
    chi2, p_value = compute_chi2_test(fwd, rev)
    binomial_p = compute_binomial_p(fwd, rev)
    
    # Use imported functions from check_strand.py
    relative_diff = compute_relative_difference(fwd, rev)
    strandedness = determine_strandedness(total, relative_diff)
    
    return CountBasedStats(
        reads_count=label,
        fwd=fwd,
        rev=rev,
        total=total,
        diff=diff,
        log2_fc=log2_fc,
        chi2=chi2,
        p_value=p_value,
        binomial_p=binomial_p,
        strandedness=strandedness
    )


def read_incremental_counts_file(filepath: str) -> List[Tuple[int, int, str]]:
    """
    Read incremental count file
    
    Data format (output from count_sam_1M_increase.sh):
    1000000 3117 37696 959187 0 0 1M /path/to/file.fq.gz
    
    Args:
        filepath: File path
    
    Returns:
        List of tuples (forward count, reverse count, label)
    """
    results = []

    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
                
            parts = line.split()
            if len(parts) < 7:
                raise ValueError(f"File format error on line {line_num+1}, need at least 7 columns")

            fwd = int(parts[1])
            rev = int(parts[2])
            label = str(parts[6])  # e.g., "1M", "2M"
                
            results.append((fwd, rev, label))
            
    return results


def format_stats_table(stats_list: List[CountBasedStats], sep: str = "\t") -> str:
    """
    Format statistical results as TSV table
    
    Args:
        stats_list: List of CountBasedStats objects
        sep: Separator
    
    Returns:
        Formatted table string
    """
    headers = [
        "ReadsCounts",
        "Strandedness",
        "Fwd",
        "Rev",
        "Total",
        "Diff",
        "Log2_FC",
        "Chi2",
        "P_value",
        "Binomial_P"
    ]

    lines = [sep.join(headers)]

    for s in stats_list:
        row = [
            s.reads_count,
            s.strandedness,
            str(s.fwd),
            str(s.rev),
            str(s.total),
            str(s.diff),
            f"{s.log2_fc:.4f}",
            f"{s.chi2:.2f}",
            f"{s.p_value:.2e}",
            f"{s.binomial_p:.2e}"
        ]
        lines.append(sep.join(row))

    return "\n".join(lines)


def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("Usage: python check_strand_step1M_withCount.py <file.counts.txt> [output.tsv]")
        print()
        print("This version uses raw counts (Fwd, Rev) directly for statistics,")
        print("instead of ratio-based metrics.")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) >= 3 else None
    
    # Read and process counts file
    stats_list = []
    try:
        file_data = read_incremental_counts_file(input_file)
        for fwd, rev, label in file_data:
            stats = analyze_counts(fwd, rev, label)
            stats_list.append(stats)
    except FileNotFoundError:
        print(f"Error: File not found {input_file}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Output results
    my_str = format_stats_table(stats_list)
    
    if output_file:
        with open(output_file, "w") as f:
            f.write(my_str)
    else:
        print(my_str)


if __name__ == "__main__":
    main()
