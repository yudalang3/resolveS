#!/usr/bin/env perl
# A script to count chromosomes from paired-end SAM file
# Each chromosome counts as ONE, strand determined by MAJOR (majority) strand
# Output format: total fwd rev unmapped sec supp not_proper

use strict;
use warnings;

# --- Input Handling ---
if (@ARGV < 1) {
    die "Usage: $0 <input_sam_file> [output_file] [index_str]\n";
}

my $input_file = $ARGV[0];
my $output_file = $ARGV[1] // ($input_file =~ s/\.sam$/.counts.txt/r);
my $index_str = $ARGV[2] // "";

die "Error: Input file '$input_file' not found!\n" unless -f $input_file;

# --- Data structures ---
my %chrom_fwd;     # chrom => count of fwd alignments
my %chrom_rev;     # chrom => count of rev alignments
my %chrom_status;  # chrom => status for invalid-only chromosomes

open my $fh, '<', $input_file or die "Cannot open $input_file: $!\n";

while (<$fh>) {
    next if /^@/;  # skip header

    chomp;
    my @fields = split /\t/;
    my $flag = $fields[1];
    my $chrom = $fields[2];
    my $mapq = $fields[4];

    # Must be paired (bit 0x1)
    next unless ($flag & 0x1);

    # Only process R1 (first in pair, bit 0x40)
    next unless ($flag & 0x40);

    # Check if unmapped (bit 0x4) or mate unmapped (bit 0x8)
    if (($flag & 0x4) || ($flag & 0x8)) {
        $chrom_status{$chrom} //= "unmapped";
        next;
    }

    # Check if secondary (bit 0x100)
    if ($flag & 0x100) {
        $chrom_status{$chrom} //= "sec";
        next;
    }

    # Check if supplementary (bit 0x800)
    if ($flag & 0x800) {
        $chrom_status{$chrom} //= "supp";
        next;
    }

    # Check MAPQ >= 4
    if ($mapq < 4) {
        $chrom_status{$chrom} //= "not_proper";
        next;
    }

    # Check if proper pair (bit 0x2)
    if (!($flag & 0x2)) {
        $chrom_status{$chrom} //= "not_proper";
        next;
    }

    # Valid alignment - count strand (bit 0x10 = reverse)
    if ($flag & 0x10) {
        $chrom_rev{$chrom}++;
    } else {
        $chrom_fwd{$chrom}++;
    }
}

close $fh;

# --- Count results ---
my $fwd = 0;
my $rev = 0;
my $unmapped = 0;
my $sec = 0;
my $supp = 0;
my $not_proper = 0;

# Get all chromosomes with valid alignments
my %valid_chroms;
$valid_chroms{$_} = 1 for keys %chrom_fwd;
$valid_chroms{$_} = 1 for keys %chrom_rev;

# --- Debug output to STDERR ---
print STDERR "=== DEBUG: count_sam_per_chrom_major (majority strand) ===\n";
print STDERR "Total chromosomes with valid alignments: " . scalar(keys %valid_chroms) . "\n";
print STDERR "\n--- Per-chromosome distribution ---\n";
print STDERR "chrom\tfwd\trev\ttotal\tmajor\n";

# Determine major strand for each valid chromosome
# Sort by total count descending
my @sorted_chroms = sort {
    my $ta = ($chrom_fwd{$a} // 0) + ($chrom_rev{$a} // 0);
    my $tb = ($chrom_fwd{$b} // 0) + ($chrom_rev{$b} // 0);
    $tb <=> $ta;  # descending
} keys %valid_chroms;

my $tie = 0;  # count of chromosomes with equal fwd/rev

for my $chrom (@sorted_chroms) {
    my $f = $chrom_fwd{$chrom} // 0;
    my $r = $chrom_rev{$chrom} // 0;
    my $t = $f + $r;
    my $major;

    if ($f > $r) {
        $fwd++;
        $major = "fwd";
    } elsif ($r > $f) {
        $rev++;
        $major = "rev";
    } else {
        $tie++;
        $major = "tie";
    }

    print STDERR "$chrom\t$f\t$r\t$t\t$major\n";
}

# Count chromosomes that only have invalid alignments
# my @invalid_only;
# for my $chrom (keys %chrom_status) {
#     next if exists $valid_chroms{$chrom};  # skip if has valid alignments

#     my $status = $chrom_status{$chrom};
#     $unmapped++   if $status eq "unmapped";
#     $sec++        if $status eq "sec";
#     $supp++       if $status eq "supp";
#     $not_proper++ if $status eq "not_proper";
#     push @invalid_only, [$chrom, $status];
# }

# if (@invalid_only) {
#     print STDERR "\n--- Invalid-only chromosomes ---\n";
#     print STDERR "chrom\tstatus\n";
#     for my $item (sort { $a->[0] cmp $b->[0] } @invalid_only) {
#         print STDERR "$item->[0]\t$item->[1]\n";
#     }
# }

my $total = $fwd + $rev;  # exclude tie

print STDERR "\n--- Summary ---\n";
print STDERR "Total chromosomes (excluding tie): $total\n";
print STDERR "fwd: $fwd | rev: $rev | tie: $tie (filtered)\n";
print STDERR "====================================================\n";

# --- Output ---
open my $out, '>>', $output_file or die "Cannot open $output_file: $!\n";
print $out "$total $fwd $rev $unmapped $sec $supp $not_proper $index_str\n";
close $out;
