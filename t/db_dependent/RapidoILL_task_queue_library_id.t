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
use Data::Dumper;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use C4::Context;
use Koha::Database;
use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Task queue userenv payload handling' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;

    # Create test libraries
    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    # Mock plugin instance
    my $plugin = t::lib::Mocks::Rapido->new(
        {
            library  => $library1,
            category => $category,
            itemtype => $itemtype,
        }
    );

    # Test 1: No userenv initially
    is( C4::Context->userenv, undef, 'No userenv set initially' );

    # Test 2: Set userenv and create task with userenv payload
    t::lib::Mocks::mock_userenv(
        {
            branchcode => $library1->branchcode,
            branchname => 'Test Library 1',
            number     => 123,
            id         => 'test_user'
        }
    );

    my $userenv = C4::Context->userenv;
    my $tasks   = $plugin->get_queued_tasks;
    my $task    = $tasks->enqueue(
        {
            object_type => 'ill',
            object_id   => 123,
            action      => 'o_item_shipped',
            pod         => 'test_pod',
            payload     => {
                userenv => $userenv,
            }
        }
    );

    # Test 3: Verify userenv is stored in payload
    my $payload = $task->decoded_payload;
    ok( $payload->{userenv}, 'Task payload contains userenv' );
    is( $payload->{userenv}->{branch}, $library1->branchcode, 'Userenv branch stored correctly' );

    # Test 4: Verify userenv is set correctly
    my $current_userenv = C4::Context->userenv;
    is( $current_userenv->{branch}, $library1->branchcode, 'Userenv branch set correctly' );

    # Test 5: Test changing to different library
    t::lib::Mocks::mock_userenv(
        {
            branchcode => $library2->branchcode,
            branchname => 'Test Library 2'
        }
    );

    is( C4::Context->userenv->{branch}, $library2->branchcode, 'Userenv branch changed correctly' );

    # Test 6: Test proper userenv cleanup using unset_userenv
    C4::Context->unset_userenv();
    is( C4::Context->userenv, undef, 'Userenv properly cleared with unset_userenv' );

    # Final cleanup
    C4::Context->unset_userenv();
    is( C4::Context->userenv, undef, 'Final userenv cleanup successful' );

    $schema->storage->txn_rollback;
};
