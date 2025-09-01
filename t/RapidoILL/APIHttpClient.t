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

use Test::More tests => 12;
use Test::Exception;
use Test::MockModule;
use HTTP::Response;
use HTTP::Request;
use JSON qw(encode_json);

use t::lib::Mocks;
use t::lib::Mocks::Logger;

BEGIN {
    use_ok('RapidoILL::APIHttpClient');
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

my $logger = t::lib::Mocks::Logger->new();

# The mock logger already mocks Koha::Logger->get() internally,
# but we need to add the is_debug method to the returned mock object
my $mock_logger_obj = Koha::Logger->get();
$mock_logger_obj->mock( 'is_debug', sub { return 1; } );    # Always return true for tests

subtest 'new() tests' => sub {
    plan tests => 2;

    subtest 'Successful instantiation' => sub {
        plan tests => 2;

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,                            # Skip token refresh in dev mode
            }
        );

        isa_ok( $client, 'RapidoILL::APIHttpClient', 'APIHttpClient instance created' );
        is( $client->{base_url}, 'https://test.example.com', 'Base URL set correctly' );
    };

    subtest 'Missing parameters' => sub {
        plan tests => 6;

        throws_ok {
            RapidoILL::APIHttpClient->new( {} );
        }
        'RapidoILL::Exception::MissingParameter', 'Dies when base_url missing';

        is( $@->param, 'base_url' );

        throws_ok {
            RapidoILL::APIHttpClient->new( { base_url => 'https://test.com' } );
        }
        'RapidoILL::Exception::MissingParameter', 'Dies when client_id missing';

        is( $@->param, 'client_id' );

        throws_ok {
            RapidoILL::APIHttpClient->new(
                {
                    base_url  => 'https://test.com',
                    client_id => 'test'
                }
            );
        }
        'RapidoILL::Exception::MissingParameter', 'Dies when client_secret missing';

        is( $@->param, 'client_secret' );
    };
};

subtest 'Dev mode behavior' => sub {
    plan tests => 1;

    my $plugin           = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $client_no_plugin = RapidoILL::APIHttpClient->new(
        {
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            plugin        => $plugin,
                pod           => "test-pod",
            dev_mode      => 1,
        }
    );

    ok( $client_no_plugin->{dev_mode}, 'Dev mode enabled' );
};

subtest 'Token management methods' => sub {
    plan tests => 2;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $client = RapidoILL::APIHttpClient->new(
        {
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            plugin        => $plugin,
                pod           => "test-pod",
            dev_mode      => 1,
        }
    );

    can_ok( $client, 'get_token' );
    can_ok( $client, 'is_token_expired' );
};

subtest 'refresh_token() tests' => sub {
    plan tests => 3;

    subtest 'Successful token refresh' => sub {
        plan tests => 6;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content(
                    encode_json(
                        {
                            access_token => 'new_test_token_12345',
                            expires_in   => 3600,
                            token_type   => 'Bearer'
                        }
                    )
                );
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        $logger->clear();

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 0,                            # Disable dev mode to test token refresh
            }
        );

        # Test successful token refresh
        my $result = $client->refresh_token();

        # Verify return value
        isa_ok( $result, 'RapidoILL::APIHttpClient', 'refresh_token returns self' );
        is( $client->{access_token}, 'new_test_token_12345', 'Access token updated correctly' );
        ok( $client->{expiration}, 'Expiration time set' );

        # Verify logging
        $logger->info_like(
            qr/Refreshing OAuth2 token for https:\/\/test\.example\.com/,
            'Info log for token refresh start'
        );
        $logger->info_like(
            qr/OAuth2 token refreshed successfully, expires in 3600 seconds/,
            'Info log for successful refresh'
        );

        # Verify no error logs
        is( $logger->count('error'), 0, 'No error logs for successful refresh' );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed token refresh - HTTP error' => sub {
        plan tests => 5;

        $logger->clear();

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 401, 'Unauthorized' );
                $response->content(
                    encode_json(
                        {
                            error             => 'invalid_client',
                            error_description => 'Client authentication failed'
                        }
                    )
                );
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

        # Constructor should succeed with deferred token refresh
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 0,
            }
        );

        isa_ok( $client, 'RapidoILL::APIHttpClient', 'Constructor succeeds with deferred refresh' );

        # First request should fail when token refresh fails
        my $exception_caught  = 0;
        my $exception_message = '';

        throws_ok {
            $client->get_request( { endpoint => '/test' } );
        }
        'RapidoILL::Exception::OAuth2::AuthError', 'Exception thrown on first request';

        if ( my $error = $@ ) {
            $exception_caught  = 1;
            $exception_message = "$error";
        }

        # Verify exception was thrown
        ok( $exception_caught, 'Exception was thrown on authentication failure' );
        like(
            $exception_message, qr/Authentication error: Client authentication failed/,
            'Exception contains error description'
        );

        # Verify logging
        $logger->info_like(
            qr/No token available, refreshing\.\.\./,
            'Info log for deferred token refresh'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed token refresh - Invalid JSON response' => sub {
        plan tests => 3;

        $logger->clear();

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content('Invalid JSON response');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

        # Constructor should succeed with deferred token refresh
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 0,
            }
        );

        isa_ok( $client, 'RapidoILL::APIHttpClient', 'Constructor succeeds with deferred refresh' );

        # First request should fail when JSON parsing fails
        throws_ok {
            $client->get_request( { endpoint => '/test' } );
        }
        qr/malformed JSON string/, 'Dies on invalid JSON response during first request';

        # Verify logging
        $logger->info_like(
            qr/No token available, refreshing\.\.\./,
            'Info log for deferred token refresh'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };
};

