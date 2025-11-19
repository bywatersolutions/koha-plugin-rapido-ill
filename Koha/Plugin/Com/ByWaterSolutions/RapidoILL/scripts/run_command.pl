#!/usr/bin/env perl

# Copyright 2025 ByWater Solutions
#
# This file is part of The Rapido ILL plugin.
#
# The Rapido ILL plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The Rapido ILL plugin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Getopt::Long;
use List::MoreUtils qw(none);
use Try::Tiny       qw( catch try );

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $borrowing;
my $command;
my $help;
my $lending;
my $list_commands;
my $pod;
my $request_id;
my $skip_api_req;

my $result = GetOptions(
    'borrowing'     => \$borrowing,
    'command=s'     => \$command,
    'help'          => \$help,
    'lending'       => \$lending,
    'list_commands' => \$list_commands,
    'pod=s'         => \$pod,
    'request_id=s'  => \$request_id,
    'skip_api_req'  => \$skip_api_req,
);

unless ($result) {
    print_usage();
    say "Error parsing command line options";
    exit 1;
}

if ($help) {
    print_usage();
    exit 0;
}

unless ( $request_id || $list_commands ) {
    print_usage();
    say "--request_id or --list_commands is mandatory";
    exit 1;
}

unless ( $command || $list_commands ) {
    print_usage();
    say "--command or --list_commands is mandatory";
    exit 1;
}

unless ( $pod || $list_commands ) {
    print_usage();
    say "--pod is mandatory (unless using --list_commands)";
    exit 1;
}

if ( $lending && $borrowing ) {
    print_usage();
    say "--lending and --borrowing are mutually exclusive";
    exit 1;
} elsif ( !( $lending || $borrowing ) && !$list_commands ) {
    print_usage();
    say "--lending or --borrowing need to be specified";
    exit 1;
}

my @valid_lending = qw(cancel_request final_checkin item_shipped process_renewal_decision);
my @valid_borrowing =
    qw(borrower_cancel borrower_renew final_checkin item_in_transit item_received receive_unshipped return_uncirculated);

if ($list_commands) {
    if ($lending) {
        say "Valid lending site commands: " . join( ', ', @valid_lending );
    } elsif ($borrowing) {
        say "Valid borrowing site commands: " . join( ', ', @valid_borrowing );
    } else {
        say "Lending site commands: " . join( ', ', @valid_lending );
        say "Borrowing site commands: " . join( ', ', @valid_borrowing );
    }
    exit 0;
}

if ($lending) {
    if ( none { $_ eq $command } @valid_lending ) {
        print_usage();
        say "'$command' is an invalid lending command. Valid options are: " . join( ', ', @valid_lending );
        exit 1;
    }
} else {
    if ( none { $_ eq $command } @valid_borrowing ) {
        print_usage();
        say "'$command' is an invalid borrowing command. Valid options are: " . join( ', ', @valid_borrowing );
        exit 1;
    }
}

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

sub print_usage {
    print <<_USAGE_;

This script takes care of triggering a Rapido ILL command.

Options:

    --request_id <id>      An ILL request ID

    --pod <pod>            The Rapido pod to use for the command

    --lending              A lending site command will be executed
    --borrowing            A borrowing site command will be executed

    --command <command>    The command to be run
    --list_commands        Prints a list of the possible commands

    --skip_api_req         Skip actual API interaction (useful for cleanup) [optional]

    --help                 This help

Examples:

    # List all available commands
    ./run_command.pl --list_commands

    # Cancel a borrowing request
    ./run_command.pl --borrowing --pod dev03-na --request_id 123 --command borrower_cancel

    # Ship an item (lending side)
    ./run_command.pl --lending --pod dev03-na --request_id 456 --command item_shipped

    # Process renewal decision (lending side)
    ./run_command.pl --lending --pod dev03-na --request_id 789 --command process_renewal_decision

_USAGE_
}

my $actions = ($lending) ? $plugin->get_lender_actions($pod) : $plugin->get_borrower_actions($pod);

my $req = Koha::ILL::Requests->find($request_id);

unless ($req) {
    say "ILL request with ID '$request_id' not found";
    exit 1;
}

try {
    my $client_options;
    $client_options = { skip_api_request => $skip_api_req } if $skip_api_req;
    $actions->$command( $req, { client_options => $client_options } );
    say "Command '$command' executed successfully for request $request_id";
} catch {
    if ( ref($_) eq 'RapidoILL::Exception::RequestFailed' ) {
        warn sprintf(
            "[rapido] [ill_req=%s] %s request error: %s",
            $req->id,
            $_->method,
            $_->response->decoded_content // $_->response->status_line // 'Unknown error'
        );
    } else {
        warn sprintf(
            "[rapido] [ill_req=%s] unhandled error: %s",
            $req->id,
            $_
        );
    }

    exit 1;
};

1;
