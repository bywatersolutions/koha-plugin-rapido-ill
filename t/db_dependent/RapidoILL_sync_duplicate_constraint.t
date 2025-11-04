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
use Test::More tests => 5;
use Test::MockModule;
use Test::NoWarnings;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

BEGIN {
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    use_ok('RapidoILL::CircAction');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'is_exact_duplicate() tests' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $action_data = {
        circId        => 'TEST001',
        pod           => 'test_pod',
        circStatus    => 'ACTIVE',
        lastCircState => 'PATRON_HOLD',
        lastUpdated   => time(),
        borrowerCode  => 'test_borrower',
        lenderCode    => 'test_lender',
        itemId        => 'TEST_ITEM_123',
        patronId      => 'TEST_PATRON_456',
        dateCreated   => time(),
        callNumber    => 'TEST_CALL_123',
    };

    my $action = RapidoILL::CircAction->new($action_data);

    ok( !$plugin->is_exact_duplicate($action), 'New action is not duplicate' );

    $action->store();

    my $duplicate_action = RapidoILL::CircAction->new($action_data);
    ok( $plugin->is_exact_duplicate($duplicate_action), 'Exact duplicate detected' );

    $schema->storage->txn_rollback;
};

subtest 'sync_circ_requests() duplicate handling' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    # Pre-create a CircAction to test duplicate detection
    my $existing_action = RapidoILL::CircAction->new(
        {
            circId        => 'TEST002',
            pod           => t::lib::Mocks::Rapido::POD,
            circStatus    => 'CREATED',
            lastCircState => 'PATRON_HOLD',
            lastUpdated   => time(),
            borrowerCode  => 'TEST_AGENCY',
            lenderCode    => '12345',
            itemId        => '',
            patronId      => 'TEST_PATRON_456',
            dateCreated   => time(),
            callNumber    => 'TEST_CALL_123',
            title         => 'Test Book Title',
            author        => 'Test Author',
        }
    );
    $existing_action->store();

    # Mock client to return the same data (should be detected as duplicate)
    my $mock_client = Test::MockModule->new('RapidoILL::Client');
    $mock_client->mock(
        'circulation_requests',
        sub {
            return [
                {
                    circId        => 'TEST002',
                    circStatus    => 'CREATED',
                    lastCircState => 'PATRON_HOLD',
                    lastUpdated   => time() + 1,          # Different timestamp
                    borrowerCode  => 'TEST_AGENCY',
                    lenderCode    => '12345',
                    itemId        => '',
                    patronId      => 'TEST_PATRON_456',
                    dateCreated   => time(),
                    callNumber    => 'TEST_CALL_123',
                    title         => 'Test Book Title',
                    author        => 'Test Author',
                }
            ];
        }
    );

    my $mock_plugin = Test::MockModule->new('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    $mock_plugin->mock( 'get_client', sub { return bless {}, 'RapidoILL::Client'; } );

    # Sync should skip duplicate
    my $results = $plugin->sync_circ_requests( { pod => t::lib::Mocks::Rapido::POD } );
    is( $results->{skipped},                  1,              'Sync skips duplicate' );
    is( $results->{messages}->[0]->{message}, 'Duplicate ID', 'Correct skip message' );

    $schema->storage->txn_rollback;
};
