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
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 6;
use Test::NoWarnings;
use Test::Exception;
use Test::MockModule;
use Test::MockModule;

use t::lib::TestBuilder;
use t::lib::Mocks;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
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

subtest 'sync_circ_requests - default state parameter' => sub {
    plan tests => 2;

    # Mock the RapidoILL::Client module
    my $client_module = Test::MockModule->new('RapidoILL::Client');
    my $captured_params;
    
    $client_module->mock('circulation_requests', sub {
        my ($self, $params) = @_;
        $captured_params = $params;
        return []; # Return empty array for testing
    });

    # Call sync_circ_requests without state parameter
    my $results = $plugin->sync_circ_requests({
        pod => 'test-pod'
    });

    # Verify default state was used
    is_deeply(
        $captured_params->{state},
        ['ACTIVE', 'COMPLETED', 'CANCELED', 'CREATED'],
        'Default state parameter used when not specified'
    );

    # Verify results structure
    is(ref($results), 'HASH', 'Returns hash reference');
};

subtest 'sync_circ_requests - custom state parameter' => sub {
    plan tests => 2;

    # Mock the RapidoILL::Client module
    my $client_module = Test::MockModule->new('RapidoILL::Client');
    my $captured_params;
    
    $client_module->mock('circulation_requests', sub {
        my ($self, $params) = @_;
        $captured_params = $params;
        return []; # Return empty array for testing
    });

    # Call sync_circ_requests with custom state parameter
    my $custom_states = ['ACTIVE', 'COMPLETED'];
    my $results = $plugin->sync_circ_requests({
        pod   => 'test-pod',
        state => $custom_states
    });

    # Verify custom state was used
    is_deeply(
        $captured_params->{state},
        $custom_states,
        'Custom state parameter used when specified'
    );

    # Verify results structure
    is(ref($results), 'HASH', 'Returns hash reference');
};

subtest 'sync_circ_requests - single state parameter' => sub {
    plan tests => 2;

    # Mock the RapidoILL::Client module
    my $client_module = Test::MockModule->new('RapidoILL::Client');
    my $captured_params;
    
    $client_module->mock('circulation_requests', sub {
        my ($self, $params) = @_;
        $captured_params = $params;
        return []; # Return empty array for testing
    });

    # Call sync_circ_requests with single state
    my $single_state = ['ACTIVE'];
    my $results = $plugin->sync_circ_requests({
        pod   => 'test-pod',
        state => $single_state
    });

    # Verify single state was used
    is_deeply(
        $captured_params->{state},
        $single_state,
        'Single state parameter used correctly'
    );

    # Verify results structure
    is(ref($results), 'HASH', 'Returns hash reference');
};

subtest 'sync_circ_requests - state parameter with other params' => sub {
    plan tests => 4;

    # Mock the RapidoILL::Client module
    my $client_module = Test::MockModule->new('RapidoILL::Client');
    my $captured_params;
    
    $client_module->mock('circulation_requests', sub {
        my ($self, $params) = @_;
        $captured_params = $params;
        return []; # Return empty array for testing
    });

    # Call sync_circ_requests with all parameters
    my $custom_states = ['COMPLETED', 'CANCELED'];
    my $start_time = 1700000000;
    my $end_time = 1800000000;
    
    my $results = $plugin->sync_circ_requests({
        pod       => 'test-pod',
        state     => $custom_states,
        startTime => $start_time,
        endTime   => $end_time
    });

    # Verify all parameters were passed correctly
    is_deeply($captured_params->{state}, $custom_states, 'Custom state parameter passed');
    is($captured_params->{startTime}, $start_time, 'Start time parameter passed');
    is($captured_params->{endTime}, $end_time, 'End time parameter passed');
    is($captured_params->{content}, 'verbose', 'Content parameter set to verbose');
};

$schema->storage->txn_rollback;
