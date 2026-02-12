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

use Test::More tests => 9;
use Test::NoWarnings;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Database;
use Koha::DateUtils qw( dt_from_string );

use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    use_ok('RapidoILL::Backend::BorrowerActions');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Default pod in the mocked plugin
my $pod = t::lib::Mocks::Rapido::POD;

$schema->storage->txn_begin;

subtest 'new() tests' => sub {

    plan tests => 3;

    # Test successful construction
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $actions = RapidoILL::Backend::BorrowerActions->new(
        {
            pod    => 'test_pod',
            plugin => $plugin,
        }
    );

    isa_ok( $actions, 'RapidoILL::Backend::BorrowerActions' );
    is( $actions->{pod},    'test_pod', 'Pod stored correctly' );
    is( $actions->{plugin}, $plugin,    'Plugin stored correctly' );
};

subtest 'borrower_receive_unshipped() tests' => sub {

    plan tests => 3;

    subtest 'Successful calls with hold and attribute creation' => sub {
        plan tests => 8;

        $schema->storage->txn_begin;

        # Test data constants
        my $test_barcode    = 'TEST_BARCODE_001';
        my $test_callnumber = 'TEST 123.45 ABC';
        my $test_circ_id    = 'test_circ_456';

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

        my $patron = $builder->build_object(
            {
                class => 'Koha::Patrons',
                value => { branchcode => $library->branchcode }
            }
        );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    backend        => 'RapidoILL',
                    status         => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $actions = $plugin->get_borrower_actions($pod);

        my $result;
        lives_ok {
            $result = $actions->borrower_receive_unshipped(
                $illrequest,
                {
                    circId     => $test_circ_id,
                    attributes => { callNumber => $test_callnumber },
                    barcode    => $test_barcode,
                }
            );
        }
        'borrower_receive_unshipped executes without error';

        # Verify status and biblio
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RECEIVED', 'Sets correct status' );
        ok( $illrequest->biblio_id, 'Biblio ID is set' );

        # Verify hold was created
        my $holds = Koha::Holds->search( { borrowernumber => $patron->borrowernumber } );
        is( $holds->count, 1, 'Hold was created for patron' );

        my $hold = $holds->next;
        is( $hold->biblionumber, $illrequest->biblio_id, 'Hold is for correct biblio' );

        # Verify attributes were stored including hold_id
        my $attributes   = $illrequest->extended_attributes;
        my $hold_id_attr = $attributes->search( { type => 'hold_id' } )->next;
        ok( $hold_id_attr, 'hold_id attribute was stored' );
        is( $hold_id_attr->value, $hold->id, 'hold_id attribute has correct value' );

        is( $result, $actions, 'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Barcode collision handling' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        # Test data constants
        my $collision_barcode = 'COLLISION_BARCODE';
        my $test_callnumber   = 'TEST 456.78 DEF';
        my $test_circ_id      = 'test_circ_collision';

        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        # Create existing item with collision barcode
        my $existing_item = $builder->build_sample_item( { barcode => $collision_barcode } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
            }
        );

        my $patron = $builder->build_object(
            {
                class => 'Koha::Patrons',
                value => { branchcode => $library->branchcode }
            }
        );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    branchcode     => $library->branchcode,
                    backend        => 'RapidoILL',
                    status         => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $actions = $plugin->get_borrower_actions($pod);

        lives_ok {
            $actions->borrower_receive_unshipped(
                $illrequest,
                {
                    circId     => $test_circ_id,
                    attributes => { callNumber => $test_callnumber },
                    barcode    => $collision_barcode,
                }
            );
        }
        'borrower_receive_unshipped handles barcode collision';

        # Verify new item was created with modified barcode
        $illrequest->discard_changes();
        my $new_item = Koha::Items->find( { biblionumber => $illrequest->biblio_id } );
        like( $new_item->barcode, qr/\Q$collision_barcode\E-\d+/, 'New item has modified barcode to avoid collision' );

        # Verify barcode_collision attribute was set
        my $collision_attr = $illrequest->extended_attributes->search( { type => 'barcode_collision' } )->next;
        ok( $collision_attr, 'barcode_collision attribute was set' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Test data constants
        my $test_callnumber = 'TEST 789.01 GHI';
        my $test_circ_id    = 'test_circ_error';

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

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    backend => 'RapidoILL',
                    status  => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $actions = $plugin->get_borrower_actions($pod);

        throws_ok {
            $actions->borrower_receive_unshipped(
                $illrequest,
                {
                    circId     => $test_circ_id,
                    attributes => { callNumber => $test_callnumber },
                    barcode    => undef,
                }
            );
        }
        qr/No barcode in request/, 'Throws exception on missing barcode';

        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_REQUESTED', 'Status unchanged after error' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_in_transit() tests' => sub {

    plan tests => 2;

    my $plugin;    # Declare at test level to avoid masking warnings

    subtest 'Successful calls' => sub {
        plan tests => 7;

        $schema->storage->txn_begin;

        # Setup test data
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

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_RECEIVED',
                }
            }
        );

        # Add required attributes using plugin method
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId      => 'test_circ_456',
                    itemBarcode => $item->barcode,
                }
            }
        );

        # Setup real plugin with method mocking for external calls
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();

        # Track API client method calls
        my @client_calls = ();
        $mock_client->mock(
            'borrower_item_returned',
            sub {
                my ( $self, $data, $options ) = @_;
                push @client_calls, {
                    method  => 'borrower_item_returned',
                    data    => $data,
                    options => $options
                };
                return;
            }
        );

        # Mock plugin methods that need external dependencies
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );
        $plugin_module->mock( 'add_return', sub { return; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        my $client_options = { timeout => 45, notify_rapido => 1 };

        my $result;
        lives_ok {
            $result = $actions->item_in_transit( $illrequest, { client_options => $client_options } );
        }
        'item_in_transit executes without error';

        # Verify API client method was called correctly
        is( scalar @client_calls,       1,                        'API client method called once' );
        is( $client_calls[0]->{method}, 'borrower_item_returned', 'Correct API method called' );

        # Verify client_options were passed through
        my $call_options = $client_calls[0]->{options};
        is_deeply( $call_options->{timeout},       45, 'client_options timeout passed through' );
        is_deeply( $call_options->{notify_rapido}, 1,  'client_options notify_rapido passed through' );

        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_IN_TRANSIT', 'Sets correct status' );
        is( $result,             $actions,            'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $patron     = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'NEW',
                }
            }
        );

        # Test parameter validation failure with real plugin
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        throws_ok {
            $actions->item_in_transit(undef);
        }
        qr/Can't call method/, 'Handles missing request parameter';

        # Test API failure with real plugin
        # Add required attributes for the method to work
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId      => 'test_circ_456',
                    itemBarcode => 'TEST_BARCODE',
                }
            }
        );

        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_item_returned', sub { die "API Error"; } );

        # Mock get_client method
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );

        $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        throws_ok {
            $actions->item_in_transit($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'borrower_cancel() tests' => sub {

    plan tests => 2;

    my $plugin;     # Declare at test level to avoid masking warnings
    my $actions;    # Declare at test level to avoid masking warnings

    subtest 'Successful calls' => sub {
        plan tests => 7;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron     = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'NEW',
                }
            }
        );

        # Setup real plugin with method stubbing for external calls
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();

        # Track API client method calls
        my @client_calls = ();
        $mock_client->mock(
            'borrower_cancel',
            sub {
                my ( $self, $data, $options ) = @_;
                push @client_calls, {
                    method  => 'borrower_cancel',
                    data    => $data,
                    options => $options
                };
                return;
            }
        );

        # Add required attributes for the method to work
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_456',
                }
            }
        );

        # Mock get_client method
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        my $client_options = { force_cancel => 1, reason => 'patron_request' };

        my $result;
        lives_ok {
            $result = $actions->borrower_cancel( $illrequest, { client_options => $client_options } );
        }
        'borrower_cancel executes without error';

        # Verify API client method was called correctly
        is( scalar @client_calls,       1,                 'API client method called once' );
        is( $client_calls[0]->{method}, 'borrower_cancel', 'Correct API method called' );

        # Verify client_options were passed through
        my $call_options = $client_calls[0]->{options};
        is_deeply( $call_options->{force_cancel}, 1,                'client_options force_cancel passed through' );
        is_deeply( $call_options->{reason},       'patron_request', 'client_options reason passed through' );

        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_CANCELLED_BY_US', 'Sets correct status' );
        is( $result,             $actions,                 'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $patron     = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'NEW',
                }
            }
        );

        # Test parameter validation failure with real plugin
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        throws_ok {
            $actions->borrower_cancel(undef);
        }
        qr/Can't call method/, 'Handles missing request parameter';

        # Test API failure with real plugin
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_456',
                }
            }
        );

        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_cancel', sub { die "API Error"; } );

        # Mock get_client method
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );

        throws_ok {
            $actions->borrower_cancel($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'borrower_renew() tests' => sub {

    plan tests => 2;

    subtest 'Successful calls' => sub {

        plan tests => 8;

        $schema->storage->txn_begin;

        # Mock client to capture the dueDateTime parameter
        my $captured_params;
        my $mock_client = Test::MockObject->new();
        $mock_client->mock(
            'borrower_renew',
            sub {
                my ( $self, $params ) = @_;
                $captured_params = $params;
                return;
            }
        );

        # Mock plugin methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client',      sub { return $mock_client; } );
        $plugin_module->mock( 'get_req_circ_id', sub { return 'TEST_CIRC_ID'; } );

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

        my $checkout = $builder->build_object(
            {
                class => 'Koha::Checkouts',
                value => { note => undef }
            }
        );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    backend  => 'RapidoILL',
                    status   => 'B_ITEM_RECEIVED',
                    due_date => '2025-09-01 23:59:59'    # Set initial due date
                }
            }
        );

        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    checkout_id => $checkout->id,
                }
            }
        );

        my $actions = $plugin->get_borrower_actions($pod);

        # Test with a due date string
        my $due_date = '2025-09-15';
        lives_ok {
            $actions->borrower_renew( $illrequest, { due_date => $due_date } );
        }
        'borrower_renew executes without error';

        my $config = $plugin->pod_config($pod);

        # Reload checkout object from DB
        $checkout->discard_changes;
        is( $checkout->note, $config->{renewal_request_note}, 'Checkout note stored on renewal' );
        isnt( $checkout->notedate, undef, 'Checkout note stored on renewal' );
        ok( !$checkout->noteseen, 'The note is not marked as seen by default' );

        # Verify API client method was called
        is( $mock_client->call_pos(1), 'borrower_renew', 'Correct API method called' );

        # Verify parameters passed to client
        ok( $captured_params, 'Parameters captured from client call' );
        is( $captured_params->{circId}, 'TEST_CIRC_ID', 'Correct circId passed' );

        # Verify status was updated
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RENEWAL_REQUESTED', 'Sets correct status' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    backend => 'RapidoILL',
                    status  => 'B_ITEM_RECEIVED'
                }
            }
        );

        # Mock client to throw error
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_renew', sub { die "API Error"; } );

        # Mock plugin methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client',      sub { return $mock_client; } );
        $plugin_module->mock( 'get_req_circ_id', sub { return 'TEST_CIRC_ID'; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new()
            }
        );

        throws_ok {
            $actions->borrower_renew( $illrequest, { due_date => '2025-09-15' } );
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RECEIVED', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_received() tests' => sub {

    plan tests => 2;

    subtest 'Successful calls' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Add required attributes
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_received_123',
                }
            }
        );

        # Mock client to avoid external calls
        my $mock_client  = Test::MockObject->new();
        my @client_calls = ();
        $mock_client->mock(
            'borrower_item_received',
            sub {
                my ( $self, $data ) = @_;
                push @client_calls, {
                    method => 'borrower_item_received',
                    data   => $data
                };
                return;
            }
        );

        # Mock plugin get_client and validate_pod methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        my $result;
        lives_ok {
            $result = $plugin->get_borrower_actions('test_pod')->item_received($illrequest);
        }
        'item_received executes without error';

        # Verify status was updated
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RECEIVED', 'Sets correct status' );

        # Verify API client method was called correctly
        is( scalar @client_calls, 1, 'API client method called once' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Add required attributes
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_received_456',
                }
            }
        );

        # Mock client to throw exception
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_item_received', sub { die "API Error"; } );

        # Mock plugin get_client and validate_pod methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        throws_ok {
            $plugin->get_borrower_actions('test_pod')->item_received($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_SHIPPED', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};
subtest 'return_uncirculated() tests' => sub {

    plan tests => 2;

    subtest 'Successful calls' => sub {
        plan tests => 4;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_IN_TRANSIT',
                }
            }
        );

        # Add required attributes
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_return_123',
                }
            }
        );

        # Mock client to avoid external calls
        my $mock_client  = Test::MockObject->new();
        my @client_calls = ();
        $mock_client->mock(
            'borrower_return_uncirculated',
            sub {
                my ( $self, $data ) = @_;
                push @client_calls, {
                    method => 'borrower_return_uncirculated',
                    data   => $data
                };
                return;
            }
        );

        # Mock plugin get_client and validate_pod methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        my $result;
        lives_ok {
            $result = $plugin->get_borrower_actions('test_pod')->return_uncirculated($illrequest);
        }
        'return_uncirculated executes without error';

        # Verify status was updated
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RETURN_UNCIRCULATED', 'Sets correct status' );

        # Verify API client method was called correctly
        is( scalar @client_calls, 1, 'API client method called once' );

        # Verify biblio cleanup occurred (biblio should be deleted)
        my $biblio_exists = Koha::Biblios->find( $biblio->biblionumber );
        is( $biblio_exists, undef, 'Biblio was deleted during cleanup' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'B_ITEM_IN_TRANSIT',
                }
            }
        );

        # Add required attributes
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_return_456',
                }
            }
        );

        # Mock client to throw exception
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_return_uncirculated', sub { die "API Error"; } );

        # Mock plugin get_client and validate_pod methods
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        throws_ok {
            $plugin->get_borrower_actions('test_pod')->return_uncirculated($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_IN_TRANSIT', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

$schema->storage->txn_rollback;
