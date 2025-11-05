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

use Getopt::Long;
use JSON qw(encode_json);
use Try::Tiny;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

use Koha::Script;

binmode( STDOUT, ':encoding(utf8)' );

my $pod;
my $list_pods;
my $end_time;
my $start_time;
my $state;
my $content = 'verbose';
my $circid;
my $help;

my $result = GetOptions(
    'pod=s'        => \$pod,
    'end_time=s'   => \$end_time,
    'start_time=s' => \$start_time,
    'state=s@'     => \$state,
    'content=s'    => \$content,
    'circid=s'     => \$circid,
    'list_pods'    => \$list_pods,
    'help|h|'      => \$help,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

if ($help) {
    print_usage();
    exit 0;
}

if ( !$pod && !$list_pods ) {
    print_usage();
    die "Passing --pod is mandatory.";
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --pod <pod_code>      Only retrieve the specified pod circulation
                          requests [MANDATORY]
    --start_time <epoch>  Start time range (epoch) [OPTIONAL]
    --end_time <epoch>    End time range (epoch) [OPTIONAL]
    --state <state>       Filter by 'state'. Multiple occurrences allowed [OPTIONAL]
                          Valid states: ACTIVE, COMPLETED, INACTIVE, CREATED, CANCELED
    --content <level>     Valid values are 'verbose' and 'concise'
    --circid <circId>     Filter by specific circulation ID [OPTIONAL]
    --list_pods           Print configured pods and exit.
    --state string        A state you want to filter on

    --help|-h             Print this information and exit.

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

if ( !$state ) {
    $state = [ 'ACTIVE', 'COMPLETED', 'CANCELED', 'CREATED' ];
}

unless ( scalar @{$pods} > 0 ) {
    print_usage();
    print STDERR "No usable pods found.\n";
}

my $requests;
try {
    $requests = $plugin->get_client($pod)->circulation_requests(
        {
            ( $start_time ? ( startTime => $start_time ) : ( startTime => "1700000000" ) ),
            ( $end_time   ? ( endTime   => $end_time )   : ( endTime   => time() ) ),
            content => $content,
            state   => $state,
        }
    );
} catch {
    my $error = $_;
    print STDERR "Error retrieving circulation requests: $error\n";

    # If it's a RequestFailed exception, show more details
    if ( ref($error) eq 'RapidoILL::Exception::RequestFailed' ) {
        my $response = $error->response;
        print STDERR "HTTP Status: " . $response->code . " " . $response->message . "\n";
        print STDERR "Response Body: "
            . ( $response->decoded_content || $response->content || 'No response body' ) . "\n";
        print STDERR "Method: " . $error->method . "\n";
        print STDERR "Request URL: " . ( $response->request ? $response->request->uri : 'Unknown' ) . "\n";
    }

    exit 1;
};

# Filter by circId if specified
if ($circid) {
    if ( $requests && ref($requests) eq 'ARRAY' ) {
        $requests = [ grep { $_->{circId} && $_->{circId} eq $circid } @{$requests} ];
    }
}

print STDOUT encode_json($requests);

1;
