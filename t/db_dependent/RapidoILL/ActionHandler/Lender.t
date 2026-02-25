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

use Test::More tests => 11;
use Test::NoWarnings;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use C4::Circulation qw( AddIssue );
use Koha::Database;
use Koha::ILL::Requests;
use Koha::Items;
use Koha::Patrons;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Constructor and basic functionality' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    # Use plugin accessor instead of direct instantiation
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_lender_action_handler('test_pod');

    isa_ok( $handler, 'RapidoILL::ActionHandler::Lender', 'Object created successfully' );
    is( $handler->{pod}, 'test_pod', 'Pod parameter stored correctly' );
    isa_ok( $handler->{plugin}, 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL', 'Plugin parameter stored correctly' );

    $schema->storage->txn_rollback;
};

subtest 'handle_from_action dispatch mechanism with real CircAction objects' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Use plugin accessor instead of mocking
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_lender_action_handler('test_pod');

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
                circId        => 'TEST_CIRC_001',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'TEST_BARCODE_001'
            }
        }
    );

    lives_ok {
        $handler->handle_from_action($final_checkin_action)
    }
    'FINAL_CHECKIN action handled without exception';

    # Test ITEM_SHIPPED dispatch with real CircAction
    my $item_shipped_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_SHIPPED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_002',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'TEST_BARCODE_002'
            }
        }
    );

    lives_ok {
        $handler->handle_from_action($item_shipped_action)
    }
    'ITEM_SHIPPED action handled without exception';

    # Test ITEM_RECEIVED dispatch with real CircAction
    my $item_received_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_RECEIVED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_003',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemId        => 'TEST_ITEM_ID',
                itemBarcode   => 'TEST_BARCODE_003'
            }
        }
    );

    # This will fail due to missing item, but we can test the dispatch
    throws_ok {
        $handler->handle_from_action($item_received_action)
    }
    qr//, 'ITEM_RECEIVED action dispatched (may fail due to missing item data)';

    # Test ITEM_IN_TRANSIT dispatch with real CircAction
    my $item_in_transit_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_IN_TRANSIT',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_004',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'TEST_BARCODE_004'
            }
        }
    );

    throws_ok {
        $handler->handle_from_action($item_in_transit_action)
    }
    qr//, 'ITEM_IN_TRANSIT action dispatched (may fail due to missing item data)';

    # Test unknown status dispatch with real CircAction
    my $unknown_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'UNKNOWN_STATUS',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_005',
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

subtest 'final_checkin method (lender-generated - no-op)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for FINAL_CHECKIN
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'FINAL_CHECKIN'; } );

    # Test that FINAL_CHECKIN is handled as no-op (no exception thrown)
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'FINAL_CHECKIN handled as no-op without exception';

    $schema->storage->txn_rollback;
};

subtest 'item_shipped method (lender-generated - no-op without dueDateTime)' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => { backend => 'RapidoILL', status => 'O_ITEM_SHIPPED' }
        }
    );

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Create a mock action for ITEM_SHIPPED without dueDateTime
    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'lastCircState', sub { return 'ITEM_SHIPPED'; } );
    $mock_action->mock( 'dueDateTime',   sub { return undef; } );
    $mock_action->mock( 'ill_request',   sub { return $ill_request; } );

    # Without dueDateTime, item_shipped is effectively a no-op
    lives_ok {
        $handler->handle_from_action($mock_action)
    }
    'ITEM_SHIPPED without dueDateTime handled without exception';

    $schema->storage->txn_rollback;
};

