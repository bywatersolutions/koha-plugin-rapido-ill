#!/usr/bin/perl

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

use Test::More tests => 9;
use Test::NoWarnings;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks::Rapido;
use Koha::Database;

BEGIN {
    use_ok('RapidoILL::QueuedTasks');
    use_ok('RapidoILL::QueuedTask');
}

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Collection instantiation and basic properties' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $tasks = RapidoILL::QueuedTasks->new;
    ok( $tasks, 'Collection created successfully' );
    isa_ok( $tasks, 'RapidoILL::QueuedTasks', 'Collection has correct class' );
    isa_ok( $tasks, 'Koha::Objects',          'Collection inherits from Koha::Objects' );
    is( $tasks->object_class, 'RapidoILL::QueuedTask', 'Correct object class returned' );

    $schema->storage->txn_rollback;
};

subtest 'enqueue() method' => sub {

    plan tests => 13;

    $schema->storage->txn_begin;

    my $tasks = RapidoILL::QueuedTasks->new;

    # Test basic enqueue
    my $task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD
        }
    );

    ok( $task, 'enqueue() returns task object' );
    isa_ok( $task, 'RapidoILL::QueuedTask', 'Returned object has correct class' );
    is( $task->object_type, 'ill',    'Object type set correctly' );
    is( $task->action,      'fill',   'Action set correctly' );
    is( $task->status,      'queued', 'Default status applied' );
    ok( $task->id, 'Task stored to database (has ID)' );

    # Test enqueue with explicit status
    my $task2 = $tasks->enqueue(
        {
            object_type => 'circulation',
            object_id   => 456,
            action      => 'checkout',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'retry'
        }
    );

    is( $task2->status,    'retry', 'Explicit status overrides default' );
    is( $task2->object_id, 456,     'All attributes set correctly' );

    # Test enqueue with payload containing userenv
    my $payload = {
        item_barcode => '123456789',
        patron_id    => 42,
        notes        => 'Test item shipment',
        userenv      => {
            branch => 'CPL',
            number => 123,
            id     => 'test_user'
        }
    };

    my $task3 = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 789,
            action      => 'o_item_shipped',
            pod         => t::lib::Mocks::Rapido::POD,
            payload     => $payload
        }
    );

    # Test that payload gets JSON-encoded in payload field
    ok( $task3->payload, 'Task has payload field populated' );

    # Test decoded_payload restores the Perl structure
    my $decoded = $task3->decoded_payload;
    is_deeply( $decoded, $payload, 'decoded_payload restores original Perl structure' );
    is( $decoded->{item_barcode},      '123456789', 'Payload item_barcode preserved' );
    is( $decoded->{patron_id},         42,          'Payload patron_id preserved' );
    is( $decoded->{userenv}->{branch}, 'CPL',       'Payload userenv branch preserved' );

    $schema->storage->txn_rollback;
};

subtest 'filter_by_active() method' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $tasks = RapidoILL::QueuedTasks->new;

    # Create tasks with different statuses
    my $queued_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 1,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'queued'
        }
    );

    my $retry_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 2,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'retry'
        }
    );

    my $success_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 3,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'success'
        }
    );

    my $error_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 4,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'error'
        }
    );

    my $skipped_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 5,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'skipped'
        }
    );

    # Test filter_by_active
    my $active_tasks = $tasks->filter_by_active();
    isa_ok( $active_tasks, 'RapidoILL::QueuedTasks', 'filter_by_active returns collection' );
    is( $active_tasks->count, 2, 'Only active tasks (queued + retry) returned' );

    # Verify the correct tasks are returned
    my @active_ids = sort map { $_->object_id } $active_tasks->as_list;
    is_deeply( \@active_ids, [ 1, 2 ], 'Correct active tasks returned (queued and retry)' );

    # Test with additional search attributes
    my $all_tasks       = RapidoILL::QueuedTasks->new;
    my $filtered_active = $all_tasks->search( { object_id => 1 } )->filter_by_active();
    is( $filtered_active->count,           1, 'Additional attributes applied correctly' );
    is( $filtered_active->next->object_id, 1, 'Correct task returned with additional filter' );

    # Test chaining
    my $chained_result = RapidoILL::QueuedTasks->new->filter_by_active();
    isa_ok( $chained_result, 'RapidoILL::QueuedTasks', 'Method can be chained' );

    $schema->storage->txn_rollback;
};

