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
use Test::MockModule;
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

        # Setup real plugin with method mocking for external dependencies
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();

        # Mock only external API calls
        $mock_client->mock( 'borrower_receive_unshipped', sub { return; } );

        # Mock plugin methods that need external dependencies
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });
        $plugin_module->mock('add_virtual_record_and_item', sub {
            return $builder->build_object(
                {
                    class => 'Koha::Items',
                    value => { biblionumber => $biblio->biblionumber }
                }
            );
        });

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
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
                $illrequest,
                {
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

        # Test API failure with real plugin
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();

        # Mock plugin methods to simulate failure
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });
        $plugin_module->mock('add_virtual_record_and_item', sub { 
            die "Virtual record creation failed"; 
        });

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        throws_ok {
            $actions->borrower_receive_unshipped(
                $illrequest,
                {
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
    
    my $plugin; # Declare at test level to avoid masking warnings

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

        # Setup real plugin with method mocking for external calls
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_item_in_transit', sub { return; } );

        # Mock plugin methods that need external dependencies
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });
        $plugin_module->mock('add_return', sub { return; });

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->item_in_transit($illrequest);
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
        $mock_client->mock( 'borrower_item_in_transit', sub { die "API Error"; } );
        
        # Mock get_client method
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });

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
    
    my $plugin; # Declare at test level to avoid masking warnings
    my $actions; # Declare at test level to avoid masking warnings

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

        # Setup real plugin with method stubbing for external calls
        $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'borrower_cancel', sub { return; } );

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
        $plugin_module->mock('get_client', sub { return $mock_client; });

        my $actions = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->borrower_cancel($illrequest);
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
        $plugin_module->mock('get_client', sub { return $mock_client; });

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
