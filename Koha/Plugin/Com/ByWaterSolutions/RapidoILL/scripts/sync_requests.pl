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

use DDP;
use Getopt::Long;
use Text::Table;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;
use RapidoILL::CircActions;

use Koha::DateUtils qw(dt_from_string);
use Koha::Script    qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $pod;
my $end_time;
my $start_time;
my $list_pods;
my $help;

my $result = GetOptions(
    'pod=s'        => \$pod,
    'end_time=s'   => \$end_time,
    'start_time=s' => \$start_time,
    'list_pods'    => \$list_pods,
    'help|h'       => \$help,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
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
    --list_pods           Print configured pods and exit.

    --help|-h             Print this information and exit.

--start_time will default to the stored last sync time if not passed. If this is not
defined, it will fallback to 1742713250.

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
}

my @rows;

$start_time //= $plugin->retrieve_data('last_circulation_sync_time');
$start_time //= 1742713250;

my $now = dt_from_string();

foreach my $pod_code ( @{$pods} ) {

    $plugin->sync_circ_requests(
        {
            pod => $pod_code,
            ( $start_time ? ( startTime => $start_time ) : () ),
            ( $end_time   ? ( endTime   => $end_time )   : () ),
        }
    );
}

$plugin->store_data( { last_circulation_sync_time => $now->epoch() } );

1;
