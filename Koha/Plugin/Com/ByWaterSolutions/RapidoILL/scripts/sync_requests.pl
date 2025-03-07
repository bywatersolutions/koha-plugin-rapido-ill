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
use RapidoILL::Circulation::Requests;

use Koha::Script qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

my $verbose;
my $local_server;
my $pod;
my $dry_run = 0;

my $result = GetOptions(
    'dry_run'   => \$dry_run,
    'pod=s'     => \$pod,
    'v|verbose' => \$verbose,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --pod <pod_code>    Only sync the specified pod circulation requests
    --dry_run           Don't make any changes
    -v | --verbose      Verbose output

_USAGE_
}

print STDERR "\n\nIMPORTANT: THIS IS JUST STORING THE DATA, NOT PRODUCTION READY OR TESTABLE\n\n";
sleep 3;

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

my $pods = $plugin->pods;
$pods = [ grep { $_ eq $pod } @{$pods} ]
    if $pod;

unless ( scalar @{$pods} > 0 ) {
    print_usage();
    print STDERR "No pods to sync.\n";
}

my @rows;

foreach my $pod_code ( @{$pods} ) {

    my $client = $plugin->get_client($pod_code);

    # start at epoch, then save
    my $startTime = $plugin->retrieve_data('startTime') // "1700000000";
    my $endTime   = time();

    my $active_requests = $client->circulation_requests(
        {
            startTime => $startTime,
            endTime   => $endTime,
            content   => "verbose",
        }
    );

    foreach my $data ( @{$active_requests} ) {

        $data->{pod} = $pod_code;

        # FIXME: Only modified requests should be recorded
        # FIXME: Actions should be triggered on status change
        my $req = RapidoILL::Circulation::Request->new( $data )->store;

        push @rows, [
            $data->{author},
            $data->{borrowerCode},
            $data->{callNumber},
            $data->{circId},
            $data->{circStatus},
            $data->{dateCreated},
            $data->{dueDateTime},
            $data->{itemAgencyCode},
            $data->{itemBarcode},
            $data->{itemId},
            $data->{lastCircState},
            $data->{lastUpdated},
            $data->{lenderCode},
            $data->{needBefore},
            $data->{patronAgencyCode},
            $data->{patronId},
            $data->{patronName},
            $data->{pickupLocation},
            $data->{puaLocalServerCode},
            $data->{title},
        ];
    }
}

if ( scalar @rows && $verbose ) {
    my $table = Text::Table->new(
        'author',
        'borrowerCode',
        'callNumber',
        'circId',
        'circStatus',
        'dateCreated',
        'dueDateTime',
        'itemAgencyCode',
        'itemBarcode',
        'itemId',
        'lastCircState',
        'lastUpdated',
        'lenderCode',
        'needBefore',
        'patronAgencyCode',
        'patronId',
        'patronName',
        'pickupLocation',
        'puaLocalServerCode',
        'title',
    );
    $table->load(@rows);
    print STDOUT $table;
}

1;