subtest 'item_received method with database operations and real CircAction' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    # Create test data
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my $item   = $builder->build_object(
        {
            class => 'Koha::Items',
            value => {
                biblionumber => $biblio->biblionumber,
                barcode      => 'TEST_BARCODE_123'
            }
        }
    );
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                backend        => 'RapidoILL'
            }
        }
    );

    # Create real CircAction object
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_RECEIVED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_RECEIVED',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemId        => 'TEST_BARCODE_123',
                itemBarcode   => 'TEST_BARCODE_123'
            }
        }
    );

    # Mock plugin with required methods
    my $mock_plugin = Test::MockObject->new();
    $mock_plugin->mock(
        'add_issue',
        sub {
            my ( $self, $params ) = @_;

            # Return a mock checkout object
            my $mock_checkout = Test::MockObject->new();
            $mock_checkout->set_always( 'id', 999 );
            return $mock_checkout;
        }
    );
    $mock_plugin->mock( 'add_or_update_attributes', sub { return; } );
    $mock_plugin->mock( 'get_checkout',             sub { return; } );    # No existing checkout

    # Mock logger
    my $mock_logger = Test::MockObject->new();
    $mock_logger->mock( 'warn',   sub { return; } );
    $mock_plugin->mock( 'logger', sub { return $mock_logger; } );

    my $handler = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Test successful item_received processing
    lives_ok {
        $handler->item_received($circ_action)
    }
    'item_received processes successfully with real CircAction';

    # Verify status was updated
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_ITEM_RECEIVED_DESTINATION', 'ILL request status updated correctly' );

    # Test error handling with missing item
    my $missing_item_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_RECEIVED',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_MISSING',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemId        => 'NONEXISTENT_BARCODE',
                itemBarcode   => 'NONEXISTENT_BARCODE'
            }
        }
    );

    throws_ok {
        $handler->item_received($missing_item_action)
    }
    qr//, 'item_received handles missing item appropriately';

    $schema->storage->txn_rollback;
};

subtest 'item_in_transit method with database operations and real CircAction' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    # Create test data
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my $item   = $builder->build_object(
        {
            class => 'Koha::Items',
            value => {
                biblionumber => $biblio->biblionumber,
                barcode      => 'TEST_TRANSIT_123'
            }
        }
    );
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                backend        => 'RapidoILL'
            }
        }
    );

    # Create real CircAction object
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_IN_TRANSIT',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_TRANSIT',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'TEST_TRANSIT_123'
            }
        }
    );

    # Mock plugin with required methods
    my $mock_plugin = Test::MockObject->new();
    $mock_plugin->mock(
        'add_issue',
        sub {
            my ( $self, $params ) = @_;
            my $mock_checkout = Test::MockObject->new();
            $mock_checkout->set_always( 'id', 888 );
            return $mock_checkout;
        }
    );
    $mock_plugin->mock( 'add_or_update_attributes', sub { return; } );
    $mock_plugin->mock( 'get_checkout',             sub { return; } );    # No existing checkout

    # Mock logger
    my $mock_logger = Test::MockObject->new();
    $mock_logger->mock( 'warn',   sub { return; } );
    $mock_plugin->mock( 'logger', sub { return $mock_logger; } );

    my $handler = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    # Test successful item_in_transit processing
    lives_ok {
        $handler->item_in_transit($circ_action)
    }
    'item_in_transit processes successfully with real CircAction';

    # Verify status was updated
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_ITEM_IN_TRANSIT', 'ILL request status updated correctly' );

    # Test error handling with missing item
    my $missing_item_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_IN_TRANSIT',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_MISSING_TRANSIT',
                borrowerCode  => 'TEST_BORROWER',
                callNumber    => 'TEST_CALL',
                itemBarcode   => 'NONEXISTENT_BARCODE'
            }
        }
    );

    throws_ok {
        $handler->item_in_transit($missing_item_action)
    }
    qr//, 'item_in_transit handles missing item appropriately';

    $schema->storage->txn_rollback;
};

subtest 'borrowing_site_cancel method with database operations and real CircAction' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Create handler using plugin accessor
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = $plugin->get_lender_action_handler('test_pod');

    # Test case 1: ILL request WITH hold_id attribute
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => { status => 'O_ITEM_SHIPPED' }
        }
    );

    # Create test hold
    my $hold = $builder->build_object(
        {
            class => 'Koha::Holds',
            value => {
                biblionumber => $ill_request->biblio_id,
            }
        }
    );

    # Add hold_id extended attribute
    $builder->build_object(
        {
            class => 'Koha::ILL::Request::Attributes',
            value => {
                illrequest_id => $ill_request->illrequest_id,
                type          => 'hold_id',
                value         => $hold->reserve_id,
            }
        }
    );

    # Create real CircAction object
    my $action_with_hold = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'BORROWING_SITE_CANCEL',
                illrequest_id => $ill_request->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_CANCEL_WITH_HOLD'
            }
        }
    );

    # Test the handler
    lives_ok { $handler->borrowing_site_cancel($action_with_hold) }
    'borrowing_site_cancel executes without error with hold';

    # Verify request status was updated
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_ITEM_CANCELLED', 'Request status set to O_ITEM_CANCELLED' );

    # Test case 2: ILL request WITHOUT hold_id attribute
    my $ill_request_no_hold = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => { status => 'O_ITEM_SHIPPED' }
        }
    );

    # Create real CircAction object without hold
    my $action_no_hold = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'BORROWING_SITE_CANCEL',
                illrequest_id => $ill_request_no_hold->id,
                pod           => 'test_pod',
                circId        => 'TEST_CIRC_CANCEL_NO_HOLD'
            }
        }
    );

    # Test the handler
    lives_ok { $handler->borrowing_site_cancel($action_no_hold) }
    'borrowing_site_cancel works without hold_id attribute';

    # Verify request status was updated
    $ill_request_no_hold->discard_changes;
    is( $ill_request_no_hold->status, 'O_ITEM_CANCELLED', 'Request status updated even without hold' );

    $schema->storage->txn_rollback;
};

