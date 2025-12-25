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
    def __init__(self, filename: str, fwd: int, rev: int,
                 fwd_ratio: float, rev_ratio: float, relative_diff: float,
                 chi2: float, p_value: float, strandedness: str):
        self.filename = filename
        self.strandedness = strandedness
        self.fwd = fwd
        self.rev = rev
        self.fwd_ratio = fwd_ratio
        self.rev_ratio = rev_ratio
        self.relative_diff = relative_diff
        self.chi2 = chi2
        self.p_value = p_value


def compute_proportions(fwd: int, rev: int) -> Tuple[float, float]:
    """
    Calculate proportions of forward and reverse strands

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        (forward ratio, reverse ratio)
    """
    total = fwd + rev
    if total == 0:
        return 0.0, 0.0

    fwd_ratio = fwd / total
    rev_ratio = rev / total

    return fwd_ratio, rev_ratio


def compute_relative_difference(fwd: int, rev: int) -> float:
    """
    Calculate signed symmetric relative difference

    Formula: (fwd - rev) / ((fwd + rev) / 2)
    Range: -2 (reverse only) to +2 (forward only)
    Positive: forward-biased, Negative: reverse-biased

    Args:
        fwd: Forward strand count
        rev: Reverse strand count

    Returns:
        Signed relative difference value
    """
    total = fwd + rev
    if total == 0:
        return float('nan')

    mean = total / 2.0
    return (fwd - rev) / mean


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


def determine_strandedness(total: int, relative_diff: float) -> str:
    """
    Determine strandedness based on total count and signed relative difference
    
    Criteria:
    1. Total > 3000: Otherwise cannot infer, return 'insufficient-data'
    2. |Rel_Diff| > 1: Strand-specific sequencing; otherwise non-specific (fr-unstranded)
    3. Rel_Diff > 0: fr-firststrand (fwd > rev); Rel_Diff < 0: fr-secondstrand (rev > fwd)
    
    Args:
        total: Total count (forward + reverse)
        relative_diff: Signed relative difference value
    
    Returns:
        Strandedness type: 'fr-firststrand', 'fr-secondstrand', 'fr-unstranded', or 'insufficient-data'
    """
    if total <= 3000:
        return 'insufficient-data'
    
    if abs(relative_diff) <= 0.07156908:
        return 'fr-unstranded'
    
    if relative_diff > 0:
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

    # Calculate statistics
    fwd_ratio, rev_ratio = compute_proportions(fwd, rev)
    relative_diff = compute_relative_difference(fwd, rev)
    chi2, p_value = compute_chi_test(fwd, rev)
    
    # Determine strandedness using signed relative difference
    strandedness = determine_strandedness(total, relative_diff)

    return StrandStats(
        filename=name,
        fwd=fwd,
        rev=rev,
        fwd_ratio=fwd_ratio,
        rev_ratio=rev_ratio,
        relative_diff=relative_diff,
        chi2=chi2,
        p_value=p_value,
        strandedness=strandedness
    )


def read_counts_file(filepath: str) -> List[Tuple[int, int, str]]:
    """
    Read count file - process all lines in the file
    # Data format:
    # total fwd rev unmapped sec supp low_mapq filename
    # 4000000 3117 37696 3959187 0 0 100 /home/user/sample_1.fq.gz

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
            if len(parts) < 8:
                raise ValueError(f"File format error on line {line_num+1}, need at least 8 columns: {filepath}")

            fwd = int(parts[1])
            rev = int(parts[2])
            name = str(parts[7])
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
        "Fwd_Ratio",
        "Rev_Ratio",
        "Rel_Diff",
        "Chi2",
        "P_value"
    ]

    lines = [sep.join(headers)]

    for s in stats_list:
        row = [
            s.filename,
            s.strandedness,
            str(s.fwd),
            str(s.rev),
            f"{s.fwd_ratio:.6f}",
            f"{s.rev_ratio:.6f}",
            f"{s.relative_diff:.6f}",
            f"{s.chi2:.6f}",
            f"{s.p_value:.6e}"
        ]
        lines.append(sep.join(row))

    return "\n".join(lines)


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
        if len(sys.argv) >= 3:
            output_file = sys.argv[2]
            with open(output_file, "w") as f:
                f.write(my_str)
        else:
            print(my_str)


if __name__ == "__main__":
    main()
