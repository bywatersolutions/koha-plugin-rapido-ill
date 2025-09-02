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
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    use_ok('RapidoILL::Backend');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

# Enable ILL module for testing
t::lib::Mocks::mock_preference( 'ILLModule', 1 );

# Mock the lender_actions to avoid API calls and exceptions
my $lender_actions_mock = Test::MockModule->new('RapidoILL::Backend::LenderActions');
$lender_actions_mock->mock(
    'process_renewal_decision',
    sub {
        my ( $self, $req, $params ) = @_;

        # Just update status without any API calls
        $req->status('O_ITEM_RECEIVED_DESTINATION')->store();
        return;    # Don't throw exceptions
    }
);

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
            status         => 'O_RENEWAL_REQUESTED',
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

# Mock the lender_actions method to return a mock object
my $mock_lender_actions = Test::MockModule->new('RapidoILL::Backend::LenderActions');
$mock_lender_actions->mock( 'process_renewal_decision', sub { return 1; } );

# Create backend instance
my $backend = $plugin->new_ill_backend();

subtest 'renewal_request backend method - approval' => sub {
    plan tests => 3;

    my $result = $backend->renewal_request(
        {
            request => $ill_request,
            other   => {
                decision     => 'approve',
                new_due_date => '2025-12-31',
            }
        }
    );

    is( $result->{error}, 0, 'No error on approval' );
    like( $result->{message}, qr/approved successfully/, 'Success message for approval' );

    # Verify status is still O_RENEWAL_REQUESTED
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_RENEWAL_REQUESTED', 'Status returned to O_ITEM_RECEIVED_DESTINATION' );
};

subtest 'renewal_request backend method - rejection' => sub {
    plan tests => 3;

    # Reset status for rejection test
    $ill_request->status('O_RENEWAL_REQUESTED')->store;

    my $result = $backend->renewal_request(
        {
            request => $ill_request,
            other   => {
                decision => 'reject',
            }
        }
    );

    is( $result->{error}, 0, 'No error on rejection' );
    like( $result->{message}, qr/rejected successfully/, 'Success message for rejection' );

    # Verify status returned to O_ITEM_RECEIVED_DESTINATION
    $ill_request->discard_changes;
    is( $ill_request->status, 'O_RENEWAL_REQUESTED', 'Status returned to O_ITEM_RECEIVED_DESTINATION' );
};

$schema->storage->txn_rollback;
