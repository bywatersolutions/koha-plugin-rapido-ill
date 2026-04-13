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
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new();

my $plugin    = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
my $namespace = $plugin->api_namespace;
my $base      = "/api/v1/contrib/$namespace";

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

my $librarian = $builder->build_object(
    { class => 'Koha::Patrons', value => { flags => 2**22 } }    # ill permission
);
my $password = 'thePassword123';
$librarian->set_password( { password => $password, skip_validation => 1 } );
my $userid = $librarian->userid;

my $patron = $builder->build_object(
    { class => 'Koha::Patrons', value => { flags => 0 } }
);
$patron->set_password( { password => 'noAccess123', skip_validation => 1 } );
my $unauth_userid = $patron->userid;

subtest 'GET /status/tasks' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    $t->get_ok("$base/status/tasks")->status_is(401);

    $t->get_ok("//$unauth_userid:noAccess123\@$base/status/tasks")->status_is(403);

    $t->get_ok("//$userid:$password\@$base/status/tasks")->status_is(200)
        ->json_is( [] );

    $schema->storage->txn_rollback;
};

subtest 'GET /status/incidents' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    $t->get_ok("$base/status/incidents")->status_is(401);

    $t->get_ok("//$unauth_userid:noAccess123\@$base/status/incidents")->status_is(403);

    $t->get_ok("//$userid:$password\@$base/status/incidents")->status_is(200)
        ->json_is( [] );

    $schema->storage->txn_rollback;
};

subtest 'GET /status/tasks/filters' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    $t->get_ok("$base/status/tasks/filters")->status_is(401);

    $t->get_ok("//$unauth_userid:noAccess123\@$base/status/tasks/filters")->status_is(403);

    $t->get_ok("//$userid:$password\@$base/status/tasks/filters")->status_is(200)
        ->json_has('/actions')
        ;

    $schema->storage->txn_rollback;
};
