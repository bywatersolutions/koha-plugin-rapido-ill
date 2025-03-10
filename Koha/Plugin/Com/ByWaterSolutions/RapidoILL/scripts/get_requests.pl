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

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

use Koha::Script;

binmode( STDOUT, ':encoding(utf8)' );

my $pod;
my $end_time;
my $start_time;
my $state;
my $content = 'verbose';

my $result = GetOptions(
    'pod=s'        => \$pod,
    'end_time=s'   => \$end_time,
    'start_time=s' => \$start_time,
    'state=s@'     => \$state,
    'content=s'    => \$content,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

if ( !$pod ) {
    print_usage();
    die "Passign --pod is mandatory.";
}

if ( !$state ) {
    $state = [ 'ACTIVE', 'COMPLETED', 'CANCELED', 'CREATED' ];
}

sub print_usage {
    print <<_USAGE_;

Valid options are:

    --pod <pod_code>      Only retrieve the specified pod circulation
                          requests [MANDATORY]
    --start_time <epoch>  Start time range (epoch) [OPTIONAL]
    --end_time <epoch>    End time range (epoch) [OPTIONAL]
    --state <state>       Filter by 'state'. Multiple occurences allowed [OPTIONAL]

_USAGE_
}

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

my $pods = $plugin->pods;
$pods = [ grep { $_ eq $pod } @{$pods} ]
    if $pod;

unless ( scalar @{$pods} > 0 ) {
    print_usage();
    print STDERR "No usable pods passed.\n";
}

print STDOUT encode_json(
    $plugin->get_client($pod)->circulation_requests(
        {
            ( $start_time ? ( startTime => $start_time ) : ( startTime => "1700000000" ) ),
            ( $end_time   ? ( endTime   => $end_time )   : ( endTime   => time() ) ),
            content => $content,
            state   => $state,
        }
    )
);

1;
