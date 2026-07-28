#!/usr/bin/env perl

# This file is part of the Rapido ILL plugin
#
# The Rapido ILL plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The Rapido ILL plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 4;
use Test::NoWarnings;
use JSON qw(decode_json encode_json);

use Koha::Database;

BEGIN {
    use_ok('RapidoILL::ServerStatusLog');
    use_ok('RapidoILL::ServerStatusLogs');
}

my $schema = Koha::Database->schema;

subtest 'store() tests' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    subtest 'basic storage' => sub {

        plan tests => 5;

        my $log = RapidoILL::ServerStatusLog->new(
            {
                pod           => 'test-pod',
                status_code   => 502,
                task_id       => 42,
                action        => 'o_item_shipped',
                delay_minutes => 20,
                delayed_until => \'DATE_ADD(NOW(), INTERVAL 1200 SECOND)',
            }
        )->store();

        ok( $log->id, 'Log entry created with auto-increment ID' );
        is( $log->pod,         'test-pod',       'pod stored correctly' );
        is( $log->status_code, 502,              'status_code stored correctly' );
        is( $log->action,      'o_item_shipped', 'action stored correctly' );
        ok( $log->delayed_until, 'delayed_until timestamp stored' );
    };

    subtest 'affected_task_ids arrayref gets JSON-encoded' => sub {

        plan tests => 3;

        my $ids = [ 10, 20, 30 ];

        my $log = RapidoILL::ServerStatusLog->new(
            {
                pod               => 'test-pod',
                status_code       => 503,
                delay_minutes     => 15,
                delayed_until     => \'NOW()',
                affected_task_ids => $ids,
            }
        )->store();

        my $stored = $log->affected_task_ids;
        ok( !ref($stored), 'Arrayref stored as string' );
        is_deeply( decode_json($stored), $ids, 'JSON decodes back to original arrayref' );

        # Re-fetch from DB to confirm persistence
        my $refetched = RapidoILL::ServerStatusLogs->find( $log->id );
        is_deeply( decode_json( $refetched->affected_task_ids ), $ids, 'Persisted correctly in database' );
    };

    subtest 'affected_task_ids as pre-encoded JSON string left unchanged' => sub {

        plan tests => 1;

        my $json_str = '[1,2,3]';

        my $log = RapidoILL::ServerStatusLog->new(
            {
                pod               => 'test-pod',
                status_code       => 500,
                delay_minutes     => 20,
                delayed_until     => \'NOW()',
                affected_task_ids => $json_str,
            }
        )->store();

        is( $log->affected_task_ids, $json_str, 'Pre-encoded JSON string left unchanged' );
    };

    subtest 'affected_task_ids undef left as undef' => sub {

        plan tests => 1;

        my $log = RapidoILL::ServerStatusLog->new(
            {
                pod           => 'test-pod',
                status_code   => 504,
                delay_minutes => 20,
                delayed_until => \'NOW()',
            }
        )->store();

        is( $log->affected_task_ids, undef, 'Undefined affected_task_ids stays undef' );
    };

    subtest 'empty arrayref' => sub {

        plan tests => 1;

        my $log = RapidoILL::ServerStatusLog->new(
            {
                pod               => 'test-pod',
                status_code       => 502,
                delay_minutes     => 20,
                delayed_until     => \'NOW()',
                affected_task_ids => [],
            }
        )->store();

        is_deeply( decode_json( $log->affected_task_ids ), [], 'Empty arrayref stored as empty JSON array' );
    };

    $schema->storage->txn_rollback;
};
