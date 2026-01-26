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

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Biblios;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

subtest 'delete_virtual_biblio - successful deletion' => sub {
    plan tests => 3;

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $biblio   = $builder->build_sample_biblio();

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $biblionumber = $biblio->biblionumber;
    my $error        = $plugin->delete_virtual_biblio({ biblio => $biblio, context => 'test' });

    is( $error, undef, 'No error returned on successful deletion' );

    my $deleted_biblio = Koha::Biblios->find($biblionumber);
    is( $deleted_biblio, undef, 'Biblio was deleted from database' );

    my $deleted_record = $schema->resultset('Deletedbiblio')->find($biblionumber);
    ok( $deleted_record, 'Biblio was moved to deletedbiblio table' );
};

subtest 'delete_virtual_biblio - with items' => sub {
    plan tests => 3;

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $biblio   = $builder->build_sample_biblio();
    my $item     = $builder->build_sample_item( { biblionumber => $biblio->biblionumber } );

    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    my $biblionumber = $biblio->biblionumber;
    my $error        = $plugin->delete_virtual_biblio({ biblio => $biblio });

    is( $error, undef, 'No error when items are deleted automatically' );

    my $deleted_biblio = Koha::Biblios->find($biblionumber);
    is( $deleted_biblio, undef, 'Biblio was deleted from database' );

    my $deleted_item = Koha::Items->find( $item->itemnumber );
    is( $deleted_item, undef, 'Item was deleted automatically' );
};

subtest 'delete_virtual_biblio - invalid parameter' => sub {
    plan tests => 1;

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

    throws_ok { $plugin->delete_virtual_biblio( { context => 'test' } ) }
        'RapidoILL::Exception::MissingParameter',
        'Exception when biblio parameter is missing';
};

$schema->storage->txn_rollback;
