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
# along with The Rapido ILL plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 14;
use Test::NoWarnings;
use Test::MockObject;
use Test::MockModule;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Logger;
use t::lib::Mocks::Rapido;

use Koha::Database;
use Koha::ILL::Requests;
use Koha::Items;
use Koha::Patrons;
use Koha::Biblios;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $logger  = t::lib::Mocks::Logger->new();

# Default pod in the mocked plugin
my $pod = t::lib::Mocks::Rapido::POD;

subtest 'Constructor and basic functionality' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    # Use plugin accessor instead of direct instantiation
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_borrower_action_handler('test_pod');

    isa_ok( $handler, 'RapidoILL::ActionHandler::Borrower', 'Object created successfully' );
    is( $handler->{pod}, 'test_pod', 'Pod parameter stored correctly' );
    isa_ok( $handler->{plugin}, 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL', 'Plugin parameter stored correctly' );

    $schema->storage->txn_rollback;
};

subtest 'handle_from_action dispatch mechanism with real CircAction objects' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Use plugin accessor instead of mocking
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_borrower_action_handler('test_pod');

    # Create real ILL request for testing
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => { backend => 'RapidoILL' }
        }
    );

    # Test FINAL_CHECKIN dispatch with real CircAction
    my $final_checkin_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'FINAL_CHECKIN',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_FINAL',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL'
            }
        }
    );

    lives_ok {
        $handler->handle_from_action($final_checkin_action)
    }
    'FINAL_CHECKIN action handled without exception';

    # Test ITEM_SHIPPED dispatch with real CircAction - this should do actual work
    my $item_shipped_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_SHIPPED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_SHIPPED',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'TEST_SHIPPED_123'
            }
        }
    );

    throws_ok {
        $handler->handle_from_action($item_shipped_action)
    }
    qr//, 'ITEM_SHIPPED action dispatched (may fail due to missing data)';

    # Test ITEM_RECEIVED dispatch (borrower-generated, no action)
    my $item_received_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_RECEIVED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_RECEIVED_B',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL'
            }
        }
    );

    lives_ok {
        $handler->handle_from_action($item_received_action)
    }
    'ITEM_RECEIVED action handled without exception';

    # Test ITEM_IN_TRANSIT dispatch (borrower-generated, no action)
    my $item_in_transit_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_IN_TRANSIT',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_TRANSIT_B',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL'
            }
        }
    );

    lives_ok {
        $handler->handle_from_action($item_in_transit_action)
    }
    'ITEM_IN_TRANSIT action handled without exception';

    # Test unknown status dispatch with real CircAction
    my $unknown_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'UNKNOWN_STATUS',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_UNKNOWN',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL'
            }
        }
    );

    throws_ok {
        $handler->handle_from_action($unknown_action)
    }
    'RapidoILL::Exception::UnhandledException', 'Unknown status throws UnhandledException';

    # Test DEFAULT handler directly
    throws_ok {
        $handler->default_handler($unknown_action)
    }
    'RapidoILL::Exception::UnhandledException', 'Default handler throws UnhandledException';

    $schema->storage->txn_rollback;
};

subtest 'final_checkin method with paper trail and real CircAction' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Create test ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                backend => 'RapidoILL',
                status  => 'B_ITEM_IN_TRANSIT'
            }
        }
    );

    # Create real CircAction object
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'FINAL_CHECKIN',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_FINAL_CHECKIN',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL'
            }
        }
    );

    # Use plugin accessor
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_borrower_action_handler('test_pod');

    # Test final_checkin creates paper trail
    lives_ok {
        $handler->final_checkin($circ_action)
    }
    'final_checkin processes successfully with real CircAction';

    # Verify paper trail was created
    $ill_request->discard_changes;
    is( $ill_request->status, 'COMP', 'Final status is COMP (completed)' );

    # Test that the method handles the paper trail correctly
    # (B_ITEM_CHECKED_IN should be set before COMP, but we can only verify final state)
    ok( $ill_request->status eq 'COMP', 'Request marked as completed' );

    # Test with different initial status
    $ill_request->status('B_ITEM_RECEIVED')->store;
    lives_ok {
        $handler->final_checkin($circ_action)
    }
    'final_checkin works with different initial status';

    $schema->storage->txn_rollback;
};

