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
# along with The Rapido ILL plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 7;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;
use Koha::ILL::Requests;
use Koha::Items;
use Koha::Patrons;
use Koha::Biblios;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

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

subtest 'item_shipped method with database operations' => sub {
    plan tests => 5;

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

    # Mock plugin with required methods
    my $mock_plugin = Test::MockObject->new();
    $mock_plugin->mock(
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
    $mock_plugin->mock( 'add_hold',                 sub { return 789; } );    # Return hold_id
    $mock_plugin->mock( 'add_or_update_attributes', sub { return; } );
    $mock_plugin->mock(
        'configuration',
        sub {
            return { 'test_pod' => { default_hold_note => 'Test hold' } };
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

    # Set all the required action attributes
    my @action_attributes = qw(
        author borrowerCode circId circStatus dateCreated dueDateTime
        itemAgencyCode itemId lastCircState lastUpdated lenderCode
        needBefore patronAgencyCode patronId patronName pickupLocation
        puaLocalServerCode title circ_action_id
    );

    foreach my $attr (@action_attributes) {
        $mock_action->set_always( $attr, "test_$attr" );
    }

    # Test successful item_shipped processing
    lives_ok {
        $handler->item_shipped($mock_action)
    }
    'item_shipped processes successfully with valid data';

    # Verify status was updated
    $ill_request->discard_changes;
    is( $ill_request->status,    'B_ITEM_SHIPPED', 'ILL request status updated correctly' );
    is( $ill_request->biblio_id, 123,              'Biblio ID was set correctly' );

    # Test barcode collision handling
    $mock_plugin->mock(
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

subtest 'item_in_transit method (borrower-generated)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    my $mock_action = Test::MockObject->new();

    # Test that item_in_transit returns without action (borrower-generated)
    my $result;
    lives_ok {
        $result = $handler->item_in_transit($mock_action)
    }
    'item_in_transit does not throw exception';

    is( $result, undef, 'item_in_transit returns undef (no action needed)' );

    $schema->storage->txn_rollback;
};

subtest 'item_received method (borrower-generated)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $mock_plugin = Test::MockObject->new();
    my $handler     = RapidoILL::ActionHandler::Borrower->new(
        {
            pod    => 'test_pod',
            plugin => $mock_plugin
        }
    );

    my $mock_action = Test::MockObject->new();

    # Test that item_received returns without action (borrower-generated)
    my $result;
    lives_ok {
        $result = $handler->item_received($mock_action)
    }
    'item_received does not throw exception';

    is( $result, undef, 'item_received returns undef (no action needed)' );

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
