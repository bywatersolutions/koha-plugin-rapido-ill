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
use Test::NoWarnings;

use t::lib::TestBuilder;
use t::lib::Mocks;

use C4::Context;
use Koha::Database;

BEGIN {

    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'after_circ_action() checkin tests' => sub {

    plan tests => 2;

    subtest 'anonymized checkout is still matched to the request' => sub {

        plan tests => 2;

        $schema->storage->txn_begin;

        my ( $plugin, $request, $checkout, $anonymous_patron ) = build_scenario();

        # Koha anonymizes the checkout before firing the hook when the patron's
        # privacy is set to 'never'
        $checkout->borrowernumber( $anonymous_patron->borrowernumber )->store;

        $plugin->after_circ_action(
            {
                action  => 'checkin',
                payload => { checkout => $checkout }
            }
        );

        my $tasks = $plugin->get_queued_tasks->search( { illrequest_id => $request->id } );

        is( $tasks->count,        1,                   'A task was enqueued despite the checkout being anonymized' );
        is( $tasks->next->action, 'b_item_in_transit', 'The expected action was enqueued' );

        $schema->storage->txn_rollback;
    };

    subtest 'checkout belonging to an unrelated patron is skipped' => sub {

        plan tests => 1;

        $schema->storage->txn_begin;

        my ( $plugin, $request, $checkout ) = build_scenario();

        my $other_patron = $builder->build_object( { class => 'Koha::Patrons' } );
        $checkout->borrowernumber( $other_patron->borrowernumber )->store;

        $plugin->after_circ_action(
            {
                action  => 'checkin',
                payload => { checkout => $checkout }
            }
        );

        is(
            $plugin->get_queued_tasks->search( { illrequest_id => $request->id } )->count,
            0, 'No task enqueued for a checkout belonging to another patron'
        );

        $schema->storage->txn_rollback;
    };
};

=head2 Helper methods

=head3 build_scenario

    my ( $plugin, $request, $checkout, $anonymous_patron ) = build_scenario();

Builds a borrowing-site request in B_ITEM_RECEIVED, linked to an old checkout
through the I<checkout_id> attribute, with the plugin configured to
automatically notify the item is in transit on checkin.

=cut

sub build_scenario {

    my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron   = $builder->build_object( { class => 'Koha::Patrons', value => { privacy => 2 } } );

    my $anonymous_patron = $builder->build_object( { class => 'Koha::Patrons' } );

    t::lib::Mocks::mock_preference( 'ILLModule',       1 );
    t::lib::Mocks::mock_preference( 'AnonymousPatron', $anonymous_patron->borrowernumber );
    t::lib::Mocks::mock_userenv( { branchcode => $library->branchcode } );

    my $config_yaml = sprintf( <<'EOF', $library->branchcode, $category->categorycode, $itemtype->itemtype );
---
test-pod:
  base_url: https://test-pod.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 12345
  partners_library_id: %s
  partners_category: %s
  default_item_type: %s
  default_patron_agency: TEST_AGENCY
  borrowing:
    automatic_item_in_transit: true
  dev_mode: true
EOF

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    $plugin->store_data( { configuration => $config_yaml } );

    my $request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                branchcode     => $library->branchcode,
                borrowernumber => $patron->borrowernumber,
                backend        => $plugin->ill_backend,
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    my $checkout = $builder->build_object(
        {
            class => 'Koha::Old::Checkouts',
            value => { borrowernumber => $patron->borrowernumber }
        }
    );

    $plugin->add_or_update_attributes(
        {
            request    => $request,
            attributes => {
                pod         => 'test-pod',
                checkout_id => $checkout->id,
            }
        }
    );

    return ( $plugin, $request, $checkout, $anonymous_patron );
}