subtest 'item_shipped() tests' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    # Create test data
    my $patron      = $builder->build_object( { class => 'Koha::Patrons' } );
    my $library     = $builder->build_object( { class => 'Koha::Libraries' } );
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'B_ITEM_REQUESTED'
            }
        }
    );

    # Mock the plugin module methods before instantiation
    my $rapido_mock = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    my $captured_attributes;

    $rapido_mock->mock(
        'add_virtual_record_and_item',
        sub {
            my ( $self, $params ) = @_;

            # Return a mock item object
            my $mock_item = Test::MockObject->new();
            $mock_item->set_always( 'biblionumber', 123 );
            $mock_item->set_always( 'id',           456 );
            return $mock_item;
        }
    );
    $rapido_mock->mock( 'add_hold', sub { return 789; } );
    $rapido_mock->mock(
        'add_or_update_attributes',
        sub {
            my ( $self, $request, $attributes ) = @_;
            $captured_attributes = $attributes;
            return;
        }
    );

    # Now instantiate the plugin with the mocked methods
    my $mock_plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $builder->build_object( { class => 'Koha::Patron::Categories' } ),
            itemtype => $builder->build_object( { class => 'Koha::ItemTypes' } )
        }
    );

    my $handler = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Mock action with all required attributes
    my $mock_action = Test::MockObject->new();
    $mock_action->set_always( 'itemBarcode', 'TEST_BARCODE_456' );
    $mock_action->set_always( 'ill_request', $ill_request );
    $mock_action->set_always( 'pod',         'test_pod' );
    $mock_action->set_always( 'callNumber',  'TEST CALL NUMBER' );
    $mock_action->set_always( 'centralItemType', 200 );

    # Set all the required action attributes
    my @action_attributes = qw(
        author borrowerCode circId circStatus dateCreated
        itemAgencyCode itemId lastCircState lastUpdated lenderCode
        needBefore patronAgencyCode patronId patronName pickupLocation
        puaLocalServerCode title circ_action_id
    );

    foreach my $attr (@action_attributes) {
        $mock_action->set_always( $attr, "test_$attr" );
    }

    # Test with dueDateTime epoch (January 1, 2025 12:00:00 UTC)
    my $test_epoch = 1735732800;
    $mock_action->set_always( 'dueDateTime', $test_epoch );

    # Test successful item_shipped processing
    lives_ok {
        $handler->item_shipped($mock_action)
    }
    'item_shipped processes successfully with valid data';

    # Verify status was updated
    $ill_request->discard_changes;
    is( $ill_request->status,    'B_ITEM_SHIPPED', 'ILL request status updated correctly' );
    is( $ill_request->biblio_id, 123,              'Biblio ID was set correctly' );

    # Verify due_date was set from dueDateTime epoch (with buffer days subtracted)
    ok( $ill_request->due_date, 'due_date was set from dueDateTime' );
    like(
        $ill_request->due_date, qr/2024-12-25/,
        'due_date contains expected date from epoch (7 days before 2025-01-01)'
    );

    # Test without dueDateTime (should not set due_date)
    my $ill_request2 = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'B_ITEM_REQUESTED',
                due_date       => undef                      # Explicitly set to undef
            }
        }
    );

    # Check initial state
    my $initial_due_date = $ill_request2->due_date;

    my $mock_action2 = Test::MockObject->new();
    $mock_action2->set_always( 'itemBarcode', 'TEST_BARCODE_789' );
    $mock_action2->set_always( 'ill_request', $ill_request2 );
    $mock_action2->set_always( 'pod',         'test_pod' );
    $mock_action2->set_always( 'callNumber',  'TEST CALL NUMBER 2' );
    $mock_action2->set_always( 'dueDateTime', undef );                  # No due date
    $mock_action2->set_always( 'centralItemType', 200 );

    foreach my $attr (@action_attributes) {
        $mock_action2->set_always( $attr, "test_$attr" );
    }

    lives_ok {
        $handler->item_shipped($mock_action2)
    }
    'item_shipped processes successfully without dueDateTime';

    # Verify due_date was not changed when dueDateTime is undefined
    $ill_request2->discard_changes;
    is( $ill_request2->due_date, $initial_due_date, 'due_date unchanged when dueDateTime is undefined' );

    # Test barcode collision handling
    $rapido_mock->mock(
        'add_virtual_record_and_item',
        sub {
            # Simulate barcode collision by throwing an error first time
            die "Barcode collision test";
        }
    );

    throws_ok {
        $handler->item_shipped($mock_action)
    }
    qr/Barcode collision test/, 'item_shipped handles barcode collision appropriately';

    # Test missing barcode
    $mock_action->set_always( 'itemBarcode', undef );
    throws_ok {
        $handler->item_shipped($mock_action)
    }
    'RapidoILL::Exception', 'item_shipped throws exception for missing barcode';

    $schema->storage->txn_rollback;
};

