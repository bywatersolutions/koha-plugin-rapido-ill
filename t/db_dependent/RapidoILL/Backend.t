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

use Test::More tests => 8;
use Test::NoWarnings;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;
use JSON qw( encode_json );

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Database;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    use_ok('RapidoILL::Backend');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'item_shipped() tests' => sub {

    plan tests => 2;

    subtest 'Successful delegation to LenderActions' => sub {
        plan tests => 4;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
        my $item   = $builder->build_object(
            {
                class => 'Koha::Items',
                value => {
                    biblionumber => $biblio->biblionumber,
                    barcode      => 'TEST_BACKEND_ITEM'
                }
            }
        );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'O_ITEM_REQUESTED',
                }
            }
        );

        # Add required attributes
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_456',
                    pod    => 'test_pod',
                    itemId => $item->barcode,
                }
            }
        );

        # Mock LenderActions to track delegation
        my $lender_actions_called = 0;
        my $mock_lender_actions   = Test::MockObject->new();
        $mock_lender_actions->mock(
            'item_shipped',
            sub {
                my ( $self, $request, $params ) = @_;
                $lender_actions_called = 1;
                return $self;    # Return self for chaining
            }
        );

        # Mock plugin to return our mock LenderActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod',        sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test delegation - this should call LenderActions->item_shipped()
        my $result;
        lives_ok {
            $result = $backend->item_shipped( { request => $illrequest } );
        }
        'Backend item_shipped executes without error';

        # Verify delegation occurred
        is( $lender_actions_called, 1, 'LenderActions->item_shipped was called' );

        # Verify return structure matches expected Backend format
        is( ref($result),      'HASH',         'Returns hash structure' );
        is( $result->{method}, 'item_shipped', 'Returns correct method name' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error handling delegation' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup minimal test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'O_ITEM_REQUESTED',
                }
            }
        );

        # Mock LenderActions to throw exception
        my $mock_lender_actions = Test::MockObject->new();
        $mock_lender_actions->mock(
            'item_shipped',
            sub {
                die "LenderActions error";
            }
        );

        # Mock plugin
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod',        sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test error handling
        my $result;
        lives_ok {
            $result = $backend->item_shipped( { request => $illrequest } );
        }
        'Backend item_shipped handles LenderActions errors gracefully';

        # Verify error response structure
        is( $result->{error}, 1, 'Returns error status when LenderActions fails' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_checkin() tests' => sub {

    plan tests => 2;

    subtest 'Successful delegation to LenderActions' => sub {
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
                    status         => 'O_ITEM_IN_TRANSIT',
                }
            }
        );

        # Add required attributes
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_789',
                    pod    => 'test_pod',
                }
            }
        );

        # Mock LenderActions to track delegation
        my $lender_actions_called = 0;
        my $mock_lender_actions   = Test::MockObject->new();
        $mock_lender_actions->mock(
            'final_checkin',
            sub {
                my ( $self, $request, $params ) = @_;
                $lender_actions_called = 1;
                return $self;    # Return self for chaining
            }
        );

        # Mock plugin to return our mock LenderActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod',        sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test delegation - this should call LenderActions->final_checkin()
        my $result;
        lives_ok {
            $result = $backend->item_checkin( { request => $illrequest } );
        }
        'Backend item_checkin executes without error';

        # Verify delegation occurred
        is( $lender_actions_called, 1, 'LenderActions->final_checkin was called' );

        # Verify return structure matches expected Backend format
        is( ref($result),      'HASH',         'Returns hash structure' );
        is( $result->{method}, 'item_checkin', 'Returns correct method name' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error handling delegation' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup minimal test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'O_ITEM_IN_TRANSIT',
                }
            }
        );

        # Mock LenderActions to throw exception
        my $mock_lender_actions = Test::MockObject->new();
        $mock_lender_actions->mock(
            'final_checkin',
            sub {
                die "LenderActions error";
            }
        );

        # Mock plugin
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod',        sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test error handling
        my $result;
        lives_ok {
            $result = $backend->item_checkin( { request => $illrequest } );
        }
        'Backend item_checkin handles LenderActions errors gracefully';

        # Verify error response structure
        is( $result->{error}, 1, 'Returns error status when LenderActions fails' );

        $schema->storage->txn_rollback;
    };
};
subtest 'item_received() delegation tests' => sub {

    plan tests => 2;

    subtest 'Successful delegation to BorrowerActions' => sub {
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
                    status         => 'B_ITEM_SHIPPED',
                }
            }
        );

        # Add required attributes
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_received_789',
                    pod    => 'test_pod',
                }
            }
        );

        # Mock BorrowerActions to track delegation
        my $borrower_actions_called = 0;
        my $mock_borrower_actions   = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'item_received',
            sub {
                my ( $self, $request, $params ) = @_;
                $borrower_actions_called = 1;
                return $self;    # Return self for chaining
            }
        );

        # Mock plugin to return our mock BorrowerActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );
        $plugin_module->mock( 'get_req_pod',          sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test delegation - this should call BorrowerActions->item_received()
        my $result;
        lives_ok {
            $result = $backend->item_received( { request => $illrequest } );
        }
        'Backend item_received executes without error';

        # Verify delegation occurred
        is( $borrower_actions_called, 1, 'BorrowerActions->item_received was called' );

        # Verify return structure matches expected Backend format
        is( ref($result),      'HASH',          'Returns hash structure' );
        is( $result->{method}, 'item_received', 'Returns correct method name' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error handling delegation' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup minimal test data
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

        # Mock BorrowerActions to throw exception
        my $mock_borrower_actions = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'item_received',
            sub {
                die "BorrowerActions error";
            }
        );

        # Mock plugin
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );
        $plugin_module->mock( 'get_req_pod',          sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test error handling
        my $result;
        lives_ok {
            $result = $backend->item_received( { request => $illrequest } );
        }
        'Backend item_received handles BorrowerActions errors gracefully';

        # Verify error response structure
        is( $result->{error}, 1, 'Returns error status when BorrowerActions fails' );

        $schema->storage->txn_rollback;
    };
};
subtest 'return_uncirculated() delegation tests' => sub {

    plan tests => 2;

    subtest 'Successful delegation to BorrowerActions' => sub {
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
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_return_999',
                    pod    => 'test_pod',
                }
            }
        );

        # Mock BorrowerActions to track delegation
        my $borrower_actions_called = 0;
        my $mock_borrower_actions   = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'return_uncirculated',
            sub {
                my ( $self, $request, $params ) = @_;
                $borrower_actions_called = 1;
                return $self;    # Return self for chaining
            }
        );

        # Mock plugin to return our mock BorrowerActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );
        $plugin_module->mock( 'get_req_pod',          sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test delegation - this should call BorrowerActions->return_uncirculated()
        my $result;
        lives_ok {
            $result = $backend->return_uncirculated( { request => $illrequest } );
        }
        'Backend return_uncirculated executes without error';

        # Verify delegation occurred
        is( $borrower_actions_called, 1, 'BorrowerActions->return_uncirculated was called' );

        # Verify return structure matches expected Backend format
        is( ref($result),      'HASH',                'Returns hash structure' );
        is( $result->{method}, 'return_uncirculated', 'Returns correct method name' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error handling delegation' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup minimal test data
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

        # Mock BorrowerActions to throw exception
        my $mock_borrower_actions = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'return_uncirculated',
            sub {
                die "BorrowerActions error";
            }
        );

        # Mock plugin
        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );
        $plugin_module->mock( 'get_req_pod',          sub { return 'test_pod'; } );

        # Create Backend instance
        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        # Test error handling
        my $result;
        lives_ok {
            $result = $backend->return_uncirculated( { request => $illrequest } );
        }
        'Backend return_uncirculated handles BorrowerActions errors gracefully';

        # Verify error response structure
        is( $result->{error}, 1, 'Returns error status when BorrowerActions fails' );

        $schema->storage->txn_rollback;
    };
};

