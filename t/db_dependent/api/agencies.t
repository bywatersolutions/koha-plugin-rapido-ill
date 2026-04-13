#!/usr/bin/env perl

use Modern::Perl;

use Test::More tests => 6;
use Test::Mojo;
use t::lib::TestBuilder;
use t::lib::Mocks;

use JSON qw(encode_json);

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new();

my $plugin    = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
my $namespace = $plugin->api_namespace;
my $base      = "/api/v1/contrib/$namespace";

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

my $librarian = $builder->build_object(
    { class => 'Koha::Patrons', value => { flags => 2**22 } }
);
my $password = 'thePassword123';
$librarian->set_password( { password => $password, skip_validation => 1 } );
my $userid = $librarian->userid;

my $patron = $builder->build_object(
    { class => 'Koha::Patrons', value => { flags => 0 } }
);
$patron->set_password( { password => 'noAccess123', skip_validation => 1 } );
my $unauth_userid = $patron->userid;

subtest 'GET /agencies (list)' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    $t->get_ok("$base/agencies")->status_is(401);

    $t->get_ok("//$unauth_userid:noAccess123\@$base/agencies")->status_is(403);

    $t->get_ok("//$userid:$password\@$base/agencies")->status_is(200)
        ->json_is( [] );

    $schema->storage->txn_rollback;
};

subtest 'POST /agencies (create)' => sub {

    plan tests => 10;

    $schema->storage->txn_begin;

    my $agency = {
        pod                       => 'test-pod',
        agency_id                 => 'AGENCY001',
        patron_id                 => $librarian->borrowernumber,
        description               => 'Test Agency',
        requires_passcode         => 0,
        visiting_checkout_allowed => 1,
    };

    $t->post_ok( "$base/agencies" => json => $agency )->status_is(401);

    $t->post_ok( "//$unauth_userid:noAccess123\@$base/agencies" => json => $agency )->status_is(403);

    $t->post_ok( "//$userid:$password\@$base/agencies" => json => $agency )->status_is(201)
        ->json_is( '/agency_id' => 'AGENCY001' )
        ->json_is( '/description' => 'Test Agency' );

    # Duplicate
    $t->post_ok( "//$userid:$password\@$base/agencies" => json => $agency )->status_is(409);

    $schema->storage->txn_rollback;
};

subtest 'POST /agencies/batch (bulk create)' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

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

    $t->post_ok( "//$unauth_userid:noAccess123\@$base/agencies/batch" => json => $batch )->status_is(403);

    $t->post_ok( "//$userid:$password\@$base/agencies/batch" => json => $batch )->status_is(201)
        ->json_is( '/0/agency_id' => 'BATCH001' )
        ->json_is( '/1/agency_id' => 'BATCH002' );

    $schema->storage->txn_rollback;
};

subtest 'GET /agencies/{pod}/{agency_id}' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

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

    $t->get_ok("//$userid:$password\@$base/agencies/test-pod/AG001")->status_is(200)
        ->json_is( '/agency_id' => 'AG001' );

    $t->get_ok("//$userid:$password\@$base/agencies/test-pod/NONEXISTENT")->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'PUT /agencies/{pod}/{agency_id}' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    require RapidoILL::AgencyPatron;
    RapidoILL::AgencyPatron->new(
        {
            pod         => 'test-pod',
            agency_id   => 'AG002',
            patron_id   => $librarian->borrowernumber,
            description => 'Before Update',
        }
    )->store;

    $t->put_ok(
        "//$userid:$password\@$base/agencies/test-pod/AG002" => json =>
            { description => 'After Update' }
    )->status_is(200)
        ->json_is( '/description' => 'After Update' );

    $t->put_ok(
        "//$userid:$password\@$base/agencies/test-pod/NONEXISTENT" => json =>
            { description => 'Nope' }
    )->status_is(404);

    # Verify persistence
    $t->get_ok("//$userid:$password\@$base/agencies/test-pod/AG002")
        ;

    $schema->storage->txn_rollback;
};

subtest 'DELETE /agencies/{pod}/{agency_id}' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    require RapidoILL::AgencyPatron;
    RapidoILL::AgencyPatron->new(
        {
            pod         => 'test-pod',
            agency_id   => 'AG003',
            patron_id   => $librarian->borrowernumber,
            description => 'To Delete',
        }
    )->store;

    $t->delete_ok("//$userid:$password\@$base/agencies/test-pod/AG003")->status_is(204);

    # Verify gone
    $t->get_ok("//$userid:$password\@$base/agencies/test-pod/AG003")->status_is(404);

    # Delete nonexistent
    $t->delete_ok("//$userid:$password\@$base/agencies/test-pod/NONEXISTENT")
        ;

    $schema->storage->txn_rollback;
};
