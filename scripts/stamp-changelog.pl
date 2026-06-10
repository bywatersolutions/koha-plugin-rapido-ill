#!/usr/bin/env perl

# stamp-changelog.pl <version>
#
# Stamps the ## [Unreleased] section in CHANGELOG.md with the given version
# and today's date.
#
# Usage: perl scripts/stamp-changelog.pl v1.8.9

use strict;
use warnings;
use POSIX qw(strftime);

my $version = shift or die "Usage: $0 <version>\n";
(my $bare = $version) =~ s/^v//;
my $date = strftime('%Y-%m-%d', localtime);

open my $fh, '<', 'CHANGELOG.md' or die "Cannot read CHANGELOG.md: $!\n";
my $content = do { local $/; <$fh> };
close $fh;

$content =~ s/^## \[Unreleased\]/## [$bare] - $date/m
    or die "Could not find '## [Unreleased]' in CHANGELOG.md\n";

open my $out, '>', 'CHANGELOG.md' or die "Cannot write CHANGELOG.md: $!\n";
print $out $content;
close $out;

print "Stamped CHANGELOG.md: [Unreleased] -> [$bare] - $date\n";
