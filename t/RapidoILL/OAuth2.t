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

use Test::More tests => 3;
use Test::MockObject;
use Test::NoWarnings;
use JSON qw(encode_json);

BEGIN {
    use_ok('RapidoILL::OAuth2');
}

subtest 'Logging tests' => sub {

    plan tests => 4;

    subtest 'OAuth2 logger method' => sub {
        plan tests => 3;

        # Create mock plugin with logger
        my $mock_plugin = Test::MockObject->new();
        my $mock_logger = Test::MockObject->new();
        $mock_plugin->mock( 'logger', sub { return $mock_logger } );

        # Create OAuth2 instance with plugin reference
        my $oauth2 = RapidoILL::OAuth2->new(
            {
                client_id      => 'test_client',
                client_secret  => 'test_secret',
                base_url       => 'https://test.example.com',
                debug_requests => 1,
                plugin         => $mock_plugin,
                dev_mode       => 1,                            # Avoid token refresh
            }
        );

        isa_ok( $oauth2, 'RapidoILL::OAuth2', 'OAuth2 instance created' );
        is( $oauth2->logger(), $mock_logger, 'OAuth2 logger returns plugin logger' );

        # Test without plugin reference
        my $oauth2_no_plugin = RapidoILL::OAuth2->new(
            {
                client_id      => 'test_client',
                client_secret  => 'test_secret',
                base_url       => 'https://test.example.com',
                debug_requests => 1,
                dev_mode       => 1,
            }
        );

        is( $oauth2_no_plugin->logger(), undef, 'OAuth2 logger returns undef without plugin' );
    };

    subtest 'Debug mode enabled - logger called' => sub {
        plan tests => 11;

        # Create mock objects
        my $mock_plugin   = Test::MockObject->new();
        my $mock_logger   = Test::MockObject->new();
        my $mock_ua       = Test::MockObject->new();
        my $mock_response = Test::MockObject->new();

        # Track debug calls
        my @debug_calls = ();
        my @info_calls  = ();
        my @error_calls = ();

        $mock_logger->mock(
            'debug',
            sub {
                my ( $self, $message ) = @_;
                push @debug_calls, $message;
            }
        );
        $mock_logger->mock(
            'info',
            sub {
                my ( $self, $message ) = @_;
                push @info_calls, $message;
            }
        );
        $mock_logger->mock(
            'error',
            sub {
                my ( $self, $message ) = @_;
                push @error_calls, $message;
            }
        );

        # Mock response methods
        $mock_response->mock( 'is_success', sub { return 1 } );
        $mock_response->mock( 'code',       sub { return 200 } );
        $mock_response->mock( 'message',    sub { return 'OK' } );

        $mock_plugin->mock( 'logger', sub { return $mock_logger } );
        $mock_ua->mock( 'request', sub { return $mock_response } );

        # Create OAuth2 instance with debug mode ENABLED
        my $oauth2 = RapidoILL::OAuth2->new(
            {
                client_id      => 'test_client',
                client_secret  => 'test_secret',
                base_url       => 'https://test.example.com',
                debug_requests => 1,                            # Debug enabled
                plugin         => $mock_plugin,
                dev_mode       => 1,
            }
        );

        # Override UA and token method
        $oauth2->{ua}           = $mock_ua;
        $oauth2->{access_token} = 'mock_token';

        # Test POST request logging
        @debug_calls = ();
        @info_calls  = ();
        @error_calls = ();
        $oauth2->post_request(
            {
                endpoint => '/test/endpoint',
                data     => { key => 'value' }
            }
        );

        is( scalar @debug_calls, 2, 'POST request: 2 debug calls made' );
        is( scalar @info_calls,  2, 'POST request: 2 info calls made (request + response)' );
        like( $debug_calls[0], qr/POST request to/,     'POST: First debug call is endpoint log' );
        like( $info_calls[0],  qr/Making POST request/, 'POST: First info call is request log' );

        # Test GET request logging
        @debug_calls = ();
        @info_calls  = ();
        @error_calls = ();
        $oauth2->get_request(
            {
                endpoint => '/test/endpoint',
                query    => { param => 'value' }
            }
        );

        is( scalar @debug_calls, 1, 'GET request: 1 debug call made' );
        is( scalar @info_calls,  2, 'GET request: 2 info calls made (request + response)' );
        like( $info_calls[0], qr/Making GET request/, 'GET: First info call is request log' );

        # Test PUT request logging
        @debug_calls = ();
        @info_calls  = ();
        @error_calls = ();
        $oauth2->put_request(
            {
                endpoint => '/test/endpoint',
                data     => { update => 'value' }
            }
        );

        is( scalar @debug_calls, 2, 'PUT request: 2 debug calls made' );
        is( scalar @info_calls,  2, 'PUT request: 2 info calls made (request + response)' );

        # Test DELETE request logging
        @debug_calls = ();
        @info_calls  = ();
        @error_calls = ();
        $oauth2->delete_request( { endpoint => '/test/endpoint' } );

        is( scalar @debug_calls, 1, 'DELETE request: 1 debug call made' );
        is( scalar @info_calls,  2, 'DELETE request: 2 info calls made (request + response)' );
    };

    subtest 'Debug mode disabled - logger not called' => sub {
        plan tests => 2;

        # Create mock objects
        my $mock_plugin   = Test::MockObject->new();
        my $mock_logger   = Test::MockObject->new();
        my $mock_ua       = Test::MockObject->new();
        my $mock_response = Test::MockObject->new();

        # Track debug calls
        my @debug_calls = ();
        my @info_calls  = ();

        $mock_logger->mock(
            'debug',
            sub {
                my ( $self, $message ) = @_;
                push @debug_calls, $message;
            }
        );
        $mock_logger->mock(
            'info',
            sub {
                my ( $self, $message ) = @_;
                push @info_calls, $message;
            }
        );

        # Mock response methods
        $mock_response->mock( 'is_success', sub { return 1 } );
        $mock_response->mock( 'code',       sub { return 200 } );
        $mock_response->mock( 'message',    sub { return 'OK' } );

        $mock_plugin->mock( 'logger', sub { return $mock_logger } );
        $mock_ua->mock( 'request', sub { return $mock_response } );

        # Create OAuth2 instance with debug mode DISABLED
        my $oauth2 = RapidoILL::OAuth2->new(
            {
                client_id      => 'test_client',
                client_secret  => 'test_secret',
                base_url       => 'https://test.example.com',
                debug_requests => 0,                            # Debug disabled
                plugin         => $mock_plugin,
                dev_mode       => 1,
            }
        );

        # Override UA and token method
        $oauth2->{ua}           = $mock_ua;
        $oauth2->{access_token} = 'mock_token';

        # Test that debug calls are not made when debug is disabled, but info calls still are
        @debug_calls = ();
        @info_calls  = ();

        $oauth2->post_request(
            {
                endpoint => '/test/endpoint',
                data     => { key => 'value' }
            }
        );

        is( scalar @debug_calls, 0, 'No debug calls made when debug mode disabled' );

        # Verify logger method still works
        my $logger = $oauth2->logger();
        is( $logger, $mock_logger, 'Logger method still returns logger when debug disabled' );
    };

    subtest 'Error logging for failed requests' => sub {
        plan tests => 4;

        # Create mock objects
        my $mock_plugin   = Test::MockObject->new();
        my $mock_logger   = Test::MockObject->new();
        my $mock_ua       = Test::MockObject->new();
        my $mock_response = Test::MockObject->new();

        # Track error calls
        my @error_calls = ();
        my @info_calls  = ();

        $mock_logger->mock(
            'error',
            sub {
                my ( $self, $message ) = @_;
                push @error_calls, $message;
            }
        );
        $mock_logger->mock(
            'info',
            sub {
                my ( $self, $message ) = @_;
                push @info_calls, $message;
            }
        );
        $mock_logger->mock( 'debug', sub { } );    # Ignore debug calls

        # Mock failed response
        $mock_response->mock( 'is_success', sub { return 0 } );
        $mock_response->mock( 'code',       sub { return 500 } );
        $mock_response->mock( 'message',    sub { return 'Internal Server Error' } );

        $mock_plugin->mock( 'logger', sub { return $mock_logger } );
        $mock_ua->mock( 'request', sub { return $mock_response } );

        # Create OAuth2 instance
        my $oauth2 = RapidoILL::OAuth2->new(
            {
                client_id      => 'test_client',
                client_secret  => 'test_secret',
                base_url       => 'https://test.example.com',
                debug_requests => 1,
                plugin         => $mock_plugin,
                dev_mode       => 1,
            }
        );

        # Override UA and token method
        $oauth2->{ua}           = $mock_ua;
        $oauth2->{access_token} = 'mock_token';

        # Test error logging for failed POST request
        @error_calls = ();
        @info_calls  = ();
        $oauth2->post_request(
            {
                endpoint => '/test/endpoint',
                data     => { key => 'value' }
            }
        );

        is( scalar @error_calls, 1, 'Error logged for failed POST request' );
        like(
            $error_calls[0], qr/POST request failed: 500 Internal Server Error/,
            'Error message contains status and endpoint'
        );

        # Test error logging for failed GET request
        @error_calls = ();
        @info_calls  = ();
        $oauth2->get_request( { endpoint => '/test/endpoint' } );

        is( scalar @error_calls, 1, 'Error logged for failed GET request' );
        like(
            $error_calls[0], qr/GET request failed: 500 Internal Server Error/,
            'Error message contains status and endpoint'
        );
    };

};
