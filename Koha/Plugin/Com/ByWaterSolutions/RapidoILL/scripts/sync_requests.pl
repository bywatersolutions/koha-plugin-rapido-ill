#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;
use utf8;

use Getopt::Long;
use Text::Table;
use Try::Tiny;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;
use RapidoILL::CircActions;

use Koha::DateUtils qw(dt_from_string);
use Koha::Script    qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $pod;
my $end_time;
my $start_time;
my $state;
my $list_pods;
my $help;
my $verbose;
my $quiet;
my $circid;

my $result = GetOptions(
    'pod=s'        => \$pod,
    'end_time=s'   => \$end_time,
    'start_time=s' => \$start_time,
    'state=s@'     => \$state,
    'list_pods'    => \$list_pods,
    'verbose|v'    => \$verbose,
    'quiet|q'      => \$quiet,
    'circid=s'     => \$circid,
    'help|h'       => \$help,
);

unless ($result) {
    print_usage();
    die "Invalid command line options";
}

if ($help) {
    print_usage();
    exit 0;
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --pod <pod_code>      Only sync the specified pod circulation requests
    --start_time <epoch>  Start time range (epoch). [OPTIONAL]
    --end_time <epoch>    End time range (epoch) [OPTIONAL]
    --state <state>       Circulation states to sync (can be repeated) [OPTIONAL]
                          Valid states: ACTIVE, COMPLETED, INACTIVE, CREATED, CANCELED
                          Default: ACTIVE COMPLETED CANCELED CREATED
    --circid <circId>     Sync only the specified circulation ID [OPTIONAL]
    --list_pods           Print configured pods and exit.
    --verbose|-v          Show detailed processing messages
    --quiet|-q            Suppress all output except errors
    --help|-h             Print this information and exit.

--start_time will default to the stored last sync time if not passed. If this is not
defined, it will fallback to 1742713250.

Output levels:
  Default: Shows summary and errors only
  --verbose: Shows detailed processing messages
  --quiet: Shows only critical errors

_USAGE_
}

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

my $pods = $plugin->pods;

if ($list_pods) {
    foreach my $i ( @{$pods} ) {
        print STDOUT "$i\n";
    }
    exit 0;
}

$pods = [ grep { $_ eq $pod } @{$pods} ]
    if $pod;

unless ( scalar @{$pods} > 0 ) {
    print_usage();
    print STDERR "No pods to sync.\n";
    exit 1;
}

# Global counters for summary
my $total_processed = 0;
my $total_created   = 0;
my $total_updated   = 0;
my $total_errors    = 0;
my $total_skipped   = 0;

my @rows;

$start_time //= $plugin->retrieve_data('last_circulation_sync_time');
$start_time //= 1742713250;

my $now = dt_from_string();

print "Syncing circulation requests...\n" unless $quiet;

foreach my $pod_code ( @{$pods} ) {
    print "Processing pod: $pod_code\n" if $verbose;

    my $pod_start = time();

    try {
        my $results = $plugin->sync_circ_requests(
            {
                pod => $pod_code,
                ( $start_time ? ( startTime => $start_time ) : () ),
                ( $end_time   ? ( endTime   => $end_time )   : () ),
                ( $state      ? ( state     => $state )      : () ),
                ( $circid     ? ( circId    => $circid )     : () ),
            }
        );

        # Accumulate totals
        $total_processed += $results->{processed};
        $total_created   += $results->{created};
        $total_updated   += $results->{updated};
        $total_skipped   += $results->{skipped};
        $total_errors    += $results->{errors};

        if ($verbose) {
            if ( $results->{processed} > 0 ) {
                print "  Found $results->{processed} circulation requests\n";

                # Show individual processing messages
                foreach my $msg ( @{ $results->{messages} } ) {
                    my $icon = {
                        created => '✓',
                        updated => '✓',
                        skipped => '⚠',
                        error   => '✗',
                        warning => '⚠'
                    }->{ $msg->{type} }
                        || '•';

                    print "    $icon $msg->{circId}: $msg->{message}\n";
                }

                print
                    "  Results: $results->{created} created, $results->{updated} updated, $results->{skipped} skipped, $results->{errors} errors\n";
            } else {
                print "  No circulation requests found\n";
            }
        }

    } catch {
        my $error = $_;
        $total_errors++;

        # Clean up error message
        $error =~ s/DBIx::Class::Storage::DBI::_dbh_execute\(\): DBI Exception: //;
        $error =~ s/ at \/.*? line \d+\.?$//;

        print "✗ Error processing pod $pod_code: $error\n" unless $quiet;
    };

    my $pod_duration = time() - $pod_start;
    print "  Completed pod $pod_code in ${pod_duration}s\n" if $verbose;
}

$plugin->store_data( { last_circulation_sync_time => $now->epoch() } );

# Print summary
unless ($quiet) {
    print "\n" . "=" x 50 . "\n";
    print "SYNC SUMMARY\n";
    print "=" x 50 . "\n";
    print "Processed: $total_processed requests\n";

    if ( $total_created > 0 || $total_updated > 0 || $total_skipped > 0 ) {
        print "Created:   $total_created new ILL requests\n"  if $total_created > 0;
        print "Updated:   $total_updated existing requests\n" if $total_updated > 0;
        print "Skipped:   $total_skipped duplicates\n"        if $total_skipped > 0;
    }

    print "Errors:    $total_errors failures\n" if $total_errors > 0;
    print "Pods:      " . scalar( @{$pods} ) . " (" . join( ", ", @{$pods} ) . ")\n";

    if ( $total_errors > 0 ) {
        print "\n⚠ Completed with $total_errors errors\n";
        exit 1;
    } elsif ( $total_processed == 0 ) {
        print "\n✓ No new requests to process\n";
    } else {
        print "\n✓ Sync completed successfully\n";
    }
}

1;