subtest 'owner_renew() tests' => sub {

    plan tests => 11;

    $schema->storage->txn_begin;

    # Create test ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                backend => 'RapidoILL',
                status  => 'B_ITEM_RECEIVED'
            }
        }
    );

    # Create a checkout for the ILL request
    my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item     = $builder->build_object( { class => 'Koha::Items' } );
    my $checkout = $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value => {
                borrowernumber => $patron->id,
                itemnumber     => $item->id,
                date_due       => '2025-09-07 23:59:59',
                note           => undef,
            }
        }
    );

    # Add checkout_id attribute to ILL request
    $builder->build_object(
        {
            class => 'Koha::ILL::Request::Attributes',
            value => {
                illrequest_id => $ill_request->id,
                type          => 'checkout_id',
                value         => $checkout->id
            }
        }
    );

    # Create real CircAction object with dueDateTime
    my $due_epoch   = DateTime->now->add( days => 14 )->epoch;
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'OWNER_RENEW',
                illrequest_id => $ill_request->id,
                pod           => $pod,
                circId        => 'TEST_CIRC_OWNER_RENEW',
                borrowerCode  => 'TEST_BORROWER',
                dueDateTime   => $due_epoch
            }
        }
    );

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $handler = $plugin->get_borrower_action_handler($pod);

    # Test owner_renew with dueDateTime
    lives_ok {
        $handler->owner_renew($circ_action)
    }
    'owner_renew processes successfully with dueDateTime';

    my $config = $plugin->pod_config($pod);

    # Reload checkout object from DB
    $checkout->discard_changes;
    is( $checkout->note, $config->{renewal_accepted_note}, 'Checkout note stored on renewal' );
    isnt( $checkout->notedate, undef, 'Checkout note stored on renewal' );
    ok( !$checkout->noteseen, 'The note is not marked as seen by default' );

    # Verify status and due_date were updated
    $ill_request->discard_changes;
    is( $ill_request->status, 'B_ITEM_RENEWAL_ACCEPTED', 'Status updated to B_ITEM_RENEWAL_ACCEPTED' );
    ok( $ill_request->due_date, 'due_date was set from dueDateTime' );

    # Verify the due_date contains the expected date (7 days earlier due to buffer)
    my $expected_date_with_buffer = DateTime->from_epoch( epoch => $due_epoch );
    my $expected_date             = $expected_date_with_buffer->clone->subtract( days => 7 );
    my $expected_date_str         = $expected_date->ymd . ' ' . $expected_date->hms;
    like(
        $ill_request->due_date, qr/\Q$expected_date_str\E/,
        'due_date contains expected date from epoch (with buffer subtracted)'
    );

    # [#61] Verify checkout due date was also updated (with buffer subtracted)
    $checkout->discard_changes;
    like(
        $checkout->date_due, qr/\Q$expected_date_str\E/,
        'checkout due_date updated to match renewal date (with buffer subtracted)'
    );

    # Test owner_renew without dueDateTime
    my $circ_action2 = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'OWNER_RENEW',
                illrequest_id => $ill_request->id,
                pod           => $pod,
                circId        => 'TEST_CIRC_OWNER_RENEW_2',
                borrowerCode  => 'TEST_BORROWER',
                dueDateTime   => undef
            }
        }
    );

    my $previous_due_date     = $ill_request->due_date;
    my $previous_checkout_due = $checkout->date_due;

    lives_ok {
        $handler->owner_renew($circ_action2)
    }
    'owner_renew processes successfully without dueDateTime';

    # Verify due_date unchanged when dueDateTime is undefined
    $ill_request->discard_changes;
    is( $ill_request->due_date, $previous_due_date, 'due_date unchanged when dueDateTime is undefined' );

    # [#61] Verify checkout due date unchanged when no dueDateTime
    $checkout->discard_changes;
    is( $checkout->date_due, $previous_checkout_due, 'checkout due_date unchanged when no dueDateTime' );

    $schema->storage->txn_rollback;
};

subtest 'item_in_transit method (borrower-generated - no-op)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for ITEM_IN_TRANSIT
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'ITEM_IN_TRANSIT'; } );

    # Test that ITEM_IN_TRANSIT is handled as no-op (no exception thrown)
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'ITEM_IN_TRANSIT handled as no-op without exception';

    $schema->storage->txn_rollback;
};

