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

use Test::More tests => 5;
use Test::Exception;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::APIHttpClient');
}

subtest 'APIHttpClient instantiation' => sub {
    plan tests => 2;

    subtest 'Successful instantiation' => sub {
        plan tests => 2;

        my $client = RapidoILL::APIHttpClient->new(
            {
                base_url      => 'https://test.example.com',
                client_id     => 'test_client',
                client_secret => 'test_secret',
                dev_mode      => 1,    # Skip token refresh in dev mode
            }
        );

        isa_ok( $client, 'RapidoILL::APIHttpClient', 'APIHttpClient instance created' );
        is( $client->{base_url}, 'https://test.example.com', 'Base URL set correctly' );
    };

    subtest 'Missing parameters' => sub {
        plan tests => 3;

        throws_ok {
            RapidoILL::APIHttpClient->new( {} );
        }
        qr/Missing parameter: base_url/, 'Dies when base_url missing';

        throws_ok {
            RapidoILL::APIHttpClient->new( { base_url => 'https://test.com' } );
        }
        qr/Missing parameter: client_id/, 'Dies when client_id missing';

        throws_ok {
            RapidoILL::APIHttpClient->new(
                {
                    base_url  => 'https://test.com',
                    client_id => 'test'
                }
            );
        }
        qr/Missing parameter: client_secret/, 'Dies when client_secret missing';
    };
};

subtest 'Dev mode behavior' => sub {
    plan tests => 1;

    my $client_no_plugin = RapidoILL::APIHttpClient->new(
        {
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            dev_mode      => 1,
        }
    );

    ok( $client_no_plugin->{dev_mode}, 'Dev mode enabled' );
};

subtest 'Token management methods' => sub {
    plan tests => 2;

    my $client = RapidoILL::APIHttpClient->new(
        {
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            dev_mode      => 1,
        }
    );

    can_ok( $client, 'get_token' );
    can_ok( $client, 'is_token_expired' );
};

subtest 'HTTP request methods' => sub {
    plan tests => 4;

    my $client = RapidoILL::APIHttpClient->new(
        {
            base_url      => 'https://test.example.com',
            client_id     => 'test_client',
            client_secret => 'test_secret',
            dev_mode      => 1,
        }
    );

    can_ok( $client, 'get_request' );
    can_ok( $client, 'post_request' );
    can_ok( $client, 'put_request' );
    can_ok( $client, 'delete_request' );
};
