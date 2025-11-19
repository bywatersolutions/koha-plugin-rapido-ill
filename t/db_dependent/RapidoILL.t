#!/usr/bin/env perl

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

use Test::More tests => 8;
use Test::NoWarnings;
use Test::Exception;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;

# Sample configuration based on README.md with dev_mode enabled for testing
my $sample_config_yaml = <<'EOF';
---
dev03-na:
  base_url: https://dev03-na.alma.exlibrisgroup.com
  client_id: test_client_id
  client_secret: test_client_secret
  server_code: 11747
  partners_library_id: CPL
  partners_category: ILL
  default_item_type: ILL
  default_patron_agency: code1
  default_location:
  default_checkin_note: Additional processing required (ILL)
  default_hold_note: Placed by ILL
  default_marc_framework: FA
  default_item_ccode: RAPIDO
  default_notforloan:
  materials_specified: true
  default_materials_specified: Additional processing required (ILL)
  location_to_library:
    RES_SHARE: CPL
  borrowing:
    automatic_item_in_transit: false
    automatic_item_receive: false
  lending:
    automatic_final_checkin: false
    automatic_item_shipped: false
  # Patron validation restrictions
  debt_blocks_holds: true
  max_debt_blocks_holds: 100
  expiration_blocks_holds: true
  restriction_blocks_holds: true
  # Development mode enabled for testing
  dev_mode: true
  default_retry_delay: 120
test-pod:
  base_url: https://test-pod.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 12345
  partners_library_id: TST
  partners_category: ILL
  default_item_type: BOOK
  default_patron_agency: test_agency
  library_to_location:
    TST:
      location: TEST_LOC
    CPL:
      location: CPL_LOC
  # Test missing defaults to verify default values
  dev_mode: true
EOF

