#!/usr/bin/env perl

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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Test::More tests => 2;
use Test::NoWarnings;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use C4::Context;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Userenv payload structure verification' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Create test data
    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );

    # Mock userenv
    t::lib::Mocks::mock_userenv(
        {
            borrowernumber => $patron->borrowernumber,
            branchcode     => $library->branchcode,
        }
    );

    # Test 1: Verify userenv is set correctly
    my $userenv = C4::Context->userenv;
    ok( $userenv, 'Userenv is set' );
    is( $userenv->{branch}, $library->branchcode,    'Userenv branch is correct' );
    is( $userenv->{number}, $patron->borrowernumber, 'Userenv borrowernumber is correct' );

    # Test 2: Create a task with userenv payload manually (simulating what hooks do)
    use RapidoILL::QueuedTasks;
    my $tasks = RapidoILL::QueuedTasks->new;

    my $task = $tasks->enqueue(
        {
            object_type => 'circulation',
            object_id   => 123,
            action      => 'b_item_renewal',
            pod         => 'test-pod',
            payload     => {
                due_date => '2024-12-31',
                userenv  => $userenv,
            }
        }
    );

    # Test 3: Verify task structure
    ok( $task, 'Task created successfully' );

    # Test 4: Verify payload contains complete userenv
    my $payload = $task->decoded_payload;
    ok( $payload, 'Task has payload' );
    is_deeply(
        $payload,
        {
            due_date => '2024-12-31',
            userenv  => $userenv,
        },
        'Payload contains complete userenv and action-specific data'
    );

    $schema->storage->txn_rollback;
};
