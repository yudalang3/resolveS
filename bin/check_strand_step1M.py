#!/usr/bin/env python3
"""
Strand bias analysis tool for NGS data - Step 1M version
Processes count files with 1M incremental records and performs 
comprehensive strand bias analysis for each increment.
"""

import sys
import os
from typing import List, Tuple

# Add the script directory to path to import from check_strand.py
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

# Import functions from check_strand.py
from check_strand import (
    analyze_strand_bias,
    StrandStats
)
import math


def read_incremental_counts_file(filepath: str) -> List[Tuple[int, int, str]]:
    """
    Read incremental count file - process all lines in the file
    
    Data format (output from count_sam_1M_increase.sh):
    1000000 3117 37696 959187 0 0 1M /path/to/file.fq.gz
    2000000 6234 75392 1918374 0 0 2M /path/to/file.fq.gz
    ...

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
                raise ValueError(f"File format error on line {line_num+1}, need at least 7 columns: {filepath}")

            fwd = int(parts[1])
            rev = int(parts[2])
            million_label = str(parts[6])  # e.g., "1M", "2M", etc.
            
            # Only use million label as the name (no file path)
            name = million_label
                
            results.append((fwd, rev, name))
            
    return results


def format_stats_table_step1M(stats_list: List[StrandStats], sep: str = "\t") -> str:
    """
    Format statistical results as table with ReadsCounts as first column

    Args:
        stats_list: List of StrandStats objects
        sep: Separator

    Returns:
        Formatted table string
    """
    # Table header - use ReadsCounts instead of File
    headers = [
        "ReadsCounts",
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


def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("Usage: python check_strand_step1M.py <file.counts.txt> [output.tsv]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) >= 3 else None
    
    # Read and process counts file
    stats_list = []
    try:
        file_data = read_incremental_counts_file(input_file)
        for fwd, rev, name in file_data:
            stats = analyze_strand_bias(fwd, rev, name)
            stats_list.append(stats)
    except FileNotFoundError:
        print(f"Error: File not found {input_file}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Output results with ReadsCounts as first column
    my_str = format_stats_table_step1M(stats_list)
    
    if output_file:
        with open(output_file, "w") as f:
            f.write(my_str)
    else:
        print(my_str)


if __name__ == "__main__":
    main()
