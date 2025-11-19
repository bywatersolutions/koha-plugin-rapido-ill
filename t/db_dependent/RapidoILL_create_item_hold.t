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

use Test::More tests => 6;
use Test::NoWarnings;
use Test::Exception;
use Test::MockObject;

use RapidoILL::CircActions;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

# Enable ILL module for testing
t::lib::Mocks::mock_preference( 'ILLModule', 1 );

# Create test data
my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
my $library3 = $builder->build_object( { class => 'Koha::Libraries' } );
my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
my $biblio   = $builder->build_sample_biblio();
my $item     = $builder->build_sample_item(
    {
        biblionumber  => $biblio->biblionumber,
        homebranch    => $library2->branchcode,
        holdingbranch => $library3->branchcode,
    }
);

# Create patron agency mapping using direct schema access
$schema->resultset('KohaPluginComBywatersolutionsRapidoillAgencyToPatron')->create(
    {
        patron_id   => $patron->borrowernumber,
        agency_id   => 'TEST_AGENCY',
        pod         => t::lib::Mocks::Rapido::POD,
        description => 'Test agency mapping',
    }
);

subtest 'create_item_hold with default pickup_location_strategy (partners_library)' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library1,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $action_mock = Test::MockModule->new('RapidoILL::CircAction');
    $action_mock->mock( 'store', sub { return 1; } );

    my $action = RapidoILL::CircAction->new(
        {
            pod                => t::lib::Mocks::Rapido::POD,
            itemId             => $item->id,
            patronAgencyCode   => 'TEST_AGENCY',
            author             => 'Test Author',
            title              => 'Test Title',
            borrowerCode       => 'TEST_BORROWER',
            callNumber         => '123.45',
            circ_action_id     => 1,
            circId             => 'CIRC123',
            circStatus         => 'ACTIVE',
            dateCreated        => '2025-10-15T15:00:00Z',
            dueDateTime        => '2025-11-15T15:00:00Z',
            itemAgencyCode     => 'ITEM_AGENCY',
            itemBarcode        => $item->barcode,
            lastCircState      => 'REQUESTED',
            lastUpdated        => '2025-10-15T15:00:00Z',
            lenderCode         => 'LENDER',
            needBefore         => '2025-12-15T15:00:00Z',
            patronId           => 'PATRON123',
            patronName         => 'Test Patron',
            pickupLocation     => $library1->branchcode,
            puaLocalServerCode => '12345',
        }
    );

    my $req;
    lives_ok {
        $req = $plugin->create_item_hold($action);
    }
    'create_item_hold succeeds with default strategy';

    ok( $req, 'Request object returned' );
    isa_ok( $req, 'Koha::ILL::Request', 'Returned object is ILL request' );
    is( $req->branchcode, $library1->branchcode, 'Request uses partners_library_id as pickup location' );

    $schema->storage->txn_rollback;
};

subtest 'create_item_hold with pickup_location_strategy = homebranch' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library                  => $library1,
            category                 => $category,
            itemtype                 => $itemtype,
            pickup_location_strategy => 'homebranch',
        }
    );

    my $action_mock = Test::MockModule->new('RapidoILL::CircAction');
    $action_mock->mock( 'store', sub { return 1; } );

    my $action = RapidoILL::CircAction->new(
        {
            pod                => t::lib::Mocks::Rapido::POD,
            itemId             => $item->id,
            patronAgencyCode   => 'TEST_AGENCY',
            author             => 'Test Author',
            title              => 'Test Title',
            borrowerCode       => 'TEST_BORROWER',
            callNumber         => '123.45',
            circ_action_id     => 1,
            circId             => 'CIRC123',
            circStatus         => 'ACTIVE',
            dateCreated        => '2025-10-15T15:00:00Z',
            dueDateTime        => '2025-11-15T15:00:00Z',
            itemAgencyCode     => 'ITEM_AGENCY',
            itemBarcode        => $item->barcode,
            lastCircState      => 'REQUESTED',
            lastUpdated        => '2025-10-15T15:00:00Z',
            lenderCode         => 'LENDER',
            needBefore         => '2025-12-15T15:00:00Z',
            patronId           => 'PATRON123',
            patronName         => 'Test Patron',
            pickupLocation     => $library1->branchcode,
            puaLocalServerCode => '12345',
        }
    );

    my $req = $plugin->create_item_hold($action);
    ok( $req, 'Request created with homebranch strategy' );
    is( $req->branchcode, $library2->branchcode, 'Request uses item homebranch as pickup location' );

    $schema->storage->txn_rollback;
};

