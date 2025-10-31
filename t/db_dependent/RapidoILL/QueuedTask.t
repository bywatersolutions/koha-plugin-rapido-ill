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

use Test::More tests => 15;
use Test::NoWarnings;
use Test::Exception;
use JSON qw(decode_json encode_json);

use t::lib::TestBuilder;
use C4::Context;
use Koha::Database;

BEGIN {
    use_ok('RapidoILL::QueuedTask');
    use_ok('RapidoILL::QueuedTasks');
}

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Object instantiation and basic properties' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    # Create a test task
    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0
        }
    )->store;

    ok( $task, 'Task created successfully' );
    isa_ok( $task, 'RapidoILL::QueuedTask', 'Object has correct class' );
    is( $task->object_type, 'ill',      'Object type set correctly' );
    is( $task->action,      'fill',     'Action set correctly' );
    is( $task->pod,         'test-pod', 'Pod set correctly' );
    is( $task->status,      'queued',   'Status set correctly' );

    $schema->storage->txn_rollback;
};

subtest 'ill_request() method' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    # Create a test ILL request
    my $ill_request = $builder->build_object( { class => "Koha::ILL::Requests" } );

    # Create task linked to ILL request
    my $task = RapidoILL::QueuedTask->new(
        {
            object_type   => 'ill',
            object_id     => 123,
            illrequest_id => $ill_request->illrequest_id,
            action        => 'fill',
            pod           => 'test-pod'
        }
    )->store;

    my $linked_request = $task->ill_request;
    ok( $linked_request, 'ill_request() returns object' );
    isa_ok(
        $linked_request, 'Koha::ILL::Request',
        'Returned object has correct class'
    );
    is(
        $linked_request->illrequest_id,
        $ill_request->illrequest_id,
        'Correct ILL request returned'
    );

    $schema->storage->txn_rollback;
};

subtest 'decoded_payload() tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    # Test data structure
    my $test_data = {
        action => 'test_action',
        params => {
            key1 => 'value1',
            key2 => 42,
            key3 => [ 'array', 'values' ]
        }
    };

    # Create task with JSON payload
    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0,
            payload     => JSON::encode_json($test_data)
        }
    )->store;

    # Test decoded_payload method
    my $decoded = $task->decoded_payload;
    ok( $decoded, 'decoded_payload() returns data' );
    is_deeply(
        $decoded, $test_data,
        'Decoded payload matches original data structure'
    );
    is( ref($decoded), 'HASH', 'Decoded payload is a hash reference' );

    $schema->storage->txn_rollback;
};

subtest 'store() method with automatic JSON encoding' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    # Test 1: Hash reference gets JSON-encoded
    my $hash_data = {
        action => 'test_action',
        params => {
            key1   => 'value1',
            key2   => 42,
            nested => { deep => 'value' }
        }
    };

    my $task1 = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0,
            payload     => $hash_data
        }
    )->store;

    # Verify payload was JSON-encoded in database
    my $stored_payload1 = $task1->payload;
    ok( !ref($stored_payload1), 'Hash payload stored as string' );
    is_deeply(
        decode_json($stored_payload1),
        $hash_data, 'Stored JSON matches original hash data'
    );

    # Test 2: Array reference gets JSON-encoded
    my $array_data = [ 'item1', 'item2', { nested => 'array_item' } ];

    my $task2 = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 124,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0,
            payload     => $array_data
        }
    )->store;

    my $stored_payload2 = $task2->payload;
    ok( !ref($stored_payload2), 'Array payload stored as string' );
    is_deeply(
        decode_json($stored_payload2),
        $array_data, 'Stored JSON matches original array data'
    );

    # Test 3: Already JSON string is left unchanged
    my $json_string = '{"already":"json","number":123}';

    my $task3 = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 125,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0,
            payload     => $json_string
        }
    )->store;

    my $stored_payload3 = $task3->payload;
    is( $stored_payload3, $json_string, 'JSON string payload left unchanged' );

    # Test 4: Plain string is left unchanged
    my $plain_string = 'just a plain string';

    my $task4 = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 126,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0,
            payload     => $plain_string
        }
    )->store;

    my $stored_payload4 = $task4->payload;
    is(
        $stored_payload4, $plain_string,
        'Plain string payload left unchanged'
    );

    # Test 5: Undefined payload is left unchanged
    my $task5 = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 127,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',
            attempts    => 0

                # No payload set
        }
    )->store;

    my $stored_payload5 = $task5->payload;
    is( $stored_payload5, undef, 'Undefined payload left unchanged' );

    # Test 6: Verify decoded_payload works with auto-encoded data
    my $decoded1 = $task1->decoded_payload;
    is_deeply(
        $decoded1, $hash_data,
        'decoded_payload works with auto-encoded hash'
    );

    $schema->storage->txn_rollback;
};

