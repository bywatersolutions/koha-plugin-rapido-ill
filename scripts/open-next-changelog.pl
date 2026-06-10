#!/usr/bin/env perl

# open-next-changelog.pl <version>
#
# Inserts a fresh ## [Unreleased] section at the top of CHANGELOG.md.
#
# Usage: perl scripts/open-next-changelog.pl v1.8.9

use strict;
use warnings;

my $version = shift or die "Usage: $0 <version>\n";
(my $bare = $version) =~ s/^v//;

open my $fh, '<', 'CHANGELOG.md' or die "Cannot read CHANGELOG.md: $!\n";
my $content = do { local $/; <$fh> };
close $fh;

$content =~ s/(## \[\Q$bare\E\])/## [Unreleased]\n\n$1/m;

open my $out, '>', 'CHANGELOG.md' or die "Cannot write CHANGELOG.md: $!\n";
print $out $content;
close $out;

print "Opened CHANGELOG.md for next development cycle\n";
