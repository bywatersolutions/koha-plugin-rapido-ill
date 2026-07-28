#!/usr/bin/env perl

# Copyright 2026 ByWater Solutions
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

use Test::More tests => 4;
use Test::NoWarnings;

use JSON qw(decode_json);
use Koha::Database;

BEGIN {
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::SyncLog');
    use_ok('RapidoILL::SyncLogs');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

subtest 'SyncLog CRUD and JSON encoding' => sub {
    plan tests => 10;

    # Create a basic log entry
    my $log = RapidoILL::SyncLog->new(
        {
            pod        => 'test-pod',
            started_at => \'NOW()',
        }
    )->store();

    ok( $log->id, 'SyncLog created with auto-increment id' );
    is( $log->pod, 'test-pod', 'pod stored correctly' );
    ok( defined $log->started_at, 'started_at set' );
    is( $log->error_details, undef, 'error_details defaults to undef' );

    # Update with results
    my $messages = [
        { type => 'created', circId => 'CIRC001', message => 'Created ILL request 1' },
        { type => 'error',   circId => 'CIRC002', message => 'Unknown patron' },
    ];

    $log->set(
        {
            finished_at   => \'NOW()',
            processed     => 5,
            created       => 1,
            updated       => 2,
            skipped       => 1,
            errors        => 1,
            error_details => $messages,
        }
    )->store();

    # Re-fetch to verify persistence
    my $fetched = RapidoILL::SyncLogs->find( $log->id );
    is( $fetched->processed, 5,     'processed updated' );
    is( $fetched->created,   1,     'created updated' );
    is( $fetched->errors,    1,     'errors updated' );
    ok( $fetched->finished_at,      'finished_at set' );

    # Verify JSON encoding of error_details
    my $details = decode_json( $fetched->error_details );
    is( ref($details), 'ARRAY', 'error_details is a JSON array' );
    is( $details->[0]->{circId}, 'CIRC001', 'error_details content preserved' );
};

$schema->storage->txn_rollback;