subtest 'configuration() tests' => sub {
    plan tests => 5;

    subtest 'Plugin instantiation and configuration storage' => sub {
        plan tests => 4;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
        ok( $plugin, 'Plugin instantiated successfully' );
        isa_ok( $plugin, 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL', 'Plugin has correct class' );

        # Store the sample configuration
        lives_ok { $plugin->store_data( { configuration => $sample_config_yaml } ) }
        'Configuration stored without errors';

        # Verify configuration was stored
        my $stored_config = $plugin->retrieve_data('configuration');
        ok( $stored_config, 'Configuration retrieved from database' );
    };

    subtest 'Configuration parsing and structure' => sub {
        plan tests => 8;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
        $plugin->store_data( { configuration => $sample_config_yaml } );

        my $config;
        lives_ok { $config = $plugin->configuration() } 'Configuration parsed without errors';

        ok( $config, 'Configuration returned' );
        is( ref $config, 'HASH', 'Configuration is a hash reference' );

        # Test pod structure
        ok( exists $config->{'dev03-na'},                 'dev03-na pod exists in configuration' );
        ok( exists $config->{t::lib::Mocks::Rapido::POD}, 'test-pod exists in configuration' );

        # Test basic configuration values
        is(
            $config->{'dev03-na'}->{base_url}, 'https://dev03-na.alma.exlibrisgroup.com',
            'Base URL parsed correctly'
        );
        is( $config->{'dev03-na'}->{server_code}, 11747, 'Server code parsed correctly' );
        is( $config->{'dev03-na'}->{dev_mode},    1,     'dev_mode enabled for testing' );
    };

    subtest 'Configuration defaults and transformations' => sub {
        plan tests => 10;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
        $plugin->store_data( { configuration => $sample_config_yaml } );

        my $config = $plugin->configuration();

        # Test default values are applied
        is(
            $config->{'dev03-na'}->{debt_blocks_holds}, 1,
            'debt_blocks_holds defaults to 1'
        );
        is(
            $config->{'dev03-na'}->{max_debt_blocks_holds}, 100,
            'max_debt_blocks_holds defaults to 100'
        );
        is(
            $config->{'dev03-na'}->{expiration_blocks_holds}, 1,
            'expiration_blocks_holds defaults to 1'
        );
        is(
            $config->{'dev03-na'}->{restriction_blocks_holds}, 1,
            'restriction_blocks_holds defaults to 1'
        );

        # Test defaults are applied to pod without explicit values
        is(
            $config->{t::lib::Mocks::Rapido::POD}->{debt_blocks_holds}, 1,
            'debt_blocks_holds defaults applied to test-pod'
        );
        is(
            $config->{t::lib::Mocks::Rapido::POD}->{max_debt_blocks_holds}, 100,
            'max_debt_blocks_holds defaults applied to test-pod'
        );
        is(
            $config->{t::lib::Mocks::Rapido::POD}->{expiration_blocks_holds}, 1,
            'expiration_blocks_holds defaults applied to test-pod'
        );
        is(
            $config->{t::lib::Mocks::Rapido::POD}->{restriction_blocks_holds}, 1,
            'restriction_blocks_holds defaults applied to test-pod'
        );

        # Test library_to_location transformation
        ok(
            exists $config->{t::lib::Mocks::Rapido::POD}->{location_to_library},
            'location_to_library mapping created'
        );
        is(
            $config->{t::lib::Mocks::Rapido::POD}->{location_to_library}->{TEST_LOC}, 'TST',
            'location_to_library mapping correct for TST'
        );
    };

    subtest 'Configuration caching and recreation' => sub {
        plan tests => 5;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
        $plugin->store_data( { configuration => $sample_config_yaml } );

        # First call should parse and cache
        my $config1 = $plugin->configuration();
        ok( $config1, 'First configuration call successful' );

        # Second call should return cached version
        my $config2 = $plugin->configuration();
        is( $config1, $config2, 'Second call returns same reference (cached)' );

        # Force recreation
        my $config3 = $plugin->configuration( { recreate => 1 } );
        ok( $config3, 'Configuration recreation successful' );
        isnt( $config1, $config3, 'Recreated configuration is new reference' );

        # But content should be the same
        is_deeply( $config1, $config3, 'Recreated configuration has same content' );
    };

    subtest 'Invalid configuration handling' => sub {
        plan tests => 3;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        # Test with invalid YAML
        my $invalid_yaml = "invalid: yaml: content: [unclosed";
        $plugin->store_data( { configuration => $invalid_yaml } );

        dies_ok { $plugin->configuration() } 'Invalid YAML throws exception';

        # Test with empty configuration - this might return undef or empty hash
        $plugin->store_data( { configuration => '' } );
        my $config;
        lives_ok { $config = $plugin->configuration() } 'Empty configuration handled gracefully';

        # Test with no configuration stored - this might return undef or empty hash
        $plugin->store_data( { configuration => undef } );
        lives_ok { $config = $plugin->configuration() } 'Undefined configuration handled gracefully';
    };
};

subtest 'get_borrower_action_handler method' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Test successful instantiation
    my $handler;
    lives_ok {
        $handler = $plugin->get_borrower_action_handler('test_pod')
    }
    'get_borrower_action_handler instantiates successfully';

    isa_ok( $handler, 'RapidoILL::ActionHandler::Borrower', 'Returns correct handler type' );

    # Test caching - second call should return same instance
    my $handler2 = $plugin->get_borrower_action_handler('test_pod');
    is( $handler, $handler2, 'Handler instance is cached for same pod' );

    # Test missing pod parameter
    throws_ok {
        $plugin->get_borrower_action_handler()
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when pod parameter missing';

    $schema->storage->txn_rollback;
};

subtest 'get_lender_action_handler method' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Test successful instantiation
    my $handler;
    lives_ok {
        $handler = $plugin->get_lender_action_handler('test_pod')
    }
    'get_lender_action_handler instantiates successfully';

    isa_ok( $handler, 'RapidoILL::ActionHandler::Lender', 'Returns correct handler type' );

    # Test caching - second call should return same instance
    my $handler2 = $plugin->get_lender_action_handler('test_pod');
    is( $handler, $handler2, 'Handler instance is cached for same pod' );

    # Test missing pod parameter
    throws_ok {
        $plugin->get_lender_action_handler()
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when pod parameter missing';

    $schema->storage->txn_rollback;
};

subtest 'get_action_handler method' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Test borrower perspective
    my $borrower_handler;
    lives_ok {
        $borrower_handler = $plugin->get_action_handler(
            {
                pod         => 'test_pod',
                perspective => 'borrower'
            }
        );
    }
    'get_action_handler with borrower perspective works';

    isa_ok(
        $borrower_handler, 'RapidoILL::ActionHandler::Borrower',
        'Returns borrower handler for borrower perspective'
    );

    # Test lender perspective
    my $lender_handler;
    lives_ok {
        $lender_handler = $plugin->get_action_handler(
            {
                pod         => 'test_pod',
                perspective => 'lender'
            }
        );
    }
    'get_action_handler with lender perspective works';

    isa_ok( $lender_handler, 'RapidoILL::ActionHandler::Lender', 'Returns lender handler for lender perspective' );

    # Test invalid perspective
    throws_ok {
        $plugin->get_action_handler(
            {
                pod         => 'test_pod',
                perspective => 'invalid'
            }
        );
    }
    'RapidoILL::Exception::BadParameter', 'Dies with invalid perspective';

    # Test missing parameters
    throws_ok {
        $plugin->get_action_handler( {} );
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when parameters missing';

    $schema->storage->txn_rollback;
};

subtest 'get_checkout() tests' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Create test ILL request
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                backend => 'RapidoILL',
                status  => 'B_ITEM_RECEIVED'
            }
        }
    );

    # Test with no checkout_id attribute
    my $checkout = $plugin->get_checkout($ill_request);
    is( $checkout, undef, 'Returns undef when no checkout_id attribute exists' );

    # Create a checkout and link it to the ILL request
    my $patron        = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item          = $builder->build_object( { class => 'Koha::Items' } );
    my $test_checkout = $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value => {
                borrowernumber => $patron->id,
                itemnumber     => $item->id,
                date_due       => '2025-09-07 23:59:59'
            }
        }
    );

    # Add checkout_id attribute to ILL request
    $builder->build_object(
        {
            class => 'Koha::ILL::Request::Attributes',
            value => {
                illrequest_id => $ill_request->id,
                type          => 'checkout_id',
                value         => $test_checkout->id
            }
        }
    );

    # Test with valid checkout_id attribute
    $checkout = $plugin->get_checkout($ill_request);
    isa_ok( $checkout, 'Koha::Checkout', 'Returns Koha::Checkout object when checkout_id exists' );
    is( $checkout->id, $test_checkout->id, 'Returns correct checkout object' );

    # Test with undef parameter
    $checkout = $plugin->get_checkout(undef);
    is( $checkout, undef, 'Returns undef when passed undef parameter' );

    $schema->storage->txn_rollback;
};