subtest 'handle_from_action() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    # Create test data
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->id,
                biblio_id      => $biblio->id,
                backend        => 'RapidoILL',
                status         => 'O_ITEM_RECEIVED_DESTINATION',
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

    # Create plugin and handler
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $handler = RapidoILL::ActionHandler::Lender->new(
        {
            plugin => $plugin,
            pod    => t::lib::Mocks::Rapido::POD,
        }
    );

    # Test that RECALL is handled as no-op
    my $original_status = $ill_request->status;

    lives_ok {
        $handler->handle_from_action($circ_action);
    }
    'RECALL action handled without error (no-op)';

    # Verify status unchanged (no-op)
    $ill_request->discard_changes;
    is( $ill_request->status, $original_status, 'Request status unchanged (RECALL is no-op for lender)' );

    $schema->storage->txn_rollback;
};

subtest 'renewal() tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    # Create test data
    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );

    # Create plugin with mock configuration
    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype
        }
    );

    # Create test ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                branchcode     => $library->branchcode,
                borrowernumber => $patron->borrowernumber,
                backend        => 'RapidoILL',
                status         => 'O_ITEM_RECEIVED_DESTINATION',
            }
        }
    );

    # Add required attributes
    $plugin->add_or_update_attributes(
        {
            request    => $ill_request,
            attributes => {
                circId => 'TEST_CIRC_001',
                pod    => t::lib::Mocks::Rapido::POD,
            }
        }
    );

    # Create CircAction using TestBuilder
    my $circ_action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                illrequest_id => $ill_request->id,
                lastCircState => 'BORROWER_RENEW',
                circId        => 'TEST_CIRC_001',
            }
        }
    );

    # Mock the RapidoILL::Client
    my $client_module = Test::MockModule->new('RapidoILL::Client');
    $client_module->mock( 'lender_renew', sub { return 1; } );

    # Create handler using plugin method
    my $handler = $plugin->get_lender_action_handler(t::lib::Mocks::Rapido::POD);

    # Test borrower_renew method
    lives_ok {
        $handler->borrower_renew($circ_action);
    }
    'borrower_renew processes without exception';

    # Verify status changed to O_RENEWAL_REQUESTED
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_RENEWAL_REQUESTED', 'Status set to O_RENEWAL_REQUESTED' );

    # Verify renewal attributes were added
    my $renewal_circId_attr = $ill_request->extended_attributes->find( { type => 'renewal_circId' } );
    ok( $renewal_circId_attr, 'Renewal circId attribute created' );
    is( $renewal_circId_attr->value, 'TEST_CIRC_001', 'Renewal circId stored correctly' );

    $schema->storage->txn_rollback;
};