subtest 'create_item_hold with pickup_location_strategy = holdingbranch' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library                  => $library1,
            category                 => $category,
            itemtype                 => $itemtype,
            pickup_location_strategy => 'holdingbranch',
        }
    );

    my $action_mock = Test::MockModule->new('RapidoILL::CircAction');
    $action_mock->mock( 'store', sub { return 1; } );

    my $action = RapidoILL::CircAction->new(
        {
            pod                => t::lib::Mocks::Rapido::POD,
            itemId             => $item->id,
            patronAgencyCode   => 'TEST_AGENCY',
            author             => 'Test Author',
            title              => 'Test Title',
            borrowerCode       => 'TEST_BORROWER',
            callNumber         => '123.45',
            circ_action_id     => 1,
            circId             => 'CIRC123',
            circStatus         => 'ACTIVE',
            dateCreated        => '2025-10-15T15:00:00Z',
            dueDateTime        => '2025-11-15T15:00:00Z',
            itemAgencyCode     => 'ITEM_AGENCY',
            itemBarcode        => $item->barcode,
            lastCircState      => 'REQUESTED',
            lastUpdated        => '2025-10-15T15:00:00Z',
            lenderCode         => 'LENDER',
            needBefore         => '2025-12-15T15:00:00Z',
            patronId           => 'PATRON123',
            patronName         => 'Test Patron',
            pickupLocation     => $library1->branchcode,
            puaLocalServerCode => '12345',
        }
    );

    my $req = $plugin->create_item_hold($action);
    ok( $req, 'Request created with holdingbranch strategy' );
    is( $req->branchcode, $library3->branchcode, 'Request uses item holdingbranch as pickup location' );

    $schema->storage->txn_rollback;
};

subtest 'create_item_hold with invalid pickup_location_strategy falls back to partners_library' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library                  => $library1,
            category                 => $category,
            itemtype                 => $itemtype,
            pickup_location_strategy => 'invalid_strategy',
        }
    );

    my $action_mock = Test::MockModule->new('RapidoILL::CircAction');
    $action_mock->mock( 'store', sub { return 1; } );

    my $action = RapidoILL::CircAction->new(
        {
            pod                => t::lib::Mocks::Rapido::POD,
            itemId             => $item->id,
            patronAgencyCode   => 'TEST_AGENCY',
            author             => 'Test Author',
            title              => 'Test Title',
            borrowerCode       => 'TEST_BORROWER',
            callNumber         => '123.45',
            circ_action_id     => 1,
            circId             => 'CIRC123',
            circStatus         => 'ACTIVE',
            dateCreated        => '2025-10-15T15:00:00Z',
            dueDateTime        => '2025-11-15T15:00:00Z',
            itemAgencyCode     => 'ITEM_AGENCY',
            itemBarcode        => $item->barcode,
            lastCircState      => 'REQUESTED',
            lastUpdated        => '2025-10-15T15:00:00Z',
            lenderCode         => 'LENDER',
            needBefore         => '2025-12-15T15:00:00Z',
            patronId           => 'PATRON123',
            patronName         => 'Test Patron',
            pickupLocation     => $library1->branchcode,
            puaLocalServerCode => '12345',
        }
    );

    my $req = $plugin->create_item_hold($action);
    ok( $req, 'Request created with invalid strategy' );
    is( $req->branchcode, $library1->branchcode, 'Invalid strategy falls back to partners_library_id' );

    $schema->storage->txn_rollback;
};

subtest 'create_item_hold throws exception for unknown item' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library1,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $mock_action = Test::MockObject->new();
    $mock_action->mock( 'pod',    sub { return t::lib::Mocks::Rapido::POD; } );
    $mock_action->mock( 'itemId', sub { return 99999; } );
    $mock_action->mock( 'item',   sub { return; } );

    throws_ok {
        $plugin->create_item_hold($mock_action);
    }
    'RapidoILL::Exception::UnknownItemId', 'Throws exception for unknown item';

    $schema->storage->txn_rollback;
};

$schema->storage->txn_rollback;