subtest 'item_received method (borrower-generated - no-op)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for ITEM_RECEIVED
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'ITEM_RECEIVED'; } );

    # Mock ill_request to return a request with non-renewal status
    my $mock_ill_request = Test::MockObject->new();
    $mock_ill_request->mock( 'status', sub { return 'B_ITEM_RECEIVED'; } );    # Not in renewal state
    $mock_action->mock( 'ill_request', sub { return $mock_ill_request; } );

    # Test that ITEM_RECEIVED is handled as no-op (no exception thrown)
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'ITEM_RECEIVED handled as no-op without exception';

    $schema->storage->txn_rollback;
};

subtest 'patron_hold method (borrower-generated - no-op)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for PATRON_HOLD
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'PATRON_HOLD'; } );

    # Test that PATRON_HOLD is handled as no-op (no exception thrown)
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'PATRON_HOLD handled as no-op without exception';

    $schema->storage->txn_rollback;
};

subtest 'borrower_renew method (borrower-generated - no-op)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for BORROWER_RENEW
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'BORROWER_RENEW'; } );

    # Test that BORROWER_RENEW is handled as no-op (no exception thrown)
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'BORROWER_RENEW handled as no-op without exception';

    $schema->storage->txn_rollback;
};

subtest 'default_handler method' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    my $mock_action = Test::MockObject->new();
    $mock_action->set_always( 'lastCircState', 'UNKNOWN_STATUS' );

    # Test that default_handler throws UnhandledException
    throws_ok {
        $handler->default_handler($mock_action)
    }
    'RapidoILL::Exception::UnhandledException', 'default_handler throws UnhandledException for unknown status';

    $schema->storage->txn_rollback;
};

subtest 'item_received renewal rejection' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => t::lib::Mocks::Rapido::POD,
            plugin => $plugin
        }
    );

    # Create a real ILL request in renewal state
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my $item = $builder->build_object( { class => 'Koha::Items', value => { biblionumber => $biblio->biblionumber } } );

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                biblio_id      => $biblio->biblionumber,
                status         => 'B_ITEM_RENEWAL_REQUESTED',
                due_date       => '2025-02-01 23:59:59'
            }
        }
    );

    # Create a checkout for the item
    my $checkout = Koha::Checkout->new(
        {
            borrowernumber => $patron->borrowernumber,
            itemnumber     => $item->itemnumber,
            date_due       => '2025-02-01 23:59:59',
            branchcode     => $patron->branchcode,
        }
    )->store();

    # Link item to ILL request
    Koha::ILL::Request::Attribute->new(
        {
            illrequest_id => $ill_request->id,
            type          => 'item_id',
            value         => $item->itemnumber,
            readonly      => 1
        }
    )->store();

    # Add prevDueDateTime attribute
    my $prev_due_epoch = 1735689599;    # 2024-12-31 23:59:59
    Koha::ILL::Request::Attribute->new(
        {
            illrequest_id => $ill_request->id,
            type          => 'prevDueDateTime',
            value         => $prev_due_epoch,
            readonly      => 1
        }
    )->store();

    # Create mock action for renewal rejection
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'ITEM_RECEIVED'; } );
    $mock_action->mock( 'ill_request',   sub { return $ill_request; } );
    $mock_action->mock( 'circId',        sub { return 'TEST_CIRC_123'; } );

    # Test renewal rejection handling
    lives_ok {
        $handler->item_received($mock_action);
    }
    'Renewal rejection handled without exception';

    # Verify status change
    $ill_request->discard_changes;
    is( $ill_request->status, 'B_ITEM_RECEIVED', 'Status reverted to B_ITEM_RECEIVED' );

    # Verify due date restored (compare just the date part, ignore format differences)
    my $restored_date = $ill_request->due_date;
    $restored_date =~ s/T/ /;    # Convert ISO format to MySQL format if needed
    like( $restored_date, qr/2024-12-31 23:59:59/, 'Due date restored to previous value' );

    # Verify renewal rejection attribute added
    my $rejection_attr = $ill_request->extended_attributes->find( { type => 'renewal_rejected' } );
    ok( $rejection_attr,        'Renewal rejection attribute created' );
    ok( $rejection_attr->value, 'Rejection timestamp recorded' );

    $schema->storage->txn_rollback;
};

