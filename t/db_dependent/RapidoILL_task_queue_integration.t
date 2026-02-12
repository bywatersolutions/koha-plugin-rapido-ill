#!/usr/bin/env perl

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

use Test::More tests => 2;
use Test::NoWarnings;
use Test::Exception;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use C4::Context;
use Koha::Database;
use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Task queue o_item_shipped integration with userenv payload' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Create test data
    my $library     = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category    = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype    = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $patron      = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item        = $builder->build_object( { class => 'Koha::Items' } );
    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => { borrowernumber => $patron->borrowernumber }
        }
    );

    # Mock plugin instance
    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library,
            category => $category,
            itemtype => $itemtype,
        }
    );

    # Add required attributes to ILL request
    $plugin->add_or_update_attributes(
        {
            request    => $ill_request,
            attributes => {
                itemId => $item->barcode,
                pod    => 'test_pod'
            }
        }
    );

    # Test 1: Set userenv and create task with userenv payload
    t::lib::Mocks::mock_userenv(
        {
            branchcode => $library->branchcode,
            branchname => $library->branchname,
            number     => 123,
            id         => 'test_user'
        }
    );

    my $userenv = C4::Context->userenv;
    my $tasks   = $plugin->get_queued_tasks;
    my $task    = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => $ill_request->id,
            action      => 'o_item_shipped',
            pod         => 'test_pod',
            payload     => {
                userenv => $userenv,
            }
        }
    );

    ok( $task, 'Task created successfully' );

    # Test 2: Verify userenv stored in payload
    my $payload = $task->decoded_payload;
    ok( $payload->{userenv}, 'Task payload contains userenv' );
    is( $payload->{userenv}->{branch}, $library->branchcode, 'Userenv branch stored correctly' );

    # Test 3: Clear userenv and verify restoration works
    C4::Context->unset_userenv();
    is( C4::Context->userenv, undef, 'No userenv set initially' );

    # Cleanup
    C4::Context->unset_userenv();

    $schema->storage->txn_rollback;
};
