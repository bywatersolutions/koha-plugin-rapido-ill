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

use Koha::Script qw(-cron);

binmode( STDOUT, ':encoding(utf8)' );

# actions
my $list_pods = 0;
my $help      = 0;
my $sync      = 0;
my $add       = 0;
my $delete    = 0;
my $update    = 0;

# params
my $pod;
my $local_server;
my $agency_id;
my $description;
my $passcode          = 0;
my $visiting_checkout = 0;
my $keep_patron       = 0;

my $result = GetOptions(
    'pod=s'             => \$pod,
    'sync'              => \$sync,
    'add'               => \add,
    'delete'            => \$delete,
    'update'            => \$update,
    'list_pods'         => \$list_pods,
    'local_server'      => \$local_server,
    'agency_id=s'       => \$agency_id,
    'description'       => \$description,
    'passcode'          => \$passcode,
    'visiting_checkout' => \$visiting_checkout,
    'keep_patron'       => \$keep_patron,
    'help|h'            => \$help,
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

    --pod <pod_code>        Only sync the specified pod circulation requests

 Actions:

    --list_pods             Print configured pods and exit.
    --sync                  Sync visiting patron pod agencies.
    --add                   Add agency.
    --delete                Delete agency.
    --update                Update existing agency.
    --help|-h.              Print this information and exit.

 Parameters for 'add' and 'update':

    --local_server <code>   Local server code. [mandatory]
    --agency_id    <code>   Agency ID. [mandatory]
    --description  <desc>   Description. [mandatory]
    --passcode              If if requires a passcode. [OPTIONAL]
    --visiting_checkout     If it allows visiting patron checkouts. [OPTIONAL]
    --keep_patron           When deleting, keep the patron. [OPTIONAL]

_USAGE_
}

if ( $list_pods + $help + $sync + $add + $delete + $update == 0 ) {
    print_usage();
    print STDERR "No action passed! \n";
    exit 1;
}

if ( $list_pods + $help + $sync + $add + $delete + $update > 1 ) {
    print_usage();
    print STDERR "Only one action can be passed.\n";
    exit 1;
}

$list_pods + $help + $sync + $add + $delete + $update my $plugin =
    Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

my $pods = $plugin->pods;

if ($list_pods) {

    foreach my $i ( @{$pods} ) {
        print STDOUT "$i\n";
    }
    exit 0;

} elsif ($sync) {

    $pods = [ grep { $_ eq $pod } @{$pods} ]
        if $pod;

    unless ( scalar @{$pods} > 0 ) {
        print_usage();
        print STDERR "No pods to sync.\n";
    }

    my @rows;

    foreach my $pod_code ( @{$pods} ) {
        $plugin->sync_agencies($pod_code);
    }

} elsif ($delete) {

    # unless ( $pod && $agency_id ) {
    #     print_usage();
    #     print STDERR "pod and agency_id are mandatory\n";
    #     exit 1;
    # }

    # my $patron_id = $plugin->get_patron_id_from_agency( { agency_id => $agency_id, pod => $pod } );

    # unless ($patron_id) {
    #     print STDERR "agency_id not found on the DB\n";
    #     exit 0;
    # }

    print STDERR "Not implemented\n";

} elsif ($add) {

    unless ( $pod && $agency_id ) {
        print_usage();
        print STDERR "pod and agency_id are mandatory\n";
        exit 1;
    }

    my $patron_id = $plugin->get_patron_id_from_agency( { agency_id => $agency_id, pod => $pod } );

    if ($patron_id) {
        print STDERR "agency_id already on the DB\n";
        exit 0;
    }

    my $patron = $plugin->generate_patron_for_agency(
        {
            pod                       => $pod,
            local_server              => $local_server,
            description               => $description,
            agency_id                 => $agency_id,
            requires_passcode         => $passcode,
            visiting_checkout_allowed => $visiting_checkout,
        }
    );

    print STDOUT printf( "Agency '%s' loaded (patron_id=%s)\n", $agency_id, $patron->id );
    exit 0;

} elsif ($update) {

    unless ( $pod && $agency_id ) {
        print_usage();
        print STDERR "pod and agency_id are mandatory\n";
        exit 1;
    }

    my $patron_id = $plugin->get_patron_id_from_agency( { agency_id => $agency_id, pod => $pod } );

    unless ($patron_id) {
        print STDERR "agency_id not found on the DB\n";
        exit 0;
    }

    my $patron = $plugin->update_patron_for_agency(
        {
            pod                       => $pod,
            local_server              => $local_server,
            description               => $description,
            agency_id                 => $agency_id,
            requires_passcode         => $passcode,
            visiting_checkout_allowed => $visiting_checkout,
        }
    );

    print STDOUT printf( "Agency '$agency_id' updated\n", );
    exit 0;
}

1;
