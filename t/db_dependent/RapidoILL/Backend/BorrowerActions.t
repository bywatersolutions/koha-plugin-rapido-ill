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

use Test::More tests => 5;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    use_ok('RapidoILL::Backend::BorrowerActions');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

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

    plan tests => 2;

    subtest 'Successful calls' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron     = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio     = $builder->build_object( { class => 'Koha::Biblios' } );
        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblio_id      => $biblio->biblionumber,
                    status         => 'NEW',
                }
            }
        );

        # Setup plugin with minimal mocking
        my $plugin      = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();

        # Mock only external API calls
        $mock_client->mock( 'borrower_receive_unshipped', sub { return; } );

        # Mock plugin methods that need external dependencies
        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock( 'configuration', sub { return { test_pod => {} }; } );
        $mock_plugin->mock( 'get_client',    sub { return $mock_client; } );
        $mock_plugin->mock(
            'add_virtual_record_and_item',
            sub {
                return $builder->build_object(
                    {
                        class => 'Koha::Items',
                        value => { biblionumber => $biblio->biblionumber }
                    }
                );
            }
        );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        my $attributes = {
            title   => 'Test Book',
            author  => 'Test Author',
            barcode => 'TEST_BARCODE_456'
        };

        my $result;
        lives_ok {
            $result = $actions->borrower_receive_unshipped(
                {
                    request    => $illrequest,
                    circId     => 'test_circ_456',
                    attributes => $attributes,
                    barcode    => 'TEST_BARCODE_456'
                }
            );
        }
        'borrower_receive_unshipped executes without error';

        $illrequest->discard_changes();
        is( $illrequest->status, 'B_ITEM_RECEIVED', 'Sets correct status' );
        is( $result,             $actions,          'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

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

        # Test API failure
        my $mock_plugin = Test::MockObject->new();
        my $mock_client = Test::MockObject->new();

        $mock_plugin->mock( 'configuration',               sub { return { test_pod => {} }; } );
        $mock_plugin->mock( 'get_client',                  sub { return $mock_client; } );
        $mock_plugin->mock( 'add_virtual_record_and_item', sub { die "Virtual record creation failed"; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->borrower_receive_unshipped(
                {
                    request    => $illrequest,
                    circId     => 'test_circ_456',
                    attributes => { title => 'Test' },
                    barcode    => 'TEST_BARCODE'
                }
            );
        }
        qr/Virtual record creation failed/, 'Throws exception on virtual record creation failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_in_transit() tests' => sub {

    plan tests => 2;

    subtest 'Successful calls' => sub {
        plan tests => 3;

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

        # Setup minimal mocking for external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_item_in_transit', sub { return; } );

        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock( 'validate_params', sub { return; } );
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_456'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );
        $mock_plugin->mock( 'add_return',      sub { return; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->item_in_transit( { request => $illrequest } );
        }
        'item_in_transit executes without error';

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

        # Test parameter validation failure
        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock(
            'validate_params',
            sub {
                die "Missing required parameter: request";
            }
        );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->item_in_transit( {} );
        }
        qr/Missing required parameter/, 'Validates parameters correctly';

        # Test API failure
        $mock_plugin->mock( 'validate_params', sub { return; } );
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_456'; } );

        # Add required attributes for the method to work
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
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
        $mock_client->mock( 'borrower_item_in_transit', sub { die "API Error"; } );
        $mock_plugin->mock( 'get_client',               sub { return $mock_client; } );

        throws_ok {
            $actions->item_in_transit( { request => $illrequest } );
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

    subtest 'Successful calls' => sub {
        plan tests => 3;

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

        # Setup minimal mocking for external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_cancel', sub { return; } );

        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock( 'validate_params', sub { return; } );
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_456'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->borrower_cancel( { request => $illrequest } );
        }
        'borrower_cancel executes without error';

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

        # Test parameter validation failure
        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock(
            'validate_params',
            sub {
                die "Missing required parameter: request";
            }
        );

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->borrower_cancel( {} );
        }
        qr/Missing required parameter/, 'Validates parameters correctly';

        # Test API failure
        $mock_plugin->mock( 'validate_params', sub { return; } );
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_456'; } );

        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_cancel', sub { die "API Error"; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );

        throws_ok {
            $actions->borrower_cancel( { request => $illrequest } );
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify transaction rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};
