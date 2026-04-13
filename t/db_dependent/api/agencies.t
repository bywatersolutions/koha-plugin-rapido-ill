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

use Test::More tests => 6;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use Koha::Database;

my $schema   = Koha::Database->new->schema;
my $builder  = t::lib::TestBuilder->new();
my $password = t::lib::Mocks::Rapido::PASSWORD;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'GET /agencies (list)' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;

    $t->get_ok("$base/agencies")->status_is(401);

    $t->get_ok( "//" . $unauth_patron->userid . ":$password\@$base/agencies" )->status_is(403);

    $t->get_ok( "//" . $librarian->userid . ":$password\@$base/agencies" )->status_is(200)
        ->json_is( [] );

    $schema->storage->txn_rollback;
};

subtest 'POST /agencies (create)' => sub {

    plan tests => 10;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;
    my $auth_base = "//" . $librarian->userid . ":$password\@$base";

    my $agency = {
        pod                       => 'test-pod',
        agency_id                 => 'AGENCY001',
        patron_id                 => $librarian->borrowernumber,
        description               => 'Test Agency',
        requires_passcode         => 0,
        visiting_checkout_allowed => 1,
    };

    $t->post_ok( "$base/agencies" => json => $agency )->status_is(401);

    $t->post_ok( "//" . $unauth_patron->userid . ":$password\@$base/agencies" => json => $agency )
        ->status_is(403);

    $t->post_ok( "$auth_base/agencies" => json => $agency )->status_is(201)
        ->json_is( '/agency_id' => 'AGENCY001' )
        ->json_is( '/description' => 'Test Agency' );

    # Duplicate
    $t->post_ok( "$auth_base/agencies" => json => $agency )->status_is(409);

    $schema->storage->txn_rollback;
};

subtest 'POST /agencies/batch (bulk create)' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;
    my $auth_base = "//" . $librarian->userid . ":$password\@$base";

    my $batch = [
        {
            pod         => 'test-pod',
            agency_id   => 'BATCH001',
            patron_id   => $librarian->borrowernumber,
            description => 'Batch Agency 1',
        },
        {
            pod         => 'test-pod',
            agency_id   => 'BATCH002',
            patron_id   => $librarian->borrowernumber,
            description => 'Batch Agency 2',
        },
    ];

    $t->post_ok( "$base/agencies/batch" => json => $batch )->status_is(401);

    $t->post_ok( "//" . $unauth_patron->userid . ":$password\@$base/agencies/batch" => json => $batch )
        ->status_is(403);

    $t->post_ok( "$auth_base/agencies/batch" => json => $batch )->status_is(201)
        ->json_is( '/0/agency_id' => 'BATCH001' )
        ->json_is( '/1/agency_id' => 'BATCH002' );

    $schema->storage->txn_rollback;
};

subtest 'GET /agencies/{pod}/{agency_id}' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;
    my $auth_base = "//" . $librarian->userid . ":$password\@$base";

    require RapidoILL::AgencyPatron;
    RapidoILL::AgencyPatron->new(
        {
            pod         => 'test-pod',
            agency_id   => 'AG001',
            patron_id   => $librarian->borrowernumber,
            description => 'Get Test',
        }
    )->store;

    $t->get_ok("$base/agencies/test-pod/AG001")->status_is(401);

    $t->get_ok("$auth_base/agencies/test-pod/AG001")->status_is(200)
        ->json_is( '/agency_id' => 'AG001' );

    $t->get_ok("$auth_base/agencies/test-pod/NONEXISTENT")->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'PUT /agencies/{pod}/{agency_id}' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;
    my $auth_base = "//" . $librarian->userid . ":$password\@$base";

    require RapidoILL::AgencyPatron;
    RapidoILL::AgencyPatron->new(
        {
            pod         => 'test-pod',
            agency_id   => 'AG002',
            patron_id   => $librarian->borrowernumber,
            description => 'Before Update',
        }
    )->store;

    $t->put_ok( "$auth_base/agencies/test-pod/AG002" => json => { description => 'After Update' } )
        ->status_is(200)
        ->json_is( '/description' => 'After Update' );

    $t->put_ok( "$auth_base/agencies/test-pod/NONEXISTENT" => json => { description => 'Nope' } )
        ->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'DELETE /agencies/{pod}/{agency_id}' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my ( $plugin, $librarian, $unauth_patron ) = t::lib::Mocks::Rapido->new();
    my $base = "/api/v1/contrib/" . $plugin->api_namespace;
    my $auth_base = "//" . $librarian->userid . ":$password\@$base";

    require RapidoILL::AgencyPatron;
    RapidoILL::AgencyPatron->new(
        {
            pod         => 'test-pod',
            agency_id   => 'AG003',
            patron_id   => $librarian->borrowernumber,
            description => 'To Delete',
        }
    )->store;

    $t->delete_ok("$auth_base/agencies/test-pod/AG003")->status_is(204);

    $t->get_ok("$auth_base/agencies/test-pod/AG003")->status_is(404);

    $t->delete_ok("$auth_base/agencies/test-pod/NONEXISTENT");

    $schema->storage->txn_rollback;
};
