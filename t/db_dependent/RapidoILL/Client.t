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
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 3;
use Test::Exception;
use Test::NoWarnings;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;
use t::lib::Mocks::Client;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::Client');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'lender_cancel() tests' => sub {
    plan tests => 3;

    subtest 'Successful API request' => sub {
        plan tests => 4;

        $schema->storage->txn_begin;

        # Setup test data with dev_mode disabled
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype,
                dev_mode => 0
            }
        );

        # Setup HTTP client mock
        my $client_mock = t::lib::Mocks::Client->new($plugin);

        # Create client using plugin method
        my $client = $plugin->get_client(t::lib::Mocks::Rapido::POD);

        # Test parameters - using integer to make test fail
        my $test_params = {
            circId     => 'TEST_CIRC_123',
            localBibId => 456,               # Integer instead of string
            patronName => 'Test Patron'
        };

        # Execute method
        lives_ok {
            $client->lender_cancel($test_params);
        }
        'lender_cancel executes without error';

        # Verify API request parameters - expecting string type
        $client_mock->endpoint_is( '/view/broker/circ/TEST_CIRC_123/lendercancel', 'Correct endpoint called' );
        $client_mock->data_type_is( 'localBibId', 'string', 'localBibId sent as string not integer' );
        $client_mock->context_is( 'lender_cancel', 'Correct context set' );

        $schema->storage->txn_rollback;
    };

    subtest 'Dev mode skips API request' => sub {
        plan tests => 2;

        $schema->storage->txn_begin;

        # Setup test data
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        # Setup HTTP client mock
        my $client_mock = t::lib::Mocks::Client->new($plugin);

        # Create client using plugin method
        my $client = $plugin->get_client(t::lib::Mocks::Rapido::POD);

        # Test parameters
        my $test_params = {
            circId     => 'TEST_CIRC_123',
            localBibId => 'BIB_456',
            patronName => 'Test Patron'
        };

        # Execute method (dev_mode is true in test config)
        lives_ok {
            $client->lender_cancel($test_params);
        }
        'lender_cancel executes without error in dev mode';

        is( $client_mock->request_count(), 0, 'API request skipped in dev mode' );

        $schema->storage->txn_rollback;
    };

    subtest 'Parameter validation' => sub {
        plan tests => 3;

        $schema->storage->txn_begin;

        # Setup test data
        my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
        my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
        my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

        my $plugin = t::lib::Mocks::Rapido->new(
            {
                library  => $library,
                category => $category,
                itemtype => $itemtype
            }
        );

        # Create client
        # Create client using plugin method
        my $client = $plugin->get_client(t::lib::Mocks::Rapido::POD);

        # Test missing circId
        throws_ok {
            $client->lender_cancel(
                {
                    localBibId => 'BIB_456',
                    patronName => 'Test Patron'
                }
            );
        }
        'RapidoILL::Exception::MissingParameter', 'Missing circId throws exception';

        # Test missing localBibId
        throws_ok {
            $client->lender_cancel(
                {
                    circId     => 'TEST_CIRC_123',
                    patronName => 'Test Patron'
                }
            );
        }
        'RapidoILL::Exception::MissingParameter', 'Missing localBibId throws exception';

        # Test missing patronName
        throws_ok {
            $client->lender_cancel(
                {
                    circId     => 'TEST_CIRC_123',
                    localBibId => 'BIB_456'
                }
            );
        }
        'RapidoILL::Exception::MissingParameter', 'Missing patronName throws exception';

        $schema->storage->txn_rollback;
    };
};
