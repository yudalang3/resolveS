#!/usr/bin/env perl
# A script to count rRNA reference sequences from paired-end SAM file
# Progressive strand detection: check top 3, then 5, then 7, then 8 rRNA sequences
# 渐进式判断：前3一致->前5有4个一致->前7有6个一致->前8对半开则fail
#
# === ADAPTIVE MAPQ VERSION ===
# 自动调整 MAPQ 阈值：20 -> 10 -> 3 -> 1
# 当遇到 all-insufficient-fallback 时，降低 MAPQ 重试
# 注意：最低一档为 MAPQ >= 1，确保即使在最宽松档位也排除 MAPQ=0 的纯随机多重比对。
#
# Output format: File Strand_Type MAPQ_Filter Detection_Level Overall_fallback_Fwd Overall_fallback_Rev Overall_fallback_Fwd_Ratio Overall_fallback_Rev_Ratio Overall_fallback_Rel_Diff
#
# =============================================================================
# DETECTION_LEVEL - All Possible Values:
# =============================================================================
#
# --- Success (progressive detection passed, NO fallback) ---
#   3of3   : Level 1 passed - top 3 rRNA sequences all agree on same valid type
#   4of5   : Level 2 passed - 4 of top 5 rRNA sequences agree on same valid type
#   6of7   : Level 3 passed - 6 of top 7 rRNA sequences agree on same valid type
#   7of8   : Level 4 passed - 7 of top 8 rRNA sequences agree
#   (Note: 8of8 is impossible - would have passed at Level 1 as 3of3)
#
# --- Failure (progressive detection failed, Rel_Diff FALLBACK used) ---
# (These all have '-fallback' suffix appended after fallback processing)
#
#   only-0-rRNAs-fallback : 0 rRNA sequences available
#   only-1-rRNAs-fallback : 1 rRNA sequence available
#   only-2-rRNAs-fallback : 2 rRNA sequences available (need 3 for Level 1)
#   only-3-rRNAs-fallback : 3 rRNA seqs but Level 1 failed, need 5 for Level 2
#   only-4-rRNAs-fallback : 4 rRNA seqs but Level 1 failed, need 5 for Level 2
#   only-5-rRNAs-fallback : 5 rRNA seqs but Level 2 failed, need 7 for Level 3
#   only-6-rRNAs-fallback : 6 rRNA seqs but Level 2 failed, need 7 for Level 3
#   only-7-rRNAs-fallback : 7 rRNA seqs but Level 3 failed, need 8 for Level 4
#   4of8-split-fallback    : Level 4 reached, 4:4 split between two types
#   multi-of8-fallback     : Level 4 reached, 3-way+ split, no majority
#   all-insufficient-fallback : All top 8 rRNA seqs have insufficient reads
#
# --- Fallback Logic ---
# When final_type is 'fail-detect', use global Rel_Diff to determine strand:
#   - total <= 0        -> 'insufficient-data'
#   - |Rel_Diff| <= 0.6 -> 'fr-unstranded'
#   - Rel_Diff > 0      -> 'fr-secondstrand'
#   - Rel_Diff < 0      -> 'fr-firststrand'
#
# Note: 'insufficient-data' rRNA sequences (reads <= 40) are EXCLUDED from voting.
#       Only valid types (fr-firststrand, fr-secondstrand, fr-unstranded) count.
#
# =============================================================================
# STRAND_TYPE - All Possible Values:
# =============================================================================
#   fr-firststrand   : Reverse reads dominate (rel_diff < -0.6, binomial p < 0.01), e.g. dUTP
#   fr-secondstrand  : Forward reads dominate (rel_diff > 0.6, binomial p < 0.01), e.g. ligation
#   fr-unstranded    : Balanced or not statistically significant, non-stranded
#   insufficient-data: No valid rRNA sequences (total = 0)
#
# =============================================================================
# ADAPTIVE MAPQ LOGIC:
# =============================================================================
# When detection_level is 'all-insufficient-fallback', try lower MAPQ:
#   MAPQ-20 -> MAPQ-10 -> MAPQ-3 -> MAPQ-1
# MAPQ_filter column shows the final MAPQ threshold used (e.g., MAPQ-20, MAPQ-10, MAPQ-3, MAPQ-1)
#
# =============================================================================

