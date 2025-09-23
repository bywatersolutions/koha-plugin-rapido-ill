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

use Test::More tests => 8;
use Test::NoWarnings;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Logger;

use Koha::Database;
use Koha::DateUtils qw(dt_from_string);
use Koha::Holds;
use Koha::Old::Holds;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    use_ok('RapidoILL::Backend::LenderActions');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $logger  = t::lib::Mocks::Logger->new();

subtest 'new() tests' => sub {

    plan tests => 3;

    # Test successful construction
    my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $actions = RapidoILL::Backend::LenderActions->new(
        {
            pod    => 'test_pod',
            plugin => $plugin,
        }
    );

    isa_ok( $actions, 'RapidoILL::Backend::LenderActions' );
    is( $actions->{pod},    'test_pod', 'Pod stored correctly' );
    is( $actions->{plugin}, $plugin,    'Plugin stored correctly' );
};

subtest 'cancel_request() tests' => sub {

    plan tests => 4;

    subtest 'Successful calls' => sub {
        plan tests => 8;

        $schema->storage->txn_begin;

        # Setup test data
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
        my $item   = $builder->build_object(
            {
                class => 'Koha::Items',
                value => {
                    biblionumber => $biblio->biblionumber,
                    barcode      => 'TEST_ITEM_BARCODE'
                }
            }
        );

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

        # Create a real hold for testing cancellation
        my $hold = $builder->build_object(
            {
                class => 'Koha::Holds',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    biblionumber   => $biblio->biblionumber,
                }
            }
        );

        # Add required attributes using plugin method
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId     => 'test_circ_123',
                    patronName => 'Test Patron',
                    itemId     => $item->barcode,
                    hold_id    => $hold->id,
                }
            }
        );

        # Setup real plugin with method mocking for external calls
        my $mock_client = Test::MockObject->new();

        # Track API client method calls
        my @client_calls = ();
        $mock_client->mock(
            'lender_cancel',
            sub {
                my ( $self, $data, $options ) = @_;
                push @client_calls, {
                    method  => 'lender_cancel',
                    data    => $data,
                    options => $options
                };
                return;
            }
        );

        # Mock plugin methods that need external dependencies
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $plugin,
            }
        );

        my $client_options = { timeout => 60, force_cancel => 1 };

        my $result;
        lives_ok {
            $result = $actions->cancel_request( $illrequest, { client_options => $client_options } );
        }
        'cancel_request executes without error';

        # Verify API client method was called correctly
        is( scalar @client_calls,       1,               'API client method called once' );
        is( $client_calls[0]->{method}, 'lender_cancel', 'Correct API method called' );

        # Verify client_options were passed through
        my $call_options = $client_calls[0]->{options};
        is_deeply( $call_options->{timeout},      60, 'client_options timeout passed through' );
        is_deeply( $call_options->{force_cancel}, 1,  'client_options force_cancel passed through' );

        $illrequest->discard_changes();
        is( $illrequest->status, 'O_ITEM_CANCELLED_BY_US', 'Sets correct status' );

        # Verify hold was actually cancelled in database (moved to old_reserves)
        my $cancelled_hold = Koha::Old::Holds->find( $hold->id );
        ok( $cancelled_hold, 'Hold was cancelled and moved to old_reserves table' );

        is( $result, $actions, 'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Missing patronName attribute' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup test data without patronName attribute
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

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

        # Add attributes WITHOUT patronName
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId  => 'test_circ_123',
                    # patronName missing intentionally
                }
            }
        );

        # Mock client to avoid external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock('lender_cancel', sub { return; });
        
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });

        # DESIRED BEHAVIOR: Should succeed with warning instead of throwing exception
        my $result;
        lives_ok {
            $result = $plugin->get_lender_actions('test_pod')->cancel_request($illrequest);
        }
        'cancel_request succeeds when patronName attribute is missing';

        # Verify status was updated
        $illrequest->discard_changes();
        is( $illrequest->status, 'O_ITEM_CANCELLED_BY_US', 'Status updated despite missing patronName' );

        $schema->storage->txn_rollback;
    };

    subtest 'Missing hold_id attribute' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup test data without hold_id attribute
        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

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

        # Add attributes WITHOUT hold_id
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId     => 'test_circ_123',
                    patronName => 'Test Patron',
                    # hold_id missing intentionally
                }
            }
        );

        # Mock client to avoid external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock('lender_cancel', sub { return; });
        
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock('get_client', sub { return $mock_client; });

        # DESIRED BEHAVIOR: Should succeed with warning instead of throwing exception
        my $result;
        lives_ok {
            $result = $plugin->get_lender_actions('test_pod')->cancel_request($illrequest);
        }
        'cancel_request succeeds when hold_id attribute is missing';

        # Verify status was updated
        $illrequest->discard_changes();
        is( $illrequest->status, 'O_ITEM_CANCELLED_BY_US', 'Status updated despite missing hold_id' );

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

        # Add required attributes for the method to work
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId     => 'test_circ_123',
                    patronName => 'Test Patron',
                    hold_id    => '999999',          # Non-existent hold ID for error test
                }
            }
        );

        # Test API failure
        my $mock_plugin = Test::MockObject->new();
        my $mock_client = Test::MockObject->new();

        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_123'; } );
        $mock_plugin->mock( 'get_req_pod',     sub { return 'test_pod'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );

        $mock_client->mock( 'lender_cancel', sub { die "API Error"; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->cancel_request($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify status was not changed due to rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'item_shipped() tests' => sub {

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
                    barcode      => 'TEST_ITEM_BARCODE'
                }
            }
        );

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

        # Add required attributes using plugin method
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_123',
                    itemId => $item->barcode,
                }
            }
        );

        # Setup minimal mocking for external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'lender_shipped', sub { return; } );

        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_123'; } );
        $mock_plugin->mock( 'get_req_pod',     sub { return 'test_pod'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );
        $mock_plugin->mock(
            'add_issue',
            sub {
                return $builder->build_object(
                    {
                        class => 'Koha::Checkouts',
                        value => {
                            borrowernumber => $patron->borrowernumber,
                            itemnumber     => $item->id,
                        }
                    }
                );
            }
        );
        $mock_plugin->mock( 'add_or_update_attributes', sub { return; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->item_shipped($illrequest);
        }
        'item_shipped executes without error';

        $illrequest->discard_changes();
        is( $illrequest->status, 'O_ITEM_SHIPPED', 'Sets correct status' );
        is( $result,             $actions,         'Returns self for method chaining' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
        my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
        my $item   = $builder->build_object(
            {
                class => 'Koha::Items',
                value => {
                    biblionumber => $biblio->biblionumber,
                    barcode      => 'TEST_ITEM_BARCODE'
                }
            }
        );

        my $illrequest = $builder->build_object(
            {
                class => 'Koha::ILL::Requests',
                value => {
                    borrowernumber => $patron->borrowernumber,
                    status         => 'NEW',
                }
            }
        );

        # Add required attributes for the method to work
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_123',
                    itemId => $item->barcode,    # Use the real item barcode
                }
            }
        );

        # Test API failure
        my $mock_plugin = Test::MockObject->new();
        my $mock_client = Test::MockObject->new();

        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_123'; } );
        $mock_plugin->mock( 'get_req_pod',     sub { return 'test_pod'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );
        $mock_plugin->mock(
            'add_issue',
            sub {
                return $builder->build_object(
                    {
                        class => 'Koha::Checkouts',
                        value => {
                            borrowernumber => $patron->borrowernumber,
                            itemnumber     => $item->id,
                        }
                    }
                );
            }
        );
        $mock_plugin->mock( 'add_or_update_attributes', sub { return; } );

        $mock_client->mock( 'lender_shipped', sub { die "API Error"; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->item_shipped($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify status was not changed due to rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'final_checkin() tests' => sub {

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
                    status         => 'O_ITEM_SHIPPED',
                }
            }
        );

        # Add required attributes using plugin method
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->add_or_update_attributes(
            {
                request    => $illrequest,
                attributes => {
                    circId => 'test_circ_123',
                }
            }
        );

        # Setup minimal mocking for external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'lender_checkin', sub { return; } );

        my $mock_plugin = Test::MockObject->new();
        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_123'; } );
        $mock_plugin->mock( 'get_req_pod',     sub { return 'test_pod'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        my $result;
        lives_ok {
            $result = $actions->final_checkin($illrequest);
        }
        'final_checkin executes without error';

        $illrequest->discard_changes();
        is( $illrequest->status, 'COMP',   'Sets final status to COMP' );
        is( $result,             $actions, 'Returns self for method chaining' );

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

        $mock_plugin->mock( 'get_req_circ_id', sub { return 'test_circ_123'; } );
        $mock_plugin->mock( 'get_req_pod',     sub { return 'test_pod'; } );
        $mock_plugin->mock( 'get_client',      sub { return $mock_client; } );

        $mock_client->mock( 'lender_checkin', sub { die "API Error"; } );

        my $actions = RapidoILL::Backend::LenderActions->new(
            {
                pod    => 'test_pod',
                plugin => $mock_plugin,
            }
        );

        throws_ok {
            $actions->final_checkin($illrequest);
        }
        qr/API Error/, 'Throws exception on API failure';

        # Verify status was not changed due to rollback
        $illrequest->discard_changes();
        is( $illrequest->status, 'NEW', 'Status unchanged after transaction rollback' );

        $schema->storage->txn_rollback;
    };
};

subtest 'renewal_request() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    # Create test data
    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    my $pod = "test-pod";

    # Sample configuration for testing
    my $sample_config_yaml = <<'EOF';
---
%s:
  base_url: https://test-pod.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 12345
  partners_library_id: %s
  partners_category: %s
  default_item_type: %s
  default_patron_agency: test_agency
  dev_mode: true
EOF

    $sample_config_yaml = sprintf(
        $sample_config_yaml,
        $pod,
        $library->branchcode,
        $category->categorycode,
        $itemtype->itemtype
    );

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

    # Store configuration
    $plugin->store_data( { configuration => $sample_config_yaml } );

    # Create test data
    my $item     = $builder->build_sample_item( { itype => $itemtype->itemtype } );
    my $checkout = $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value => { itemnumber => $item->itemnumber }
        }
    );

    # Create a test ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                branchcode     => $library->branchcode,
                borrowernumber => $patron->borrowernumber,
                biblio_id      => $item->biblionumber,
                backend        => 'RapidoILL',
                status         => 'O_RENEWAL_REQUESTED',
            }
        }
    );

    # Add required attributes
    $plugin->add_or_update_attributes(
        {
            request    => $ill_request,
            attributes => {
                circId      => 'TEST_CIRC_001',
                pod         => 'test-pod',
                itemId      => $item->itemnumber,
                checkout_id => $checkout->id,
            }
        }
    );

    # Create backend instance
    lives_ok {
        $plugin->get_lender_actions($pod)->renewal_request(
            $ill_request,
            {
                approve        => 1,
                new_due_date   => dt_from_string('2025-12-31'),
                client_options => { skip_api_request => 1 }
            }
        );
    };

    # Verify status returned to O_ITEM_RECEIVED_DESTINATION
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_ITEM_RECEIVED_DESTINATION', 'Status returned to O_ITEM_RECEIVED_DESTINATION' );

    $schema->storage->txn_rollback;
};

