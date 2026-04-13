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

use Test::More tests => 4;
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
    { class => 'Koha::Patrons', value => { flags => 2**4 } }    # borrowers permission
);
my $password = 'thePassword123';
$librarian->set_password( { password => $password, skip_validation => 1 } );
my $userid = $librarian->userid;

my $patron = $builder->build_object(
    { class => 'Koha::Patrons', value => { flags => 0 } }
);
$patron->set_password( { password => 'noAccess123', skip_validation => 1 } );
my $unauth_userid = $patron->userid;

subtest 'auth' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $body = {
        visiblePatronId  => $patron->cardnumber,
        patronAgencyCode => 'TEST',
        patronName       => 'Test Patron',
    };

    $t->post_ok( "$base/circulation/verifypatron" => json => $body )->status_is(401);

    $t->post_ok( "//$unauth_userid:noAccess123\@$base/circulation/verifypatron" => json => $body )
        ->status_is(403);

    $schema->storage->txn_rollback;
};

subtest 'missing parameters' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    $t->post_ok(
        "//$userid:$password\@$base/circulation/verifypatron" => json =>
            { patronAgencyCode => 'TEST', patronName => 'Test' }
    )->status_is(400)
        ->json_like( '/error' => qr/visiblePatronId/ );

    $t->post_ok(
        "//$userid:$password\@$base/circulation/verifypatron" => json => {}
    )->status_is(400);

    $schema->storage->txn_rollback;
};

subtest 'patron not found' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    $t->post_ok(
        "//$userid:$password\@$base/circulation/verifypatron" => json => {
            visiblePatronId  => 'NONEXISTENT_CARDNUMBER_XYZ',
            patronAgencyCode => 'TEST',
            patronName       => 'Nobody',
        }
    )->status_is(404)
        ->json_is( '/error' => 'Patron not found' );

    $schema->storage->txn_rollback;
};

subtest 'successful verification' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    my $test_patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => {
                dateexpiry => '2099-12-31',
                debarred   => undef,
            }
        }
    );

    $t->post_ok(
        "//$userid:$password\@$base/circulation/verifypatron" => json => {
            visiblePatronId  => $test_patron->cardnumber,
            patronAgencyCode => 'TEST',
            patronName       => $test_patron->surname,
        }
    )->status_is(200)
        ->json_is( '/requestAllowed' => Mojo::JSON->true )
        ->json_is( '/patronInfo/patronId' => $test_patron->borrowernumber . "" )
        ->json_has('/patronInfo/patronExpireDate');

    $schema->storage->txn_rollback;
};