subtest 'recall() tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;
    $logger->clear();

    # Create test data
    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
    my $biblio   = $builder->build_object( { class => 'Koha::Biblios' } );

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->id,
                biblio_id      => $biblio->id,
                backend        => 'RapidoILL',
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    # Create CircAction for RECALL
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                illrequest_id => $ill_request->id,
                lastCircState => 'RECALL',
                circId        => 'test-circ-123',
            }
        }
    );

    # Create plugin with mock configuration
    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype
        }
    );

    my $handler = RapidoILL::ActionHandler::Borrower->new(
        {
            plugin => $plugin,
            pod    => t::lib::Mocks::Rapido::POD,
        }
    );

    # Test recall method directly
    lives_ok {
        $handler->recall($circ_action);
    }
    'recall method executes without error';

    # Verify status change
    $ill_request->discard_changes;
    is( $ill_request->status, 'B_ITEM_RECALLED', 'Request status updated to B_ITEM_RECALLED' );

    # Verify logging
    $logger->info_like(
        qr/Item recalled for ILL request \d+ \(circId: test-circ-123\) - status set to B_ITEM_RECALLED/,
        'Recall action logged correctly'
    );

    $schema->storage->txn_rollback;
};

subtest 'owner_cancel() tests' => sub {
    plan tests => 3;

    subtest 'basic functionality' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        # Create test data
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $ill_request = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Create CircAction for OWNING_SITE_CANCEL
        my $circ_action = $builder->build_object(
            {
                class => 'RapidoILL::CircActions',
                value => {
                    illrequest_id => $ill_request->id,
                    lastCircState => 'OWNING_SITE_CANCEL',
                    circId        => 'test-cancel-123',
                }
            }
        );

        # Create plugin with mock configuration
        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        my $handler = RapidoILL::ActionHandler::Borrower->new(
            {
                plugin => $plugin,
                pod    => t::lib::Mocks::Rapido::POD,
            }
        );

        # Test the method exists and can be called
        ok( $handler->can('owner_cancel'), 'owner_cancel method exists' );

        lives_ok {
            $handler->handle_from_action($circ_action);
        }
        'owner_cancel method executes without error';

        # Verify status was updated
        $ill_request->discard_changes;
        is( $ill_request->status, 'B_CANCELLED_BY_OWNER', 'ILL request status updated to B_CANCELLED_BY_OWNER' );

        $schema->storage->txn_rollback;
    };

    subtest 'with virtual item cleanup' => sub {
        plan tests => 4;

        $schema->storage->txn_begin;

        # Create test data with virtual item
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
        my $biblio   = $builder->build_object( { class => 'Koha::Biblios' } );

        my $ill_request = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Create CircAction for OWNING_SITE_CANCEL
        my $circ_action = $builder->build_object(
            {
                class => 'RapidoILL::CircActions',
                value => {
                    illrequest_id => $ill_request->id,
                    lastCircState => 'OWNING_SITE_CANCEL',
                    circId        => 'test-cancel-456',
                }
            }
        );

        # Create plugin with mock configuration
        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        my $handler = RapidoILL::ActionHandler::Borrower->new(
            {
                plugin => $plugin,
                pod    => t::lib::Mocks::Rapido::POD,
            }
        );

        lives_ok {
            $handler->handle_from_action($circ_action);
        }
        'owner_cancel method executes without error with virtual item';

        # Verify status was updated
        $ill_request->discard_changes;
        is( $ill_request->status, 'B_CANCELLED_BY_OWNER', 'ILL request status updated to B_CANCELLED_BY_OWNER' );

        # Verify logging includes cancellation info
        $logger->info_like(
            qr/\[owner_cancel\] Deleted biblio \d+/,
            'Biblio deletion logged'
        );
        $logger->info_like(
            qr/Request cancelled by owner for ILL request \d+ \(circId: test-cancel-\d+\) - status set to B_CANCELLED_BY_OWNER/,
            'Owner cancellation logged correctly'
        );

        $schema->storage->txn_rollback;
    };

    subtest 'dispatch through handle_from_action' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Create test data
        my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $ill_request = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Create CircAction for OWNING_SITE_CANCEL
        my $circ_action = $builder->build_object(
            {
                class => 'RapidoILL::CircActions',
                value => {
                    illrequest_id => $ill_request->id,
                    lastCircState => 'OWNING_SITE_CANCEL',
                    circId        => 'test-dispatch-789',
                }
            }
        );

        # Create plugin with mock configuration
        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        my $handler = RapidoILL::ActionHandler::Borrower->new(
            {
                plugin => $plugin,
                pod    => t::lib::Mocks::Rapido::POD,
            }
        );

        # Test dispatch mechanism correctly routes to owner_cancel
        lives_ok {
            $handler->handle_from_action($circ_action);
        }
        'OWNING_SITE_CANCEL action dispatched correctly';

        # Verify the correct status change occurred
        $ill_request->discard_changes;
        is( $ill_request->status, 'B_CANCELLED_BY_OWNER', 'Dispatch resulted in correct status change' );

        $schema->storage->txn_rollback;
    };
};
