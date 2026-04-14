#!/usr/bin/env perl

# Copyright 2026 ByWater Solutions
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
use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Database;
use Koha::Patrons;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new();

subtest 'create_with_patron' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new();
    my $config = $plugin->pod_config( t::lib::Mocks::Rapido::POD );

    my $agency = $plugin->get_agency_patrons->create_with_patron(
        {
            pod           => t::lib::Mocks::Rapido::POD,
            agency_id     => 'TEST001',
            description   => 'Test Agency',
            local_server  => '12345',
            library_id    => $config->{partners_library_id},
            category_code => $config->{partners_category},
        }
    );

    ok( $agency, 'Agency created' );
    is( $agency->pod,       t::lib::Mocks::Rapido::POD, 'Correct pod' );
    is( $agency->agency_id, 'TEST001',                   'Correct agency_id' );
    is( $agency->description, 'Test Agency',             'Correct description' );
    ok( $agency->patron_id, 'patron_id is set' );

    my $patron = $agency->patron;
    ok( $patron, 'Patron exists' );
    is( $patron->cardnumber, 'ILL_' . t::lib::Mocks::Rapido::POD . '_TEST001', 'Correct cardnumber' );
    is( $patron->surname,    'Test Agency (TEST001)',    'Correct surname' );

    $schema->storage->txn_rollback;
};

subtest 'update_with_patron' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new();
    my $config = $plugin->pod_config( t::lib::Mocks::Rapido::POD );

    my $agency = $plugin->get_agency_patrons->create_with_patron(
        {
            pod           => t::lib::Mocks::Rapido::POD,
            agency_id     => 'UPD001',
            description   => 'Original Name',
            local_server  => '12345',
            library_id    => $config->{partners_library_id},
            category_code => $config->{partners_category},
        }
    );

    $plugin->get_agency_patrons->update_with_patron(
        $agency,
        {
            description  => 'Updated Name',
            local_server => '99999',
        }
    );

    $agency->discard_changes;
    is( $agency->description,  'Updated Name', 'Agency description updated' );
    is( $agency->local_server, '99999',        'Agency local_server updated' );

    my $patron = $agency->patron;
    is( $patron->surname,    'Updated Name (UPD001)',                            'Patron surname updated' );
    is( $patron->cardnumber, 'ILL_' . t::lib::Mocks::Rapido::POD . '_UPD001',  'Patron cardnumber correct' );

    # Verify partial update preserves existing values
    $plugin->get_agency_patrons->update_with_patron(
        $agency,
        { description => 'Another Update' }
    );
    $agency->discard_changes;
    is( $agency->description,  'Another Update', 'Description updated again' );
    is( $agency->local_server, '99999',          'local_server preserved' );

    $schema->storage->txn_rollback;
};

subtest 'patron accessor' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    my $plugin = t::lib::Mocks::Rapido->new();
    my $config = $plugin->pod_config( t::lib::Mocks::Rapido::POD );

    my $agency = $plugin->get_agency_patrons->create_with_patron(
        {
            pod           => t::lib::Mocks::Rapido::POD,
            agency_id     => 'PAT001',
            description   => 'Patron Test',
            local_server  => '12345',
            library_id    => $config->{partners_library_id},
            category_code => $config->{partners_category},
        }
    );

    my $patron = $agency->patron;
    isa_ok( $patron, 'Koha::Patron' );
    is( $patron->borrowernumber, $agency->patron_id, 'Patron matches patron_id' );
    is( $patron->branchcode, $config->{partners_library_id}, 'Patron has correct branchcode' );

    $schema->storage->txn_rollback;
};