use strict;
use warnings;
use POSIX qw(lgamma);

# --- MAPQ thresholds to try in order ---
# Lowest tier is 1 (not 0) so that MAPQ=0 pure multi-mappers are always excluded,
# even in the most permissive fallback used for sparse data.
my @MAPQ_LEVELS = (20, 10, 3, 1);
use constant RELATIVE_DIFF_CUTOFF => 0.6;
use constant BINOMIAL_PVALUE_CUTOFF => 0.01;

# --- Global Configuration ---
our $DEBUG = 0;

# --- Input Handling ---
if (@ARGV < 1) {
    die "Usage: $0 <input_sam_file> [output_file] [index_str] [debug=0]\n";
}

my $input_file = $ARGV[0];
my $output_file = $ARGV[1] // ($input_file =~ s/\.sam$/.counts.txt/r);
my $index_str = $ARGV[2] // "";
$DEBUG = $ARGV[3] // 0;

die "Error: Input file '$input_file' not found!\n" unless -f $input_file;

# --- Debug helper ---
sub debug_print {
    print STDERR @_ if $DEBUG;
}

sub binomial_two_tailed_pvalue {
    my ($successes, $trials) = @_;
    return 1 if $trials <= 0;

    my $lower_tail_count = $successes < ($trials - $successes)
        ? $successes
        : ($trials - $successes);
    my $log_probability = lgamma($trials + 1)
        - lgamma($lower_tail_count + 1)
        - lgamma($trials - $lower_tail_count + 1)
        - $trials * log(2);

    my $term = exp($log_probability);
    my $tail_probability = $term;

    for (my $i = $lower_tail_count; $i > 0; $i--) {
        $term *= $i / ($trials - $i + 1);
        last if $term == 0;
        $tail_probability += $term;
        last if $term < $tail_probability * 1e-15;
    }

    my $pvalue = 2 * $tail_probability;
    return $pvalue > 1 ? 1 : $pvalue;
}

