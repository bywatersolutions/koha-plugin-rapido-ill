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
use Test::MockObject;
use Test::NoWarnings;

BEGIN {
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

subtest 'Plugin logger method' => sub {
    plan tests => 4;

    # Mock Koha::Logger
    my $mock_logger = Test::MockObject->new();
    $mock_logger->set_isa('Koha::Logger');

    my $koha_logger_mock = Test::MockModule->new('Koha::Logger');
    $koha_logger_mock->mock( 'get', sub { return $mock_logger } );

    # Test plugin logger initialization
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    isa_ok( $plugin, 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL', 'Plugin instantiated' );

    # Test logger method exists
    ok( $plugin->can('logger'), 'Plugin has logger method' );

    # Test logger returns the mocked logger
    my $logger = $plugin->logger();
    is( $logger, $mock_logger, 'Logger method returns mocked logger' );

    # Test singleton behavior - same logger instance returned
    my $logger2 = $plugin->logger();
    is( $logger, $logger2, 'Logger method returns same instance (singleton)' );
};

subtest 'OAuth2 gets plugin reference for logger access' => sub {
    plan tests => 4;

    # Mock Koha::Logger
    my $mock_logger = Test::MockObject->new();
    $mock_logger->set_isa('Koha::Logger');

    my $koha_logger_mock = Test::MockModule->new('Koha::Logger');
    $koha_logger_mock->mock( 'get', sub { return $mock_logger } );

    # Create plugin
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

    # Mock plugin configuration
    my $plugin_mock = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    $plugin_mock->mock(
        'configuration',
        sub {
            return {
                'test-pod' => {
                    client_id      => 'test_client',
                    client_secret  => 'test_secret',
                    base_url       => 'https://test.example.com',
                    debug_requests => 1,
                }
            };
        }
    );

    # Mock OAuth2 to avoid HTTP requests
    my $oauth2_mock = Test::MockModule->new('RapidoILL::OAuth2');
    $oauth2_mock->mock( 'refresh_token', sub { return 1; } );

    # Test OAuth2 instantiation with plugin reference
    lives_ok {
        my $oauth2 = $plugin->get_ua('test-pod');
        isa_ok( $oauth2, 'RapidoILL::OAuth2', 'OAuth2 instance created' );

        # Test that OAuth2 has plugin reference
        is( $oauth2->plugin, $plugin, 'OAuth2 has plugin reference' );

        # Test that OAuth2 can access logger through plugin
        ok( $oauth2->can('logger'), 'OAuth2 has logger method' );

    }
    'OAuth2 instantiation with plugin reference works';
};