subtest 'get_token() deferred refresh tests' => sub {
    plan tests => 2;

    subtest 'First call triggers token refresh' => sub {
        plan tests => 4;

        $logger->clear();

        # Mock successful OAuth2 response
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content(
                    encode_json(
                        {
                            access_token => 'deferred_token_12345',
                            expires_in   => 3600,
                            token_type   => 'Bearer'
                        }
                    )
                );
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 0,
            }
        );

        # Verify no token exists initially
        ok( !$client->{access_token}, 'No token exists after construction' );

        # First call to get_token should trigger refresh
        my $token = $client->get_token();

        # Verify token was obtained
        is( $token,                  'deferred_token_12345', 'Token obtained from deferred refresh' );
        is( $client->{access_token}, 'deferred_token_12345', 'Token stored in client' );

        # Verify logging
        $logger->info_like(
            qr/No token available, refreshing\.\.\./,
            'Info log for deferred token refresh'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Subsequent calls use cached token' => sub {
        plan tests => 3;

        $logger->clear();

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 0,
            }
        );

        # Manually set a token and expiration (simulating previous refresh)
        $client->{access_token} = 'cached_token_67890';
        $client->{expiration}   = DateTime->now()->add( hours => 1 );

        # Call get_token - should return cached token
        my $token = $client->get_token();

        is( $token, 'cached_token_67890', 'Cached token returned' );

        # Verify no refresh logging (no new refresh occurred)
        is( $logger->count('info'),  0, 'No refresh logs for cached token' );
        is( $logger->count('error'), 0, 'No error logs for cached token' );
    };
};

