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

use Test::More tests => 4;
use Test::Exception;
use Test::MockModule;

use t::lib::TestBuilder;
use t::lib::Mocks;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    use_ok('RapidoILL::ActionHandler::Lender');
    use_ok('RapidoILL::CircAction');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;

# Enable ILL module for testing
t::lib::Mocks::mock_preference( 'ILLModule', 1 );

# Create test data
my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

# Sample configuration for testing
my $sample_config_yaml = <<'EOF';
---
test-pod:
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
    $library->branchcode,
    $category->categorycode,
    $itemtype->itemtype
);

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

# Store configuration
$plugin->store_data( { configuration => $sample_config_yaml } );

# Create a test ILL request
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
            pod    => 'test-pod',
        }
    }
);

# Mock the RapidoILL::Client
my $client_module = Test::MockModule->new('RapidoILL::Client');
$client_module->mock('lender_renew', sub { return 1; });

subtest 'borrower_renew method sets O_RENEWAL_REQUESTED status' => sub {
    plan tests => 4;

    # Create handler
    my $handler = RapidoILL::ActionHandler::Lender->new(
        {
            pod    => 'test-pod',
            plugin => $plugin,
        }
    );

    # Create mock action with proper ill_request method
    my $mock_action = RapidoILL::CircAction->new(
        {
            circId        => 'TEST_CIRC_001',
            lastCircState => 'BORROWER_RENEW',
            pod           => 'test-pod',
        }
    );

    # Override the ill_request method to return our test request
    no warnings 'redefine';
    local *RapidoILL::CircAction::ill_request = sub { return $ill_request; };

    # Test borrower_renew method
    lives_ok {
        $handler->borrower_renew($mock_action);
    } 'borrower_renew processes without exception';

    # Verify status changed to O_RENEWAL_REQUESTED
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_RENEWAL_REQUESTED', 'Status set to O_RENEWAL_REQUESTED' );

    # Verify renewal attributes were added
    my $renewal_circId_attr = $ill_request->extended_attributes->find({ type => 'renewal_circId' });
    ok( $renewal_circId_attr, 'Renewal circId attribute created' );
    is( $renewal_circId_attr->value, 'TEST_CIRC_001', 'Renewal circId stored correctly' );
};

$schema->storage->txn_rollback;