subtest 'get_http_client() tests' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Store test configuration
    my $test_config = q{
dev03-na:
  base_url: https://dev03-na.alma.exlibrisgroup.com
  client_id: test_client_id
  client_secret: test_client_secret
  server_code: 12345
  partners_library_id: TST
  dev_mode: true
test-pod:
  base_url: https://test.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 67890
  partners_library_id: TEST
  dev_mode: true
};

    $plugin->store_data( { configuration => $test_config } );

    subtest 'Successful HTTP client creation' => sub {
        plan tests => 4;

        my $client = $plugin->get_http_client('dev03-na');

        isa_ok( $client, 'RapidoILL::APIHttpClient', 'Returns APIHttpClient instance' );
        is( $client->{base_url}, 'https://dev03-na.alma.exlibrisgroup.com', 'Base URL set correctly' );
        is( $client->{pod},      'dev03-na',                                'Pod parameter set correctly' );
        ok( $client->{plugin}, 'Plugin reference set' );
    };

    subtest 'Client caching' => sub {
        plan tests => 2;

        my $client1 = $plugin->get_http_client(t::lib::Mocks::Rapido::POD);
        my $client2 = $plugin->get_http_client(t::lib::Mocks::Rapido::POD);

        is( $client1,        $client2,                   'Same client instance returned for same pod' );
        is( $client1->{pod}, t::lib::Mocks::Rapido::POD, 'Cached client has correct pod' );
    };

    subtest 'Different pods get different clients' => sub {
        plan tests => 3;

        my $client1 = $plugin->get_http_client('dev03-na');
        my $client2 = $plugin->get_http_client(t::lib::Mocks::Rapido::POD);

        isnt( $client1, $client2, 'Different client instances for different pods' );
        is( $client1->{pod}, 'dev03-na',                 'Client1 has correct pod' );
        is( $client2->{pod}, t::lib::Mocks::Rapido::POD, 'Client2 has correct pod' );
    };

    subtest 'Missing pod parameter' => sub {
        plan tests => 2;

        throws_ok {
            $plugin->get_http_client();
        }
        'RapidoILL::Exception::MissingParameter', 'Dies when pod parameter missing';

        is( $@->param, 'pod', 'Exception indicates missing pod parameter' );
    };

    subtest 'Invalid pod configuration' => sub {
        plan tests => 2;

        throws_ok {
            $plugin->get_http_client('nonexistent-pod');
        }
        'RapidoILL::Exception::MissingParameter', 'Dies for nonexistent pod configuration';

        is( $@->param, 'base_url', 'Exception indicates missing base_url from undefined configuration' );
    };

    $schema->storage->txn_rollback;
};

$schema->storage->txn_rollback;