subtest 'delete_request() tests' => sub {
    plan tests => 4;

    my $client_mock = Test::MockModule->new('RapidoILL::APIHttpClient');
    $client_mock->mock( 'get_token', sub { return 'the_token'; } );

    subtest 'Successful DELETE request' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 204, 'No Content' );
                $response->content('');
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,                            # Use dev_mode to avoid refresh_token call
            }
        );

        $logger->clear();

        # Test successful DELETE request
        my $response = $client->delete_request( { endpoint => '/item/123' } );

        # Verify response
        ok( $response->is_success, 'DELETE response indicates success' );
        is( $response->code, 204, 'DELETE response has correct status code' );

        # Verify logging
        $logger->info_like(
            qr/Making DELETE request to https:\/\/test\.example\.com\/item\/123/,
            'Info log for DELETE request start'
        );
        $logger->info_like( qr/DELETE request successful: 204 No Content/, 'Info log for successful DELETE' );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'DELETE request with context parameter' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content('{"deleted": true, "id": "456"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,                            # Use dev_mode to avoid refresh_token call
            }
        );

        $logger->clear();

        # Test DELETE request with context
        my $response = $client->delete_request(
            {
                endpoint => '/reservation/456',
                context  => 'cancel_reservation'
            }
        );

        # Verify response
        ok( $response->is_success, 'DELETE response with context indicates success' );
        is( $response->code, 200, 'DELETE response has correct status code' );

        # Verify context appears in logs
        $logger->info_like(
            qr/Making DELETE request to https:\/\/test\.example\.com\/reservation\/456/,
            'Info log for DELETE request start'
        );
        $logger->info_like(
            qr/DELETE request successful: 200 OK \[context: cancel_reservation\]/,
            'Info log includes context for successful DELETE'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed DELETE request - HTTP error' => sub {
        plan tests => 6;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'DELETE', 'https://test.example.com/item/999' );

                my $response = HTTP::Response->new( 404, 'Not Found' );
                $response->request($request);
                $response->content('{"error": "Resource not found", "id": "999"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,                            # Use dev_mode to avoid refresh_token call
            }
        );

        $logger->clear();

        # Test failed DELETE request
        my $response = $client->delete_request(
            {
                endpoint => '/item/999',
                context  => 'delete_item'
            }
        );

        # Verify response
        ok( !$response->is_success, 'DELETE response indicates failure' );
        is( $response->code, 404, 'DELETE response has correct error status code' );

        # Verify error logging
        $logger->info_like(
            qr/Making DELETE request to https:\/\/test\.example\.com\/item\/999/,
            'Info log for DELETE request start'
        );
        $logger->error_like(
            qr/DELETE request failed: 404 Not Found to https:\/\/test\.example\.com\/item\/999 \[context: delete_item\]/,
            'Error log contains status, endpoint, and context'
        );

        # Verify debug logging for response content
        # First debug message is the request debug, second is the response body debug
        $logger->debug_like(
            qr/DELETE request headers: Authorization=Bearer \[REDACTED\], Accept=application\/json/,
            'Debug log for DELETE request'
        );
        $logger->debug_like(
            qr/DELETE request failed response body \[context: delete_item\]: .*Resource not found/,
            'Debug log contains response body with context'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed DELETE request - Permission denied' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'DELETE', 'https://test.example.com/admin/user/123' );

                my $response = HTTP::Response->new( 403, 'Forbidden' );
                $response->request($request);
                $response->content('{"error": "Insufficient permissions", "required_role": "admin"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,                            # Use dev_mode to avoid refresh_token call
            }
        );

        $logger->clear();

        # Test permission denied DELETE request
        my $response = $client->delete_request( { endpoint => '/admin/user/123' } );

        # Verify response
        ok( !$response->is_success, 'DELETE response indicates failure' );
        is( $response->code, 403, 'DELETE response has correct permission error status code' );

        # Verify error logging (without context this time)
        $logger->info_like(
            qr/Making DELETE request to https:\/\/test\.example\.com\/admin\/user\/123/,
            'Info log for DELETE request start'
        );
        $logger->error_like(
            qr/DELETE request failed: 403 Forbidden to https:\/\/test\.example\.com\/admin\/user\/123$/,
            'Error log contains status and endpoint (no context)'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };
};