subtest 'filter_by_runnable() method' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $tasks = RapidoILL::QueuedTasks->new;

    # Create tasks with different statuses and run_after times
    my $queued_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 1,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'queued'

                # run_after is NULL (should be runnable)
        }
    );

    my $retry_task_runnable = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 2,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'retry'
        }
    );

    # Set run_after to past time (should be runnable)
    $retry_task_runnable->set( { run_after => \'DATE_SUB(NOW(), INTERVAL 1 HOUR)' } )->store;

    my $retry_task_future = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 3,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'retry'
        }
    );

    # Set run_after to future time (should NOT be runnable)
    $retry_task_future->set( { run_after => \'DATE_ADD(NOW(), INTERVAL 1 HOUR)' } )->store;

    my $success_task = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 4,
            action      => 'fill',
            pod         => t::lib::Mocks::Rapido::POD,
            status      => 'success'

                # Even with NULL run_after, not active so not runnable
        }
    );

    # Test filter_by_runnable
    my $runnable_tasks = $tasks->filter_by_runnable();
    isa_ok( $runnable_tasks, 'RapidoILL::QueuedTasks', 'filter_by_runnable returns collection' );
    is( $runnable_tasks->count, 2, 'Only runnable tasks returned' );

    # Verify the correct tasks are returned
    my @runnable_ids = sort map { $_->object_id } $runnable_tasks->as_list;
    is_deeply( \@runnable_ids, [ 1, 2 ], 'Correct runnable tasks returned (queued + past retry)' );

    # Test with additional search attributes
    my $all_tasks_runnable = RapidoILL::QueuedTasks->new;
    my $filtered_runnable  = $all_tasks_runnable->search( { object_id => 1 } )->filter_by_runnable();
    is( $filtered_runnable->count,           1, 'Additional attributes applied correctly' );
    is( $filtered_runnable->next->object_id, 1, 'Correct task returned with additional filter' );

    # Test that future retry task is not included
    my $future_only = $tasks->search( { object_id => 3 } )->filter_by_runnable();
    is( $future_only->count, 0, 'Future retry task not included in runnable' );

    # Test that non-active tasks are not included
    my $success_only = $tasks->search( { object_id => 4 } )->filter_by_runnable();
    is( $success_only->count, 0, 'Success task not included in runnable' );

    # Test chaining
    my $chained_result = RapidoILL::QueuedTasks->new->filter_by_runnable();
    isa_ok( $chained_result, 'RapidoILL::QueuedTasks', 'Method can be chained' );

    $schema->storage->txn_rollback;
};

subtest 'Complex filtering and method chaining' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $initial_count = RapidoILL::QueuedTasks->search()->count;
    my $tasks         = RapidoILL::QueuedTasks->new;

    # Create a variety of tasks
    for my $i ( 1 .. 10 ) {
        my $status =
              $i <= 3 ? 'queued'
            : $i <= 6 ? 'retry'
            : $i <= 8 ? 'success'
            :           'error';

        my $pod = $i <= 5 ? 'pod-a' : 'pod-b';

        $tasks->enqueue(
            {
                object_type => 'ill',
                object_id   => $i,
                action      => 'fill',
                pod         => $pod,
                status      => $status
            }
        );
    }

    # Test method chaining with search
    my $pod_a_active = $tasks->search( { pod => 'pod-a' } )->filter_by_active();
    is( $pod_a_active->count, 5, 'Chained search and filter_by_active works' );

    my $pod_b_active = $tasks->search( { pod => 'pod-b' } )->filter_by_active();
    is( $pod_b_active->count, 1, 'Different pod filter works correctly' );

    # Test complex chaining
    my $specific_tasks =
        RapidoILL::QueuedTasks->new->search( { pod => 'pod-a' } )->filter_by_active()
        ->search( { object_id => { '>' => 2 } } );

    is( $specific_tasks->count, 3, 'Complex method chaining works' );

    # Verify the results
    my @ids = sort map { $_->object_id } $specific_tasks->as_list;
    is_deeply( \@ids, [ 3, 4, 5 ], 'Complex filter returns correct results' );

    # Test that we can still use standard Koha::Objects methods
    my $total_count = $tasks->count;
    is( $total_count, $initial_count + 10, 'Standard count method works' );

    my $first_task = $tasks->search( {}, { order_by => 'object_id' } )->next;
    is( $first_task->object_id, 1, 'Standard search and next methods work' );

    $schema->storage->txn_rollback;
};

subtest 'enqueue() context fallback tests' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $queued_tasks = RapidoILL::QueuedTasks->new;

    # Test 1: Explicit context is preserved
    my $explicit_context = {
        userenv   => { branch => 'EXPLICIT', number => 999 },
        interface => 'api'
    };

    my $task_explicit = $queued_tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'o_item_shipped',
            pod         => t::lib::Mocks::Rapido::POD,
            context     => $explicit_context
        }
    );

    is_deeply( $task_explicit->decoded_context, $explicit_context, 'Explicit context preserved' );

    # Test 2: Default context is created when none provided
    my $task_default = $queued_tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 456,
            action      => 'o_item_shipped',
            pod         => t::lib::Mocks::Rapido::POD
        }
    );

    my $default_context = $task_default->decoded_context;
    ok( $default_context,                     'Default context created' );
    ok( exists $default_context->{userenv},   'Default context has userenv' );
    ok( exists $default_context->{interface}, 'Default context has interface' );

    $schema->storage->txn_rollback;
};