subtest 'can_retry() method' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    # Create task with 0 attempts
    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            attempts    => 0
        }
    )->store;

    is( $task->can_retry(),  1, 'Task with 0 attempts can retry (default max)' );
    is( $task->can_retry(5), 1, 'Task with 0 attempts can retry (custom max)' );

    # Update attempts to 5
    $task->set( { attempts => 5 } )->store;
    is(
        $task->can_retry(5), 1,
        'Task with 5 attempts can retry when max is 5'
    );
    is(
        $task->can_retry(4), 0,
        'Task with 5 attempts cannot retry when max is 4'
    );

    # Update attempts to 11 (exceeds default max of 10)
    $task->set( { attempts => 11 } )->store;
    is(
        $task->can_retry(), 0,
        'Task with 11 attempts cannot retry (default max 10)'
    );
    is(
        $task->can_retry(15),
        1, 'Task with 11 attempts can retry with higher max'
    );

    $schema->storage->txn_rollback;
};

subtest 'error() method' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod'
        }
    )->store;

    # Test error without error details
    my $result = $task->error();
    isa_ok(
        $result, 'RapidoILL::QueuedTask',
        'error() returns task object for chaining'
    );
    is( $task->status,     'error', 'Status set to error' );
    is( $task->last_error, undef,   'No error details when none provided' );

    # Test error with error details
    my $error_details = { message => 'Test error', code => 500 };
    $task->error($error_details);
    is( $task->status, 'error', 'Status remains error' );
    ok( $task->last_error, 'Error details stored' );

    # Verify JSON encoding
    my $decoded_error = JSON::decode_json( $task->last_error );
    is(
        $decoded_error->{message},
        'Test error', 'Error details correctly JSON encoded'
    );

    $schema->storage->txn_rollback;
};

subtest 'retry() method' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            attempts    => 2
        }
    )->store;

    # Test retry with default delay
    my $result = $task->retry();
    isa_ok(
        $result, 'RapidoILL::QueuedTask',
        'retry() returns task object for chaining'
    );
    is( $task->status,   'retry', 'Status set to retry' );
    is( $task->attempts, 3,       'Attempts incremented' );
    ok( $task->run_after, 'run_after timestamp set' );

    # Test retry with custom delay and error
    my $error_details = { message => 'Retry error', code => 503 };
    $task->retry( { delay => 300, error => $error_details } );
    is( $task->status,   'retry', 'Status remains retry' );
    is( $task->attempts, 4,       'Attempts incremented again' );
    ok( $task->last_error, 'Error details stored' );

    # Verify JSON encoding of error
    my $decoded_error = JSON::decode_json( $task->last_error );
    is(
        $decoded_error->{message},
        'Retry error', 'Retry error details correctly stored'
    );

    $schema->storage->txn_rollback;
};

subtest 'success() method' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'retry'
        }
    )->store;

    my $result = $task->success();
    isa_ok(
        $result, 'RapidoILL::QueuedTask',
        'success() returns task object for chaining'
    );
    is( $task->status, 'success', 'Status set to success' );

    $schema->storage->txn_rollback;
};

subtest 'Database field validation and constraints' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    # Suppress expected database warnings for constraint validation tests
    local $SIG{__WARN__} = sub {
        my $warning = shift;

        # Only suppress expected database constraint warnings
        warn $warning
            unless $warning =~
            /DBD::mysql::st execute failed:|Field .* doesn't have a default value|Data truncated for column/;
    };

    # Test required fields
    throws_ok {
        RapidoILL::QueuedTask->new(
            {
                object_id => 123,
                action    => 'fill',
                pod       => 'test-pod'

                    # Missing object_type
            }
        )->store;
    }
    qr//, 'Missing object_type throws error';

    throws_ok {
        RapidoILL::QueuedTask->new(
            {
                object_type => 'ill',
                object_id   => 123,
                pod         => 'test-pod'

                    # Missing action
            }
        )->store;
    }
    qr//, 'Missing action throws error';

    throws_ok {
        RapidoILL::QueuedTask->new(
            {
                object_type => 'ill',
                object_id   => 123,
                action      => 'fill'

                    # Missing pod
            }
        )->store;
    }
    qr//, 'Missing pod throws error';

    # Test enum validation
    throws_ok {
        RapidoILL::QueuedTask->new(
            {
                object_type => 'invalid_type',
                object_id   => 123,
                action      => 'fill',
                pod         => 'test-pod'
            }
        )->store;
    }
    qr//, 'Invalid object_type throws error';

    throws_ok {
        RapidoILL::QueuedTask->new(
            {
                object_type => 'ill',
                object_id   => 123,
                action      => 'invalid_action',
                pod         => 'test-pod'
            }
        )->store;
    }
    qr//, 'Invalid action throws error';

    # Test valid enum values
    my $task1 = RapidoILL::QueuedTask->new(
        {
            object_type => 'circulation',
            object_id   => 123,
            action      => 'b_item_received',
            pod         => 'test-pod'
        }
    )->store;
    ok( $task1, 'Valid enum values accepted' );

    my $task2 = RapidoILL::QueuedTask->new(
        {
            object_type => 'holds',
            object_id   => 456,
            action      => 'o_item_shipped',
            pod         => 'test-pod'
        }
    )->store;
    ok( $task2, 'Different valid enum values accepted' );

    $schema->storage->txn_rollback;
};