subtest 'receive_unshipped() tests' => sub {

    plan tests => 3;

    subtest 'Rapido API is called with correct circId' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

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

        my $test_circ_id = 'test_circ_receive_unshipped';

        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => $test_circ_id,
                    pod    => t::lib::Mocks::Rapido::POD,
                }
            }
        );

        # Mock client to track API calls
        my $mock_client  = Test::MockObject->new();
        my @client_calls = ();
        $mock_client->mock(
            'borrower_receive_unshipped',
            sub {
                my ( $self, $data, $options ) = @_;
                push @client_calls, {
                    data    => $data,
                    options => $options,
                };
                return;
            }
        );

        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client',   sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        my $result = $backend->receive_unshipped(
            {
                request => $illrequest,
                other   => {
                    stage           => 'confirm',
                    item_callnumber => 'TEST 123',
                    item_barcode    => 'BC_' . time(),
                }
            }
        );

        is( $result->{error}, 0, 'receive_unshipped completed successfully' );
        is( scalar @client_calls, 1, 'Rapido /receiveunshipped API was called' );
        is( $client_calls[0]->{data}->{circId}, $test_circ_id, 'circId passed correctly to API' );

        $schema->storage->txn_rollback;
    };

    subtest 'Rapido API receives circId, not empty hash' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

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

        my $test_circ_id = 'test_circ_empty_hash_check';

        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => $test_circ_id,
                    pod    => t::lib::Mocks::Rapido::POD,
                }
            }
        );

        # Mock client - verify data param is not empty
        my $mock_client = Test::MockObject->new();
        my $received_data;
        $mock_client->mock(
            'borrower_receive_unshipped',
            sub {
                my ( $self, $data, $options ) = @_;
                $received_data = $data;
                return;
            }
        );

        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client',   sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        $backend->receive_unshipped(
            {
                request => $illrequest,
                other   => {
                    stage           => 'confirm',
                    item_callnumber => 'TEST 456',
                    item_barcode    => 'BC2_' . time(),
                }
            }
        );

        ok( defined $received_data && keys %{$received_data}, 'API data param is not empty' );
        is( $received_data->{circId}, $test_circ_id, 'circId is present in API data' );

        $schema->storage->txn_rollback;
    };

    subtest 'Stores itemBarcode and callNumber attributes with correct keys' => sub {
        plan tests => 4;

        $schema->storage->txn_begin;

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

        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_barcode_attr',
                    pod    => t::lib::Mocks::Rapido::POD,
                }
            }
        );

        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_receive_unshipped', sub { return; } );

        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client',   sub { return $mock_client; } );
        $plugin_module->mock( 'validate_pod', sub { return 1; } );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        my $sample_item     = $builder->build_sample_item();
        my $test_barcode    = $sample_item->barcode;
        $sample_item->delete;
        my $test_callnumber = 'QA 999';

        $backend->receive_unshipped(
            {
                request => $illrequest,
                other   => {
                    stage           => 'confirm',
                    item_callnumber => $test_callnumber,
                    item_barcode    => $test_barcode,
                }
            }
        );

        # Regression: receive_unshipped was storing 'barcode' instead of 'itemBarcode'
        my $item_barcode_attr = $illrequest->extended_attributes->find( { type => 'itemBarcode' } );
        ok( $item_barcode_attr, 'itemBarcode attribute exists (not stored as barcode)' );
        is( $item_barcode_attr->value, $test_barcode, 'itemBarcode attribute has correct value' )
            if $item_barcode_attr;

        # Regression: receive_unshipped was storing 'callnumber' instead of 'callNumber'
        my $call_number_attr = $illrequest->extended_attributes->find( { type => 'callNumber' } );
        ok( $call_number_attr, 'callNumber attribute exists (not stored as callnumber)' );
        is( $call_number_attr->value, $test_callnumber, 'callNumber attribute has correct value' )
            if $call_number_attr;

        $schema->storage->txn_rollback;
    };
};