subtest 'post_request() tests' => sub {
    plan tests => 4;

    my $client_mock = Test::MockModule->new('RapidoILL::APIHttpClient');
    $client_mock->mock( 'get_token', sub { return 'the_token'; } );

    subtest 'Successful POST request' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 201, 'Created' );
                $response->content('{"id": "12345", "status": "created"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test successful POST request
        my $response = $client->post_request(
            {
                endpoint => '/items',
                data     => { title => 'Test Item', author => 'Test Author' }
            }
        );

        # Verify response
        ok( $response->is_success, 'POST response indicates success' );
        is( $response->code, 201, 'POST response has correct status code' );

        # Verify logging
        $logger->info_like(
            qr/Making POST request to https:\/\/test\.example\.com\/items/,
            'Info log for POST request start'
        );
        $logger->info_like( qr/POST request successful: 201 Created/, 'Info log for successful POST' );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'POST request with context parameter' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content('{"success": true, "message": "Item updated"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test POST request with context
        my $response = $client->post_request(
            {
                endpoint => '/borrowercancel',
                data     => { circId => '789' },
                context  => 'borrower_cancel'
            }
        );

        # Verify response
        ok( $response->is_success, 'POST response with context indicates success' );
        is( $response->code, 200, 'POST response has correct status code' );

        # Verify context appears in logs
        $logger->info_like(
            qr/Making POST request to https:\/\/test\.example\.com\/borrowercancel/,
            'Info log for POST request start'
        );
        $logger->info_like(
            qr/POST request successful: 200 OK \[context: borrower_cancel\]/,
            'Info log includes context for successful POST'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed POST request - HTTP error' => sub {
        plan tests => 7;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'POST', 'https://test.example.com/items' );

                my $response = HTTP::Response->new( 400, 'Bad Request' );
                $response->request($request);
                $response->content('{"error": "Validation failed", "details": "Missing required field: title"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test failed POST request
        my $response = $client->post_request(
            {
                endpoint => '/items',
                data     => { author => 'Test Author' },
                context  => 'create_item'
            }
        );

        # Verify response
        ok( !$response->is_success, 'POST response indicates failure' );
        is( $response->code, 400, 'POST response has correct error status code' );

        # Verify error logging
        $logger->info_like(
            qr/Making POST request to https:\/\/test\.example\.com\/items/,
            'Info log for POST request start'
        );
        $logger->error_like(
            qr/POST request failed: 400 Bad Request to https:\/\/test\.example\.com\/items \[context: create_item\]/,
            'Error log contains status, endpoint, and context'
        );

        # Verify debug logging for response content
        # First debug message is the request debug, second is request data, third is the response body debug
        $logger->debug_like(
            qr/POST request headers: Authorization=Bearer \[REDACTED\], Content-Type=application\/json/,
            'Debug log for POST request'
        );
        $logger->debug_like(
            qr/Request data: .*author.*Test Author/,
            'Debug log for POST request data'
        );
        $logger->debug_like(
            qr/POST request failed response body \[context: create_item\]: .*Validation failed/,
            'Debug log contains response body with context'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed POST request - Server error' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'POST', 'https://test.example.com/items' );

                my $response = HTTP::Response->new( 500, 'Internal Server Error' );
                $response->request($request);
                $response->content('{"error": "Database connection failed"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test server error POST request
        my $response = $client->post_request(
            {
                endpoint => '/items',
                data     => { title => 'Test Item' }
            }
        );

        # Verify response
        ok( !$response->is_success, 'POST response indicates failure' );
        is( $response->code, 500, 'POST response has correct server error status code' );

        # Verify error logging (without context this time)
        $logger->info_like(
            qr/Making POST request to https:\/\/test\.example\.com\/items/,
            'Info log for POST request start'
        );
        $logger->error_like(
            qr/POST request failed: 500 Internal Server Error to https:\/\/test\.example\.com\/items$/,
            'Error log contains status and endpoint (no context)'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };
};

subtest 'put_request() tests' => sub {
    plan tests => 4;

    my $client_mock = Test::MockModule->new('RapidoILL::APIHttpClient');
    $client_mock->mock( 'get_token', sub { return 'the_token'; } );

    subtest 'Successful PUT request' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content('{"id": "456", "status": "updated"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test successful PUT request
        my $response = $client->put_request(
            {
                endpoint => '/items/456',
                data     => { title => 'Updated Item', status => 'active' }
            }
        );

        # Verify response
        ok( $response->is_success, 'PUT response indicates success' );
        is( $response->code, 200, 'PUT response has correct status code' );

        # Verify logging
        $logger->info_like(
            qr/Making PUT request to https:\/\/test\.example\.com\/items\/456/,
            'Info log for PUT request start'
        );
        $logger->info_like( qr/PUT request successful: 200 OK/, 'Info log for successful PUT' );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'PUT request with context parameter' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 202, 'Accepted' );
                $response->content('{"message": "Update queued for processing"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test PUT request with context
        my $response = $client->put_request(
            {
                endpoint => '/requests/789/status',
                data     => { status => 'completed' },
                context  => 'update_request_status'
            }
        );

        # Verify response
        ok( $response->is_success, 'PUT response with context indicates success' );
        is( $response->code, 202, 'PUT response has correct status code' );

        # Verify context appears in logs
        $logger->info_like(
            qr/Making PUT request to https:\/\/test\.example\.com\/requests\/789\/status/,
            'Info log for PUT request start'
        );
        $logger->info_like(
            qr/PUT request successful: 202 Accepted \[context: update_request_status\]/,
            'Info log includes context for successful PUT'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed PUT request - HTTP error' => sub {
        plan tests => 7;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'PUT', 'https://test.example.com/items/999' );

                my $response = HTTP::Response->new( 409, 'Conflict' );
                $response->request($request);
                $response->content('{"error": "Version conflict", "current_version": "2", "provided_version": "1"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test failed PUT request
        my $response = $client->put_request(
            {
                endpoint => '/items/999',
                data     => { title => 'Updated Title', version => 1 },
                context  => 'update_item'
            }
        );

        # Verify response
        ok( !$response->is_success, 'PUT response indicates failure' );
        is( $response->code, 409, 'PUT response has correct error status code' );

        # Verify error logging
        $logger->info_like(
            qr/Making PUT request to https:\/\/test\.example\.com\/items\/999/,
            'Info log for PUT request start'
        );
        $logger->error_like(
            qr/PUT request failed: 409 Conflict to https:\/\/test\.example\.com\/items\/999 \[context: update_item\]/,
            'Error log contains status, endpoint, and context'
        );

        # Verify debug logging for response content
        # First debug message is the request debug, second is request data, third is the response body debug
        $logger->debug_like(
            qr/PUT request headers: Authorization=Bearer \[REDACTED\], Content-Type=application\/json/,
            'Debug log for PUT request'
        );
        $logger->debug_like(
            qr/Request data: .*title.*Updated Title/,
            'Debug log for PUT request data'
        );
        $logger->debug_like(
            qr/PUT request failed response body \[context: update_item\]: .*Version conflict/,
            'Debug log contains response body with context'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed PUT request - Not found' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'PUT', 'https://test.example.com/items/nonexistent' );

                my $response = HTTP::Response->new( 404, 'Not Found' );
                $response->request($request);
                $response->content('{"error": "Item not found", "id": "nonexistent"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test not found PUT request
        my $response = $client->put_request(
            {
                endpoint => '/items/nonexistent',
                data     => { title => 'Updated Title' }
            }
        );

        # Verify response
        ok( !$response->is_success, 'PUT response indicates failure' );
        is( $response->code, 404, 'PUT response has correct not found status code' );

        # Verify error logging (without context this time)
        $logger->info_like(
            qr/Making PUT request to https:\/\/test\.example\.com\/items\/nonexistent/,
            'Info log for PUT request start'
        );
        $logger->error_like(
            qr/PUT request failed: 404 Not Found to https:\/\/test\.example\.com\/items\/nonexistent$/,
            'Error log contains status and endpoint (no context)'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };
};

subtest 'get_request() tests' => sub {
    plan tests => 4;

    my $client_mock = Test::MockModule->new('RapidoILL::APIHttpClient');
    $client_mock->mock( 'get_token', sub { return 'the_token'; } );

    subtest 'Successful GET request' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content('{"id": "123", "title": "Test Item", "status": "active"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test successful GET request
        my $response = $client->get_request( { endpoint => '/items/123' } );

        # Verify response
        ok( $response->is_success, 'GET response indicates success' );
        is( $response->code, 200, 'GET response has correct status code' );

        # Verify logging
        $logger->info_like(
            qr/Making GET request to https:\/\/test\.example\.com\/items\/123/,
            'Info log for GET request start'
        );
        $logger->info_like( qr/GET request successful: 200 OK/, 'Info log for successful GET' );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'GET request with query parameters and context' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $response = HTTP::Response->new( 200, 'OK' );
                $response->content(
                    '{"items": [{"id": "1", "title": "Item 1"}, {"id": "2", "title": "Item 2"}], "total": 2}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test GET request with query parameters and context
        my $response = $client->get_request(
            {
                endpoint => '/items',
                query    => { status => 'active', limit => 10 },
                context  => 'search_items'
            }
        );

        # Verify response
        ok( $response->is_success, 'GET response with query and context indicates success' );
        is( $response->code, 200, 'GET response has correct status code' );

        # Verify context appears in logs
        $logger->info_like(
            qr/Making GET request to https:\/\/test\.example\.com\/items/,
            'Info log for GET request start'
        );
        $logger->info_like(
            qr/GET request successful: 200 OK \[context: search_items\]/,
            'Info log includes context for successful GET'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed GET request - HTTP error' => sub {
        plan tests => 6;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'GET', 'https://test.example.com/items/999' );

                my $response = HTTP::Response->new( 404, 'Not Found' );
                $response->request($request);
                $response->content('{"error": "Item not found", "id": "999"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test failed GET request
        my $response = $client->get_request(
            {
                endpoint => '/items/999',
                context  => 'fetch_item'
            }
        );

        # Verify response
        ok( !$response->is_success, 'GET response indicates failure' );
        is( $response->code, 404, 'GET response has correct error status code' );

        # Verify error logging
        $logger->info_like(
            qr/Making GET request to https:\/\/test\.example\.com\/items\/999/,
            'Info log for GET request start'
        );
        $logger->error_like(
            qr/GET request failed: 404 Not Found to https:\/\/test\.example\.com\/items\/999 \[context: fetch_item\]/,
            'Error log contains status, endpoint, and context'
        );

        # Verify debug logging for response content
        # First debug message is the request debug, second is the response body debug
        $logger->debug_like(
            qr/GET request headers: Authorization=Bearer \[REDACTED\], Accept=application\/json/,
            'Debug log for GET request'
        );
        $logger->debug_like(
            qr/GET request failed response body \[context: fetch_item\]: .*Item not found/,
            'Debug log contains response body with context'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };

    subtest 'Failed GET request - Unauthorized' => sub {
        plan tests => 4;

        # Mock LWP::UserAgent before creating the client
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        my $mock_ua = bless {}, 'LWP::UserAgent';

        $ua_mock->mock( 'new', sub { return $mock_ua; } );
        $ua_mock->mock(
            'request',
            sub {
                my $request = HTTP::Request->new( 'GET', 'https://test.example.com/admin/settings' );

                my $response = HTTP::Response->new( 401, 'Unauthorized' );
                $response->request($request);
                $response->content('{"error": "Authentication required", "message": "Invalid or expired token"}');
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                plugin        => $plugin,
                pod           => "test-pod",
                dev_mode      => 1,
            }
        );

        $logger->clear();

        # Test unauthorized GET request
        my $response = $client->get_request( { endpoint => '/admin/settings' } );

        # Verify response
        ok( !$response->is_success, 'GET response indicates failure' );
        is( $response->code, 401, 'GET response has correct unauthorized status code' );

        # Verify error logging (without context this time)
        $logger->info_like(
            qr/Making GET request to https:\/\/test\.example\.com\/admin\/settings/,
            'Info log for GET request start'
        );
        $logger->error_like(
            qr/GET request failed: 401 Unauthorized to https:\/\/test\.example\.com\/admin\/settings$/,
            'Error log contains status and endpoint (no context)'
        );

        # Clean up mock
        $ua_mock->unmock_all();
    };
};

subtest 'Token persistence tests' => sub {
    plan tests => 4;

    subtest 'Token saving to database' => sub {
        plan tests => 4;
        
        my $stored_data = {};
        my $plugin = Test::MockObject->new();
        $plugin->mock('store_data', sub {
            my ($self, $data) = @_;
            %$stored_data = (%$stored_data, %$data);
        });
        
        my $client = RapidoILL::APIHttpClient->new({
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            plugin        => $plugin,
            pod           => "test-pod",
            dev_mode      => 1,
        });
        
        # Set up token data
        $client->{access_token} = 'test_token_123';
        $client->{expiration} = DateTime->now()->add(seconds => 600);
        
        # Save token
        $client->_save_token_to_database();
        
        # Verify storage
        my $token_key = "access_token_test-pod";
        ok(exists $stored_data->{$token_key}, 'Token data stored with correct pod-specific key');
        
        my $token_data = $stored_data->{$token_key};
        is($token_data->{access_token}, 'test_token_123', 'Access token stored correctly');
        ok($token_data->{expiration_epoch}, 'Expiration epoch stored');
        ok($token_data->{cached_at_epoch}, 'Cache timestamp stored');
    };

    subtest 'Token loading from database' => sub {
        plan tests => 5;
        
        my $future_time = DateTime->now()->add(seconds => 600);
        my $token_key = "access_token_test-pod";
        my $stored_data = {
            $token_key => {
                access_token     => 'cached_token_456',
                expiration_epoch => $future_time->epoch(),
                cached_at_epoch  => DateTime->now()->epoch(),
            }
        };
        
        my $plugin = Test::MockObject->new();
        $plugin->mock('retrieve_data', sub {
            my ($self, $key) = @_;
            return $stored_data->{$key};
        });
        
        my $client = RapidoILL::APIHttpClient->new({
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            plugin        => $plugin,
            pod           => "test-pod",
            dev_mode      => 1,
        });
        
        # Load token
        $client->_load_token_from_database();
        
        # Verify loading
        is($client->{access_token}, 'cached_token_456', 'Access token loaded correctly');
        isa_ok($client->{expiration}, 'DateTime', 'Expiration loaded as DateTime object');
        is($client->{expiration}->epoch(), $future_time->epoch(), 'Expiration time matches stored value');
        
        # Test with invalid data
        $stored_data->{$token_key} = { access_token => 'token', expiration_epoch => 'invalid' };
        $client->_load_token_from_database();
        
        ok(!defined $client->{access_token}, 'Invalid cached data cleared on parse error');
        ok(!defined $client->{expiration}, 'Invalid expiration cleared on parse error');
    };

    subtest 'Multi-pod token isolation' => sub {
        plan tests => 4;
        
        my $stored_data = {};
        my $plugin = Test::MockObject->new();
        $plugin->mock('store_data', sub {
            my ($self, $data) = @_;
            %$stored_data = (%$stored_data, %$data);
        });
        $plugin->mock('retrieve_data', sub {
            my ($self, $key) = @_;
            return $stored_data->{$key};
        });
        
        # Create clients for different pods
        my $client1 = RapidoILL::APIHttpClient->new({
            base_url      => 'https://pod1.example.com',
            client_id     => 'client1',
            client_secret => 'secret1',
            plugin        => $plugin,
            pod           => "pod1",
            dev_mode      => 1,
        });
        
        my $client2 = RapidoILL::APIHttpClient->new({
            base_url      => 'https://pod2.example.com',
            client_id     => 'client2',
            client_secret => 'secret2',
            plugin        => $plugin,
            pod           => "pod2",
            dev_mode      => 1,
        });
        
        # Set different tokens for each pod
        $client1->{access_token} = 'token_pod1';
        $client1->{expiration} = DateTime->now()->add(seconds => 600);
        $client1->_save_token_to_database();
        
        $client2->{access_token} = 'token_pod2';
        $client2->{expiration} = DateTime->now()->add(seconds => 600);
        $client2->_save_token_to_database();
        
        # Verify separate storage
        ok(exists $stored_data->{"access_token_pod1"}, 'Pod1 token stored separately');
        ok(exists $stored_data->{"access_token_pod2"}, 'Pod2 token stored separately');
        is($stored_data->{"access_token_pod1"}->{access_token}, 'token_pod1', 'Pod1 token correct');
        is($stored_data->{"access_token_pod2"}->{access_token}, 'token_pod2', 'Pod2 token correct');
    };

    subtest 'Database access optimization for long-running processes' => sub {
        plan tests => 4;
        
        my $db_access_count = 0;
        my $stored_data = {
            "access_token_test-pod" => {
                access_token     => 'cached_token_789',
                expiration_epoch => DateTime->now()->add(seconds => 600)->epoch(),
                cached_at_epoch  => DateTime->now()->epoch(),
            }
        };
        
        my $plugin = Test::MockObject->new();
        $plugin->mock('retrieve_data', sub {
            my ($self, $key) = @_;
            $db_access_count++;
            return $stored_data->{$key};
        });
        
        my $client = RapidoILL::APIHttpClient->new({
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            plugin        => $plugin,
            pod           => "test-pod",
            # No dev_mode - we want real token loading behavior
        });
        
        # First call should load from database
        my $token1 = $client->get_token();
        is($db_access_count, 1, 'First get_token() call loads from database');
        is($token1, 'cached_token_789', 'Token loaded correctly from database');
        
        # Subsequent calls should use in-memory cache
        my $token2 = $client->get_token();
        my $token3 = $client->get_token();
        
        is($db_access_count, 1, 'Subsequent get_token() calls do not hit database');
        is($token2, 'cached_token_789', 'In-memory cached token returned');
    };
};
