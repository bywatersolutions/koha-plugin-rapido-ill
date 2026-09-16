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

# Exercises the selection logic used by
# scripts/cleanup_duplicate_virtual_records.pl : a duplicate virtual pair
# (both sides virtual, base orphaned) is selected and its orphan deleted,
# while a legitimate collision with a real owned item is left untouched.

use Modern::Perl;

use Test::More tests => 2;
use Test::NoWarnings;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Biblios;
use Koha::Items;
use Koha::ILL::Requests;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $VIRTUAL_NOTE = 'Additional processing required (ILL)';

# Replicates the candidate-selection used by the cleanup script: returns the
# base (orphan) biblionumber to delete for a given suffix item, or a skip reason.
sub classify_pair {
    my ( $suffix_item, $backend ) = @_;

    my $barcode = $suffix_item->barcode;
    return { skip => 'not a suffix barcode' } unless $barcode =~ /^(.+)-\d+$/;
    my $base_barcode = $1;

    my $base_item = Koha::Items->search(
        {
            barcode             => $base_barcode,
            itemnotes_nonpublic => $VIRTUAL_NOTE,
        }
    )->next;
    return { skip => 'base not virtual (legit collision)' } unless $base_item;

    my $suffix_biblio_id = $suffix_item->biblionumber;
    my $base_biblio_id   = $base_item->biblionumber;

    my $suffix_reqs = Koha::ILL::Requests->search(
        { biblio_id => $suffix_biblio_id, backend => $backend } );
    my $suffix_req_count = $suffix_reqs->count;
    my $suffix_req       = $suffix_reqs->next;

    my $base_ref_count =
        Koha::ILL::Requests->search( { biblio_id => $base_biblio_id } )->count;

    return { skip => 'suffix biblio not referenced' }         unless $suffix_req;
    return { skip => 'suffix biblio multiply referenced' }    if $suffix_req_count > 1;
    return { skip => 'base biblio still referenced' }         if $base_ref_count;
    return { skip => 'base item checked out' }                if $base_item->checkout;
    return { skip => 'suffix item checked out' }              if $suffix_item->checkout;

    return { delete_biblio => $base_biblio_id, keep_biblio => $suffix_biblio_id };
}

subtest 'bug pair selected & deleted; legit collision untouched' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );

    my $plugin  = t::lib::Mocks::Rapido->new(
        { library => $library, category => $category, itemtype => $itemtype } );
    my $backend = $plugin->ill_backend();

    my $bc = 'DUP' . int( rand(1_000_000) );

    # --- Bug pair: base and suffix are BOTH virtual items ---------------------
    my $base_biblio = $builder->build_sample_biblio();
    my $base_item   = $builder->build_sample_item(
        {
            biblionumber        => $base_biblio->biblionumber,
            barcode             => $bc,
            itemnotes_nonpublic => $VIRTUAL_NOTE,
        }
    );
    my $suffix_biblio = $builder->build_sample_biblio();
    my $suffix_item   = $builder->build_sample_item(
        {
            biblionumber        => $suffix_biblio->biblionumber,
            barcode             => "$bc-1",
            itemnotes_nonpublic => $VIRTUAL_NOTE,
        }
    );

    # The ILL request points to the -1 (suffix) biblio; base is the orphan.
    $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                backend        => $backend,
                biblio_id      => $suffix_biblio->biblionumber,
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    # --- Legit collision: suffix is virtual, base is a REAL owned item --------
    my $rbc         = 'REAL' . int( rand(1_000_000) );
    my $real_biblio = $builder->build_sample_biblio();
    my $real_item   = $builder->build_sample_item(
        {
            biblionumber        => $real_biblio->biblionumber,
            barcode             => $rbc,
            itemnotes_nonpublic => undef,             # real owned item, no ILL note
        }
    );
    my $legit_suffix_biblio = $builder->build_sample_biblio();
    my $legit_suffix_item   = $builder->build_sample_item(
        {
            biblionumber        => $legit_suffix_biblio->biblionumber,
            barcode             => "$rbc-1",
            itemnotes_nonpublic => $VIRTUAL_NOTE,
        }
    );
    $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                backend        => $backend,
                biblio_id      => $legit_suffix_biblio->biblionumber,
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    # --- Classify ------------------------------------------------------------
    my $bug = classify_pair( $suffix_item, $backend );
    is( $bug->{delete_biblio}, $base_biblio->biblionumber, 'Bug pair: base biblio flagged as orphan to delete' );
    is( $bug->{keep_biblio},   $suffix_biblio->biblionumber, 'Bug pair: suffix biblio kept' );
    ok( !$bug->{skip}, 'Bug pair: not skipped' );

    my $legit = classify_pair( $legit_suffix_item, $backend );
    ok( $legit->{skip}, 'Legit collision: skipped (base is a real owned item)' );
    ok( !$legit->{delete_biblio}, 'Legit collision: nothing flagged for deletion' );

    # --- Delete the orphan via the same helper the script uses ---------------
    my $orphan = Koha::Biblios->find( $bug->{delete_biblio} );
    my $error  = $plugin->delete_virtual_biblio(
        { biblio => $orphan, context => 'test_cleanup' } );
    is( $error, undef, 'delete_virtual_biblio removed the orphan without error' );

    is( Koha::Biblios->find( $base_biblio->biblionumber ),   undef, 'Orphan base biblio deleted' );
    ok( Koha::Biblios->find( $suffix_biblio->biblionumber ), 'Referenced suffix biblio still present' );

    $schema->storage->txn_rollback;
};
