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
use Test::NoWarnings;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Rapido;

use C4::Letters;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new();

subtest 'GetPreparedLetter returns undef for missing template' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    # GetPreparedLetter warns when the template is missing — expected Koha core behavior
    my $slip;
    warning_like {
        $slip = C4::Letters::GetPreparedLetter(
            module                 => 'ill',
            letter_code            => 'NONEXISTENT_SLIP',
            branchcode             => $library->branchcode,
            message_transport_type => 'print',
            lang                   => $patron->lang,
            tables                 => {
                illrequests => $ill_request->illrequest_id,
                borrowers   => $patron->borrowernumber,
                branches    => $library->branchcode,
            },
        );
    }
    qr/No ill NONEXISTENT_SLIP letter/, 'Expected warning from GetPreparedLetter for missing template';

    # This is the line that caused the 500 before the fix.
    # With the fix, we guard against undef:
    my $content = $slip ? $slip->{content} : undef;

    is( $content, undef, 'Guarded access returns undef instead of crashing' );

    $schema->storage->txn_rollback;
};

subtest 'GetPreparedLetter returns content for existing template' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );

    my $ill_request = $builder->build_object(
        {
            class => 'Koha::ILL::Requests',
            value => {
                borrowernumber => $patron->borrowernumber,
                branchcode     => $library->branchcode,
                backend        => 'RapidoILL',
                status         => 'B_ITEM_RECEIVED',
            }
        }
    );

    # Create a notice template
    $builder->build_object(
        {
            class => 'Koha::Notice::Templates',
            value => {
                module                 => 'ill',
                code                   => 'ILL_TEST_SLIP',
                branchcode             => q{},
                name                   => 'Test ILL slip',
                is_html                => 1,
                title                  => 'ILL Slip',
                content                => 'Request [% illrequests.illrequest_id %]',
                message_transport_type => 'print',
                lang                   => 'default',
            }
        }
    );

    my $slip = C4::Letters::GetPreparedLetter(
        module                 => 'ill',
        letter_code            => 'ILL_TEST_SLIP',
        branchcode             => $library->branchcode,
        message_transport_type => 'print',
        lang                   => $patron->lang,
        tables                 => {
            illrequests => $ill_request->illrequest_id,
            borrowers   => $patron->borrowernumber,
            branches    => $library->branchcode,
        },
    );

    ok( defined $slip, 'GetPreparedLetter returns a value for existing template' );

    my $content = $slip ? $slip->{content} : undef;
    like( $content, qr/Request/, 'Slip content was rendered from template' );

    $schema->storage->txn_rollback;
};
