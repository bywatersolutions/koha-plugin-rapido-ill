#!/usr/bin/perl

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
# along with The Rapido ILL plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 3;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;

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
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
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
        my $mock_lender_actions = Test::MockObject->new();
        $mock_lender_actions->mock(
            'item_shipped',
            sub {
                my ( $self, $request, $params ) = @_;
                $lender_actions_called = 1;
                return $self;  # Return self for chaining
            }
        );

        # Mock plugin to return our mock LenderActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod', sub { return 'test_pod'; } );

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
        is( ref($result), 'HASH', 'Returns hash structure' );
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
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod', sub { return 'test_pod'; } );

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
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
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
        my $mock_lender_actions = Test::MockObject->new();
        $mock_lender_actions->mock(
            'final_checkin',
            sub {
                my ( $self, $request, $params ) = @_;
                $lender_actions_called = 1;
                return $self;  # Return self for chaining
            }
        );

        # Mock plugin to return our mock LenderActions
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod', sub { return 'test_pod'; } );

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
        is( ref($result), 'HASH', 'Returns hash structure' );
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
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_lender_actions', sub { return $mock_lender_actions; } );
        $plugin_module->mock( 'get_req_pod', sub { return 'test_pod'; } );

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
