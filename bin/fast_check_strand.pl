#!/usr/bin/env perl
# Strand bias analysis tool for NGS data
# Processes count files and performs comprehensive strand bias analysis

use strict;
use warnings;
use POSIX qw(sqrt);

# Complementary error function approximation
# Using Horner form of approximation from Abramowitz and Stegun
sub erfc {
    my ($x) = @_;

    # For negative values, use erfc(-x) = 2 - erfc(x)
    my $neg = 0;
    if ($x < 0) {
        $neg = 1;
        $x = -$x;
    }

    # Constants for approximation (Abramowitz & Stegun 7.1.26)
    my $a1 =  0.254829592;
    my $a2 = -0.284496736;
    my $a3 =  1.421413741;
    my $a4 = -1.453152027;
    my $a5 =  1.061405429;
    my $p  =  0.3275911;

    my $t = 1.0 / (1.0 + $p * $x);
    # erfc(x) = t * (a1 + t*(a2 + t*(a3 + t*(a4 + t*a5)))) * exp(-x^2)
    my $erfc_val = $t * ($a1 + $t * ($a2 + $t * ($a3 + $t * ($a4 + $t * $a5)))) * exp(-$x * $x);

    if ($neg) {
        return 2.0 - $erfc_val;
    }
    return $erfc_val;
}

# Calculate proportions of forward and reverse strands
sub compute_proportions {
    my ($fwd, $rev) = @_;
    my $total = $fwd + $rev;

    if ($total == 0) {
        return (0.0, 0.0);
    }

    my $fwd_ratio = $fwd / $total;
    my $rev_ratio = $rev / $total;

    return ($fwd_ratio, $rev_ratio);
}

# Calculate signed symmetric relative difference
# Formula: (fwd - rev) / ((fwd + rev) / 2)
# Range: -2 (reverse only) to +2 (forward only)
sub compute_relative_difference {
    my ($fwd, $rev) = @_;
    my $total = $fwd + $rev;

    if ($total == 0) {
        return "nan";
    }

    my $mean = $total / 2.0;
    return ($fwd - $rev) / $mean;
}

# Calculate chi-square test chi-square value and P-value
# Null hypothesis: Forward and reverse strand distribution is 50:50
# Degrees of freedom: df = 1
sub compute_chi_test {
    my ($fwd, $rev) = @_;
    my $total = $fwd + $rev;

    if ($total == 0) {
        return ("nan", "nan");
    }

    my $expected = $total / 2.0;

    # Chi-square calculation
    my $chi2 = (($fwd - $expected) ** 2 / $expected) + (($rev - $expected) ** 2 / $expected);

    # P-value calculation (chi-square distribution with df=1)
    my $p_value = erfc(sqrt($chi2 / 2.0));

    return ($chi2, $p_value);
}

# Determine strandedness based on total count and signed relative difference
sub determine_strandedness {
    my ($total, $relative_diff) = @_;

    if ($total <= 40) {
        return 'insufficient-data';
    }

    if (abs($relative_diff) <= 0.6) {
        return 'fr-unstranded';
    }

    if ($relative_diff > 0) {
        return 'fr-secondstrand';
    } else {
        return 'fr-firststrand';
    }
}

# Determine if more precise analysis is needed
sub determine_need_precise {
    my ($total, $relative_diff) = @_;

    if ($total <= 80) {
        return 'T';
    }

    my $abs_diff = abs($relative_diff);
    if ($abs_diff > 0.2 && $abs_diff < 0.8) {
        return 'T';
    }

    return 'F';
}

# Comprehensive analysis of forward/reverse strand preference
sub analyze_strand_bias {
    my ($fwd, $rev, $name) = @_;
    my $total = $fwd + $rev;

    # Calculate statistics
    my ($fwd_ratio, $rev_ratio) = compute_proportions($fwd, $rev);
    my $relative_diff = compute_relative_difference($fwd, $rev);
    my ($chi2, $p_value) = compute_chi_test($fwd, $rev);

    # Determine strandedness using signed relative difference
    my $strandedness = determine_strandedness($total, $relative_diff);
    my $need_precise = determine_need_precise($total, $relative_diff);

    return {
        filename => $name,
        strandedness => $strandedness,
        need_precise => $need_precise,
        fwd => $fwd,
        rev => $rev,
        fwd_ratio => $fwd_ratio,
        rev_ratio => $rev_ratio,
        relative_diff => $relative_diff,
        chi2 => $chi2,
        p_value => $p_value
    };
}

# Read count file - process all lines in the file
# Data format:
# total fwd rev unmapped sec supp low_mapq filename
# 4000000 3117 37696 3959187 0 0 100 /home/user/sample_1.fq.gz
sub read_counts_file {
    my ($filepath) = @_;
    my @results;

    open(my $fh, '<', $filepath) or die "Error: File not found $filepath\n";

    my $line_num = 0;
    while (my $line = <$fh>) {
        $line_num++;
        chomp($line);
        next if $line eq '';  # Skip empty lines

        my @parts = split(/\s+/, $line);
        if (scalar(@parts) < 8) {
            die "File format error on line $line_num, need at least 8 columns: $filepath\n";
        }

        my $fwd = int($parts[1]);
        my $rev = int($parts[2]);
        my $name = $parts[7];
        push @results, [$fwd, $rev, $name];
    }

    close($fh);
    return @results;
}

# Format statistical results as table
sub format_stats_table {
    my ($stats_list_ref, $sep) = @_;
    $sep //= "\t";

    my @headers = (
        "File",
        "Strandedness",
        "NeedPrecise",
        "Fwd",
        "Rev",
        "Fwd_Ratio",
        "Rev_Ratio",
        "Rel_Diff",
        "Chi2",
        "P_value"
    );

    my @lines;
    push @lines, join($sep, @headers);

    for my $s (@$stats_list_ref) {
        my @row = (
            $s->{filename},
            $s->{strandedness},
            $s->{need_precise},
            $s->{fwd},
            $s->{rev},
            sprintf("%.6f", $s->{fwd_ratio}),
            sprintf("%.6f", $s->{rev_ratio}),
            sprintf("%.6f", $s->{relative_diff}),
            sprintf("%.6f", $s->{chi2}),
            sprintf("%.6e", $s->{p_value})
        );
        push @lines, join($sep, @row);
    }

    return join("\n", @lines);
}

# Process input file list
sub run_input_file_lists {
    my @file_list = @_;
    my @stats_list;

    for my $filepath (@file_list) {
        my @file_data = read_counts_file($filepath);

        for my $data (@file_data) {
            my ($fwd, $rev, $name) = @$data;
            my $stats = analyze_strand_bias($fwd, $rev, $name);
            push @stats_list, $stats;
        }
    }

    return @stats_list;
}

# Main function
sub main {
    if (scalar(@ARGV) < 1) {
        print "Usage: perl fast_check_strand.pl <file.counts.txt> [output.tsv]\n";
        exit 0;
    }

    my $input_file = $ARGV[0];
    my @stats_list = run_input_file_lists($input_file);
    my $my_str = format_stats_table(\@stats_list);

    if (scalar(@ARGV) >= 2) {
        my $output_file = $ARGV[1];
        open(my $fh, '>', $output_file) or die "Cannot open $output_file: $!\n";
        print $fh $my_str;
        close($fh);
    } else {
        print $my_str . "\n";
    }
}

main();
