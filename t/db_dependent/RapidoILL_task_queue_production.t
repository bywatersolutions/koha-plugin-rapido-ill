#!/usr/bin/env perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Test::More tests => 2;
use Test::NoWarnings;
use Test::Exception;

use t::lib::TestBuilder;

use C4::Context;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'Production userenv handling with C4::Context directly' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Create test library
    my $library = $builder->build_object( { class => 'Koha::Libraries' } );

    # Test 1: No userenv initially
    is( C4::Context->userenv, undef, 'No userenv set initially' );

    # Test 2: Set userenv using C4::Context directly (production method)
    C4::Context->set_userenv(
        0,                       # borrowernumber (daemon user)
        'rapidoill_daemon',      # userid
        '',                      # cardnumber
        'RapidoILL',             # firstname
        'Daemon',                # surname
        $library->branchcode,    # branch (this is the key part)
        $library->branchname,    # branchname
        0,                       # flags
        '',                      # emailaddress
        '',                      # shibboleth
        '',                      # desk_id
        '',                      # desk_name
        '',                      # register_id
        ''                       # register_name
    );

    # Test 3: Verify userenv is set correctly
    my $userenv = C4::Context->userenv;
    ok( $userenv, 'Userenv is set' );
    is( $userenv->{branch}, $library->branchcode, 'Userenv branch set correctly' );
    is( $userenv->{id},     'rapidoill_daemon',   'Userenv userid set correctly' );

    # Test 4: Test cleanup with unset_userenv
    C4::Context->unset_userenv();
    is( C4::Context->userenv, undef, 'Userenv properly cleared with unset_userenv' );

    # Test 5: Test setting userenv again after cleanup
    C4::Context->set_userenv(
        1,                    'test_user',          'test_card', 'Test', 'User',
        $library->branchcode, $library->branchname, 0,
        '',                   '',                   '', '', '', ''
    );

    is( C4::Context->userenv->{branch}, $library->branchcode, 'Userenv can be set again after cleanup' );

    # Final cleanup
    C4::Context->unset_userenv();

    $schema->storage->txn_rollback;
};