# === Core detection logic (wrapped in sub for multiple calls) ===
sub run_detection {
    my ($mapq_threshold) = @_;

    debug_print "\n" . "=" x 60 . "\n";
    debug_print "[ADAPTIVE] Trying MAPQ_THRESHOLD = $mapq_threshold\n";
    debug_print "=" x 60 . "\n";

    # --- Data structures (reset each run) ---
    my %chrom_fwd;
    my %chrom_rev;
    my %chrom_status;

    open my $fh, '<', $input_file or die "Cannot open $input_file: $!\n";

    while (<$fh>) {
        next if /^@/;
        chomp;
        my @fields = split /\t/;
        my $flag = $fields[1];
        my $chrom = $fields[2];
        my $mapq = $fields[4];

        next unless ($flag & 0x1);
        next unless ($flag & 0x40);

        if (($flag & 0x4) || ($flag & 0x8)) {
            $chrom_status{$chrom} //= "unmapped";
            next;
        }
        if ($flag & 0x100) {
            $chrom_status{$chrom} //= "sec";
            next;
        }
        if ($flag & 0x800) {
            $chrom_status{$chrom} //= "supp";
            next;
        }
        if ($mapq < $mapq_threshold) {
            $chrom_status{$chrom} //= "not_proper";
            next;
        }
        if (!($flag & 0x2)) {
            $chrom_status{$chrom} //= "not_proper";
            next;
        }

        if ($flag & 0x10) {
            $chrom_rev{$chrom}++;
        } else {
            $chrom_fwd{$chrom}++;
        }
    }
    close $fh;

    # --- Get valid rRNA sequences ---
    my %valid_chroms;
    $valid_chroms{$_} = 1 for keys %chrom_fwd;
    $valid_chroms{$_} = 1 for keys %chrom_rev;

    my @sorted_chroms = sort {
        my $ta = ($chrom_fwd{$a} // 0) + ($chrom_rev{$a} // 0);
        my $tb = ($chrom_fwd{$b} // 0) + ($chrom_rev{$b} // 0);
        $tb <=> $ta;
    } keys %valid_chroms;

    my $total_chroms = scalar(@sorted_chroms);

    # --- Helper: get strand type for an rRNA sequence ---
    my $get_strand_type = sub {
        my ($f, $r) = @_;
        my $total = $f + $r;
        return 'insufficient-data' if $total < 18;
        my $mean = $total / 2.0;
        my $relative_diff = $mean > 0 ? ($f - $r) / $mean : 0;
        return 'fr-unstranded' if abs($relative_diff) <= RELATIVE_DIFF_CUTOFF;
        return 'fr-unstranded' if binomial_two_tailed_pvalue($f, $total) >= BINOMIAL_PVALUE_CUTOFF;
        return $relative_diff > 0 ? 'fr-secondstrand' : 'fr-firststrand';
    };

    # --- Helper: count strand types ---
    my $count_strand_types = sub {
        my ($n) = @_;
        my %counts;
        my $insuff_count = 0;

        for (my $i = 0; $i < $n && $i < $total_chroms; $i++) {
            my $chrom = $sorted_chroms[$i];
            my $f = $chrom_fwd{$chrom} // 0;
            my $r = $chrom_rev{$chrom} // 0;
            my $type = $get_strand_type->($f, $r);

            if ($type eq 'insufficient-data') {
                $insuff_count++;
            } else {
                $counts{$type}++;
            }
        }
        return (\%counts, $insuff_count);
    };

    # --- Helper: get majority type ---
    my $get_majority_type = sub {
        my ($counts_ref, $threshold) = @_;
        for my $type (keys %$counts_ref) {
            return $type if $counts_ref->{$type} >= $threshold;
        }
        return undef;
    };

    # --- Progressive detection ---
    my $final_type = 'fail-detect';
    my $detection_level = '';

    if ($total_chroms < 3) {
        $final_type = 'fail-detect';
        $detection_level = 'only-' . $total_chroms . '-rRNAs';
    } else {
        # Level 1: 3/3
        my ($counts, $insuff) = $count_strand_types->(3);
        my $majority = $get_majority_type->($counts, 3);

        if (defined $majority) {
            $final_type = $majority;
            $detection_level = '3of3';
        } elsif ($total_chroms < 5) {
            $final_type = 'fail-detect';
            $detection_level = 'only-' . $total_chroms . '-rRNAs';
        } else {
            # Level 2: 4/5
            ($counts, $insuff) = $count_strand_types->(5);
            $majority = $get_majority_type->($counts, 4);

            if (defined $majority) {
                $final_type = $majority;
                $detection_level = '4of5';
            } elsif ($total_chroms < 7) {
                $final_type = 'fail-detect';
                $detection_level = 'only-' . $total_chroms . '-rRNAs';
            } else {
                # Level 3: 6/7
                ($counts, $insuff) = $count_strand_types->(7);
                $majority = $get_majority_type->($counts, 6);

                if (defined $majority) {
                    $final_type = $majority;
                    $detection_level = '6of7';
                } elsif ($total_chroms < 8) {
                    $final_type = 'fail-detect';
                    $detection_level = 'only-' . $total_chroms . '-rRNAs';
                } else {
                    # Level 4: 7/8
                    ($counts, $insuff) = $count_strand_types->(8);

                    my $max_count = 0;
                    my $max_type = '';
                    for my $type (keys %$counts) {
                        if ($counts->{$type} > $max_count) {
                            $max_count = $counts->{$type};
                            $max_type = $type;
                        }
                    }

                    if ($max_count >= 7) {
                        $final_type = $max_type;
                        $detection_level = $max_count . 'of8';
                    } elsif ($max_count == 4) {
                        $final_type = 'fail-detect';
                        $detection_level = '4of8-split';
                    } elsif ($max_count > 0) {
                        $final_type = 'fail-detect';
                        $detection_level = 'multi-of8';
                    } else {
                        $final_type = 'fail-detect';
                        $detection_level = 'all-insufficient';
                    }
                }
            }
        }
    }

    # --- Count by major strand ---
    my $fwd = 0;
    my $rev = 0;
    my $tie = 0;

    my @debug_rows;
    my $chrom_width = length('rRNA_seq');
    my $fwd_width = length('fwd');
    my $rev_width = length('rev');
    my $total_width = length('total');
    my $major_width = length('major');
    for my $chrom (@sorted_chroms) {
        my $f = $chrom_fwd{$chrom} // 0;
        my $r = $chrom_rev{$chrom} // 0;
        my $t = $f + $r;
        my $major;
        my $strand_type = $get_strand_type->($f, $r);

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

        push @debug_rows, [$chrom, $f, $r, $t, $major, $strand_type];
        $chrom_width = length($chrom) if length($chrom) > $chrom_width;
        $fwd_width = length($f) if length($f) > $fwd_width;
        $rev_width = length($r) if length($r) > $rev_width;
        $total_width = length($t) if length($t) > $total_width;
        $major_width = length($major) if length($major) > $major_width;
    }

    # --- Debug: Per-rRNA-sequence distribution ---
    debug_print "\n--- Per-rRNA-sequence distribution (MAPQ >= $mapq_threshold) ---\n";
    debug_print "Total rRNA sequences with valid alignments: $total_chroms\n";
    debug_print sprintf(
        "%-${chrom_width}s  %${fwd_width}s  %${rev_width}s  %${total_width}s  %-${major_width}s  %s\n",
        'rRNA_seq', 'fwd', 'rev', 'total', 'major', 'strand_type'
    );
    for my $row (@debug_rows) {
        debug_print sprintf(
            "%-${chrom_width}s  %${fwd_width}d  %${rev_width}d  %${total_width}d  %-${major_width}s  %s\n",
            @$row
        );
    }

    my $total = $fwd + $rev;
    debug_print "\n--- Summary ---\n";
    debug_print "Total rRNA sequences (excluding tie): $total\n";
    debug_print "fwd: $fwd | rev: $rev | tie: $tie (filtered)\n";
    debug_print "=" x 60 . "\n";
    my $fwd_Ratio = $total > 0 ? $fwd / $total : 0;
    my $rev_Ratio = $total > 0 ? $rev / $total : 0;
    my $mean = $total / 2.0;
    my $Rel_Diff = $mean > 0 ? ($fwd - $rev) / $mean : 0;

    # --- Fallback ---
    if ($final_type eq 'fail-detect') {
        if ($total <= 0) {
            $final_type = 'insufficient-data';
        } elsif (abs($Rel_Diff) <= 0.6) {
            $final_type = 'fr-unstranded';
        } elsif ($Rel_Diff > 0) {
            $final_type = 'fr-secondstrand';
        } else {
            $final_type = 'fr-firststrand';
        }
        $detection_level = $detection_level . '-fallback';
    }

    debug_print "[ADAPTIVE] Result: detection_level='$detection_level', strand_type='$final_type'\n";

    return {
        fwd => $fwd,
        rev => $rev,
        fwd_Ratio => $fwd_Ratio,
        rev_Ratio => $rev_Ratio,
        Rel_Diff => $Rel_Diff,
        final_type => $final_type,
        detection_level => $detection_level,
    };
}

# === Main: Adaptive MAPQ loop ===
my $result;
my $final_mapq;

for my $mapq (@MAPQ_LEVELS) {
    $result = run_detection($mapq);
    $final_mapq = $mapq;

    if ($result->{detection_level} ne 'all-insufficient-fallback') {
        debug_print "\n[ADAPTIVE] Success at MAPQ=$mapq\n";
        last;
    }
    debug_print "[ADAPTIVE] Got all-insufficient-fallback, trying lower MAPQ...\n";
}

debug_print "\n[ADAPTIVE] Final MAPQ used: $final_mapq\n";
debug_print "[ADAPTIVE] Final result: $result->{final_type} ($result->{detection_level})\n";

# --- Output ---
# Format: File Strand_Type MAPQ_Filter Detection_Level Overall_fallback_Fwd Overall_fallback_Rev Overall_fallback_Fwd_Ratio Overall_fallback_Rev_Ratio Overall_fallback_Rel_Diff
my $mapq_filter = "MAPQ-$final_mapq";
my $output_line = "$index_str\t$result->{final_type}\t$mapq_filter\t$result->{detection_level}\t$result->{fwd}\t$result->{rev}\t$result->{fwd_Ratio}\t$result->{rev_Ratio}\t$result->{Rel_Diff}\n";

if ($output_file eq "-") {
    # Output to stdout
    print $output_line;
} else {
    open my $out, '>>', $output_file or die "Cannot open $output_file: $!\n";
    print $out $output_line;
    close $out;
}