subtest 'item_recalled() tests' => sub {

    plan tests => 2;

    # Sample configuration for testing
    my $sample_config_yaml = <<'EOF';
test-pod:
  base_url: https://test.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 12345
  partners_library_id: TEST
  dev_mode: true
EOF

    subtest 'Successful calls' => sub {

        plan tests => 3;

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

        # Add required attributes
        $builder->build_object(
            {
                class => 'Koha::ILL::Request::Attributes',
                value => {
                    illrequest_id => $ill_request->id,
                    type          => 'circId',
                    value         => 'test-circ-123',
                }
            }
        );

        # Mock client to avoid external calls
        my $mock_client = Test::MockObject->new();
        $mock_client->mock( 'lender_recall', sub { return; } );

        # Mock plugin methods before instantiation
        my $plugin_module = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
        $plugin_module->mock( 'get_client', sub { return $mock_client; } );

        # Create plugin instance
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->store_data( { configuration => $sample_config_yaml } );

        # Test successful item recall
        my $recall_due_date = dt_from_string('2025-12-31');

        $logger->clear();

        lives_ok {
            $plugin->get_lender_actions('test-pod')->item_recalled(
                $ill_request,
                {
                    recall_due_date => $recall_due_date,
                    client_options  => { skip_api_request => 1 }
                }
            );
        } 'item_recalled executes without error';

        # Verify status change
        $ill_request->discard_changes;
        is( $ill_request->status, 'O_ITEM_RECALLED', 'Status updated to O_ITEM_RECALLED' );

        # Verify client method was called with correct parameters
        my ( $method, $args ) = $mock_client->next_call();
        is( $method, 'lender_recall', 'lender_recall method called on client' );

        $schema->storage->txn_rollback;
    };

    subtest 'Error cases' => sub {

        plan tests => 1;

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

        # Create plugin instance
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        $plugin->store_data( { configuration => $sample_config_yaml } );

        # Test missing recall_due_date parameter
        throws_ok {
            $plugin->get_lender_actions('test-pod')->item_recalled( $ill_request, {} );
        } 'RapidoILL::Exception::MissingParameter', 'Throws exception when recall_due_date is missing';

        $schema->storage->txn_rollback;
    };
};
