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

use Test::More tests => 3;
use Test::Exception;
use Test::NoWarnings;

use Koha::Database;

use t::lib::TestBuilder;
use t::lib::Mocks::Rapido;

use RapidoILL::CircActions;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'item() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    subtest 'Returns correct item for valid itemnumber' => sub {
        plan tests => 3;

        # Create a test item
        my $item = $builder->build_sample_item();

        # Create CircAction with itemId as itemnumber
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_001',
                pod           => 'test_pod',
                itemId        => $item->itemnumber,
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->item();

        ok( $result, 'item() returns a result' );
        isa_ok( $result, 'Koha::Item', 'Result is a Koha::Item object' );
        is( $result->itemnumber, $item->itemnumber, 'Returns correct item by itemnumber' );
    };

    subtest 'Returns undef for invalid itemnumber' => sub {
        plan tests => 1;

        # Create CircAction with non-existent itemId
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_002',
                pod           => 'test_pod',
                itemId        => 999999,
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->item();

        is( $result, undef, 'item() returns undef for non-existent itemnumber' );
    };

    subtest 'Returns undef for undefined itemId' => sub {
        plan tests => 1;

        # Create CircAction without itemId
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_003',
                pod           => 'test_pod',
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->item();

        is( $result, undef, 'item() returns undef when itemId is undefined' );
    };

    $schema->storage->txn_rollback;
};

subtest 'ill_request() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    subtest 'Returns correct ILL request for valid illrequest_id' => sub {
        plan tests => 3;

        # Create a test ILL request
        my $ill_request = $builder->build_object( { class => 'Koha::ILL::Requests' } );

        # Create CircAction with illrequest_id
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_004',
                pod           => 'test_pod',
                illrequest_id => $ill_request->illrequest_id,
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->ill_request();

        ok( $result, 'ill_request() returns a result' );
        isa_ok( $result, 'Koha::ILL::Request', 'Result is a Koha::ILL::Request object' );
        is( $result->illrequest_id, $ill_request->illrequest_id, 'Returns correct ILL request by ID' );
    };

    subtest 'Returns undef for invalid illrequest_id' => sub {
        plan tests => 1;

        # Create CircAction with non-existent illrequest_id
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_005',
                pod           => 'test_pod',
                illrequest_id => 999999,
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->ill_request();

        is( $result, undef, 'ill_request() returns undef for non-existent illrequest_id' );
    };

    subtest 'Returns undef for undefined illrequest_id' => sub {
        plan tests => 1;

        # Create CircAction without illrequest_id
        my $action = RapidoILL::CircAction->new(
            {
                circId        => 'TEST_CIRC_006',
                pod           => 'test_pod',
                circStatus    => 'ACTIVE',
                lastCircState => 'ITEM_SHIPPED',
            }
        );

        my $result = $action->ill_request();

        is( $result, undef, 'ill_request() returns undef when illrequest_id is undefined' );
    };

    $schema->storage->txn_rollback;
};