subtest 'Default values and auto-increment' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'fill',
            pod         => 'test-pod',
            status      => 'queued',     # Explicitly set since no database default
            attempts    => 0             # Explicitly set since no database default
        }
    )->store;

    ok( $task->id, 'Auto-increment ID assigned' );
    is( $task->status,   'queued', 'Status set correctly' );
    is( $task->attempts, 0,        'Attempts set correctly' );
    ok( $task->timestamp, 'Timestamp automatically set' );

    $schema->storage->txn_rollback;
};

subtest 'execute_with_context() tests' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Create test data
    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );

    # Test 1: No userenv initially
    is( C4::Context->userenv, undef, 'No userenv set initially' );

    # Test 2: Create task with context
    my $test_context = {
        userenv => {
            branch     => $library->branchcode,
            branchname => $library->branchname,
            number     => $patron->borrowernumber,
            id         => 'test_user'
        },
        interface => 'intranet'
    };

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'o_item_shipped',
            pod         => 'test-pod',
            context     => $test_context
        }
    )->store;

    # Test 3: Test execute_with_context with userenv restoration
    my $executed_with_branch;
    my $result = $task->execute_with_context(
        sub {
            $executed_with_branch = C4::Context->userenv->{branch};
            return 'success';
        }
    );

    is( $result,               'success',            'Code executed successfully' );
    is( $executed_with_branch, $library->branchcode, 'Userenv restored correctly during execution' );
    is( C4::Context->userenv,  undef,                'Original userenv restored after execution' );

    # Test 4: Test with no context
    my $task_no_context = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 456,
            action      => 'o_item_shipped',
            pod         => 'test-pod'
        }
    )->store;

    my $executed_without_context = 0;
    $task_no_context->execute_with_context(
        sub {
            $executed_without_context = 1;
            return 'no_context_success';
        }
    );

    is( $executed_without_context, 1, 'Code executed even without context' );

    # Test 5: Test with mock userenv format (branchcode instead of branch)
    my $mock_context = {
        userenv => {
            branchcode => $library->branchcode,
            branchname => $library->branchname,
            number     => $patron->borrowernumber,
            id         => 'mock_user'
        },
        interface => 'api'
    };

    my $task_mock = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 789,
            action      => 'o_item_shipped',
            pod         => 'test-pod',
            context     => $mock_context
        }
    )->store;

    my $executed_with_mock_branch;
    $task_mock->execute_with_context(
        sub {
            $executed_with_mock_branch = C4::Context->userenv->{branch};
        }
    );

    is( $executed_with_mock_branch, $library->branchcode, 'Mock userenv format (branchcode) handled correctly' );

    # Cleanup
    C4::Context->unset_userenv();

    $schema->storage->txn_rollback;
};

subtest 'decoded_context() tests' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Test 1: Valid JSON context
    my $context_data = {
        userenv   => { branch => 'CPL', number => 123 },
        interface => 'intranet'
    };

    my $task = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'o_item_shipped',
            pod         => 'test-pod',
            context     => $context_data
        }
    )->store;

    my $decoded = $task->decoded_context;
    is_deeply( $decoded, $context_data, 'Context decoded correctly' );

    # Test 2: No context
    my $task_no_context = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 456,
            action      => 'o_item_shipped',
            pod         => 'test-pod'
        }
    )->store;

    is( $task_no_context->decoded_context, undef, 'Returns undef when no context' );

    # Test 3: Empty context
    my $task_empty = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 789,
            action      => 'o_item_shipped',
            pod         => 'test-pod',
            context     => ''
        }
    )->store;

    is( $task_empty->decoded_context, undef, 'Returns undef for empty context' );

    # Test 4: Context with userenv only
    my $userenv_only = { userenv => { branch => 'MPL' } };
    my $task_userenv = RapidoILL::QueuedTask->new(
        {
            object_type => 'ill',
            object_id   => 101,
            action      => 'o_item_shipped',
            pod         => 'test-pod',
            context     => $userenv_only
        }
    )->store;

    is_deeply( $task_userenv->decoded_context, $userenv_only, 'Context with userenv only works' );

    $schema->storage->txn_rollback;
};