subtest 'item_shipped() updates checkout due date from Rapido dueDateTime' => sub {

    plan tests => 11;

    $schema->storage->txn_begin;

    # Create test data
    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron   = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => {
                branchcode   => $library->branchcode,
                categorycode => $category->categorycode,
            }
        }
    );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my $item   = $builder->build_object(
        {
            class => 'Koha::Items',
            value => {
                biblionumber  => $biblio->biblionumber,
                homebranch    => $library->branchcode,
                holdingbranch => $library->branchcode,
                itype         => $itemtype->itemtype,
            }
        }
    );

    # Create a checkout (simulating what LenderActions::item_shipped does via AddIssue)
    t::lib::Mocks::mock_userenv( { branchcode => $library->branchcode } );
    my $checkout = AddIssue( $patron, $item->barcode );
    ok( $checkout, 'Checkout created' );

    # Record the circ-rule-based due date
    my $circ_rule_due_date = $checkout->date_due;

    # Create ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                biblio_id      => $biblio->biblionumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'O_ITEM_SHIPPED',
                due_date       => undef,
            }
        }
    );

    # Create plugin with test config (due_date_buffer_days: 7)
    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    # Store checkout_id attribute so get_checkout() can find it
    $plugin->add_or_update_attributes(
        {
            request    => $ill_request,
            attributes => {
                checkout_id => $checkout->id,
                pod         => t::lib::Mocks::Rapido::POD,
            }
        }
    );

    my $handler = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => t::lib::Mocks::Rapido::POD,
            plugin => $plugin,
        }
    );

    # Rapido dueDateTime: March 6, 2026 23:59:23 UTC (epoch 1772841563)
    my $rapido_epoch = 1772841563;

    # Create CircAction with dueDateTime
    my $action = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_SHIPPED',
                illrequest_id => $ill_request->id,
                pod           => t::lib::Mocks::Rapido::POD,
                circId        => 'TEST_SHIPPED_DUE',
                borrowerCode  => 'TEST',
                callNumber    => 'TEST',
                dueDateTime   => $rapido_epoch,
            }
        }
    );

    # Run the handler
    lives_ok {
        $handler->item_shipped($action);
    }
    'item_shipped with dueDateTime processes without exception';

    # Verify checkout due date was updated (Rapido date minus 7 buffer days)
    $checkout->discard_changes;
    like( $checkout->date_due, qr/2026-02-27/, 'Checkout due date updated to Rapido date minus 7 buffer days' );

    # Verify ILL request due_date was set
    $ill_request->discard_changes;
    like( $ill_request->due_date, qr/2026-02-27/, 'ILL request due_date set to buffered date' );

    # Verify dueDateWithBuffer attribute stored the original Rapido date
    my $buffer_attr = $ill_request->extended_attributes->find( { type => 'dueDateWithBuffer' } );
    ok( $buffer_attr, 'dueDateWithBuffer attribute created' );
    like( $buffer_attr->value, qr/2026-03-06/, 'dueDateWithBuffer contains original Rapido due date' );

    # Test with dueDateTime but no checkout — should warn
    my $ill_request_no_checkout = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'O_ITEM_SHIPPED',
                due_date       => undef,
            }
        }
    );

    # Store pod but NO checkout_id
    $plugin->add_or_update_attributes(
        {
            request    => $ill_request_no_checkout,
            attributes => { pod => t::lib::Mocks::Rapido::POD },
        }
    );

    my $action_no_checkout = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_SHIPPED',
                illrequest_id => $ill_request_no_checkout->id,
                pod           => t::lib::Mocks::Rapido::POD,
                circId        => 'TEST_SHIPPED_NO_CHECKOUT',
                borrowerCode  => 'TEST',
                callNumber    => 'TEST',
                dueDateTime   => $rapido_epoch,
            }
        }
    );

    my $warn_logged = 0;
    my $logger_mock = Test::MockModule->new('Koha::Logger');
    $logger_mock->mock( 'warn', sub { $warn_logged = 1; } );

    lives_ok {
        $handler->item_shipped($action_no_checkout);
    }
    'item_shipped with dueDateTime but no checkout processes without exception';

    ok( $warn_logged, 'Warning logged when no checkout found' );

    # ILL request due_date should still be updated even without checkout
    $ill_request_no_checkout->discard_changes;
    like( $ill_request_no_checkout->due_date, qr/2026-02-27/, 'ILL request due_date still set even without checkout' );

    # Test without dueDateTime — should be a no-op
    my $ill_request2 = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'O_ITEM_SHIPPED',
                due_date       => undef,
            }
        }
    );

    my $action_no_due = $builder->build_object(
        {
            class => 'RapidoILL::CircActions',
            value => {
                lastCircState => 'ITEM_SHIPPED',
                illrequest_id => $ill_request2->id,
                pod           => t::lib::Mocks::Rapido::POD,
                circId        => 'TEST_SHIPPED_NO_DUE',
                borrowerCode  => 'TEST',
                callNumber    => 'TEST',
                dueDateTime   => undef,
            }
        }
    );

    lives_ok {
        $handler->item_shipped($action_no_due);
    }
    'item_shipped without dueDateTime is a no-op';

    $ill_request2->discard_changes;
    is( $ill_request2->due_date, undef, 'ILL request due_date remains NULL when no dueDateTime' );

    $schema->storage->txn_rollback;
};