subtest 'borrower_cancel() force cancel tests' => sub {

    plan tests => 3;

    subtest 'Force cancel parameter' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

        my $result = $backend->borrower_cancel(
            {
                request => $illrequest,
                other   => { force_cancel => 1 }
            }
        );

        is( $result->{method}, 'illview', 'Returns illview method' );
        is( $result->{stage},  'commit',  'Returns commit stage' );

        $illrequest->discard_changes;
        is( $illrequest->status, 'B_ITEM_CANCELLED_BY_US', 'Status updated to cancelled' );

        $schema->storage->txn_rollback;
    };

    subtest 'Returns allow_force on 400 error' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => { circId => 'test_circ_123', pod => 'test_pod' }
            }
        );

        # Mock get_borrower_actions to return a mock that throws the exception
        my $mock_borrower_actions = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'borrower_cancel',
            sub {
                RapidoILL::Exception::RequestFailed->throw(
                    method        => 'borrower_cancel',
                    status_code   => 400,
                    status_message => 'Bad Request',
                    response_body => encode_json( { error => "No circulation request processable request was found" } )
                );
            }
        );

        my $plugin_module = Test::MockModule->new( ref($plugin) );
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );
        my $result = $backend->borrower_cancel( { request => $illrequest } );

        is( $result->{stage},              'form', 'Returns form stage' );
        is( $result->{value}->{allow_force}, 1,      'Returns allow_force flag in value' );
        like( $result->{message}, qr/may have already been cancelled/, 'Message indicates possible cancellation' );

        $schema->storage->txn_rollback;
    };

    subtest 'No allow_force on other errors' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'B_ITEM_REQUESTED',
                }
            }
        );

        my $library  = $builder->build_object( { class => "Koha::Libraries" } );
        my $category = $builder->build_object( { class => "Koha::Patron::Categories" } );
        my $itemtype = $builder->build_object( { class => "Koha::ItemTypes" } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => { circId => 'test_circ_123', pod => 'test_pod' }
            }
        );

        # Mock get_borrower_actions to return a mock that throws a different exception
        my $mock_borrower_actions = Test::MockObject->new();
        $mock_borrower_actions->mock(
            'borrower_cancel',
            sub {
                RapidoILL::Exception::RequestFailed->throw(
                    method        => 'borrower_cancel',
                    status_code   => 500,
                    status_message => 'Internal Server Error',
                    response_body => 'Server error'
                );
            }
        );

        my $plugin_module = Test::MockModule->new( ref($plugin) );
        $plugin_module->mock( 'get_borrower_actions', sub { return $mock_borrower_actions; } );

        my $backend = RapidoILL::Backend->new( { plugin => $plugin } );
        my $result = $backend->borrower_cancel( { request => $illrequest } );

        is( $result->{stage},              'form', 'Returns form stage for other errors too' );
        is( $result->{value}->{allow_force}, 0, 'Does not return allow_force flag for other errors' );
        ok( $result->{value}->{error_message}, 'Returns error_message in value' );

        $schema->storage->txn_rollback;
    };
};
