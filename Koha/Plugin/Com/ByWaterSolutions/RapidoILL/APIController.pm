package Koha::Plugin::Com::ByWaterSolutions::RapidoILL::APIController;

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

use Mojo::Base 'Mojolicious::Controller';

use C4::Letters;

use Koha::DateUtils qw(dt_from_string);
use Koha::ILL::Requests;
use Koha::Items;
use Koha::Patrons;

use Encode;
use Try::Tiny;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

=head1 Koha::Plugin::Com::ByWaterSolutions::RapidoILL::APIController

A class implementing the controller methods for the plugin API

=head2 Class methods

=head3 verifypatron

This method returns patron information, including the I<requestAllowed> boolean
which gets calculated out of several configuration entries and patron status in Koha.

=cut

sub verifypatron {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $body = $c->req->json;

        my $patron_id          = $body->{visiblePatronId};
        my $patron_agency_code = $body->{patronAgencyCode};
        my $patronName         = $body->{patronName};

        # FIXME: Pick the first one until there's a way to determine the pod
        #        the request belongs to.
        my $pod           = $plugin->pods->[0];
        my $configuration = $plugin->configuration->{$pod};

        unless (defined $patron_id
            and defined $patron_agency_code
            and defined $patronName )
        {
            # All fields are mandatory
            my @errors;
            push @errors, 'Missing visiblePatronId'  unless $patron_id;
            push @errors, 'Missing patronAgencyCode' unless $patron_agency_code;
            push @errors, 'Missing patronName'       unless $patronName;

            return $c->render(
                status  => 400,
                openapi => { error => $errors[0] }
            );
        }

        my $patron;
        if ( defined $patron_id ) {
            $patron = Koha::Patrons->find( { cardnumber => $patron_id } );
            $patron = Koha::Patrons->find( { userid     => $patron_id } )
                unless $patron;
        }

        unless ($patron) {
            return $c->render(
                status  => 404,
                openapi => { error => 'Patron not found' }
            );
        }

        my $expiration_date = dt_from_string( $patron->dateexpiry );
        my $agency_code     = $configuration->{$pod}->{library_to_location}->{ $patron->branchcode }
            // $configuration->{default_patron_agency};

        my $local_loans = $patron->checkouts->count;
        my $non_local_loans =
            Koha::ILL::Requests->search( { borrowernumber => $patron->id, backend => $plugin->ill_backend() } )
            ->search_incomplete()
            ->count();

        # Borrowed from SIP/Patron.pm
        my $fines_amount = ( $patron->account->balance > 0 ) ? $patron->account->balance : 0;
        my $debt_blocks_holds =
            ( defined $configuration->{debt_blocks_holds} and $configuration->{debt_blocks_holds} eq 'true' ) ? 1 : 0;
        my $max_debt_blocks_holds = $configuration->{max_debt_blocks_holds};

        my $max_fees = $max_debt_blocks_holds // C4::Context->preference('maxoutstanding') + 0;

        my $surname   = $patron->surname;
        my $firstname = $patron->firstname;

        my $THE_name = "";
        if ( defined $surname and $surname ne '' ) {
            $THE_name = $surname;
            if ( defined $firstname and $firstname ne '' ) {
                $THE_name .= ", $firstname";
            }
        } elsif ( defined $firstname and $firstname ne '' ) {
            $THE_name = $firstname;
        }

        # else { # no surname and no firstname
        #    $THE_name = "";
        #}

        my $patron_info = {
            patronId          => $patron->borrowernumber . "",
            patronExpireDate  => $expiration_date->epoch(),
            patronAgencyCode  => $agency_code,
            centralPatronType => 0, # hardcoded 0 as in the docs
            localLoans        => $local_loans,
            nonLocalLoans     => $non_local_loans,
            patronName        => $THE_name,
        };

        my @errors;

        if (    defined $configuration->{restriction_blocks_holds}
            and $configuration->{restriction_blocks_holds} eq 'true'
            and $patron->is_debarred )
        {
            push @errors, 'The patron is restricted.';
        }

        if (    defined $configuration->{expiration_blocks_holds}
            and $configuration->{expiration_blocks_holds} eq 'true'
            and $patron->is_expired )
        {
            push @errors, 'The patron has expired.';
        }

        if ( $debt_blocks_holds and $fines_amount > $max_fees ) {
            push @errors, 'Patron debt reached the limit.';
        }

        my $status = 'ok';
        my $reason = '';

        if ( scalar @errors > 0 ) {

            # There's something preventing circ, pick the first reason
            $status = 'error';
            $reason = $errors[0];
        }

        return $c->render(
            status  => 200,
            openapi => {
                ( ( $status eq 'ok' ) ? ( patronInfo => $patron_info ) : () ),

                # reason         => $reason,
                requestAllowed => ( $status eq 'ok' ) ? Mojo::JSON->true : Mojo::JSON->false,
            }
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get_print_slip

Given an ILL request id and a letter code, this method returns the HTML required to
generate a print slip for an ILL request.

=cut

sub get_print_slip {
    my $c = shift->openapi->valid_input or return;

    my $illrequest_id = $c->param('ill_request_id');
    my $print_slip_id = $c->param('print_slip_id');

    return try {

        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        $plugin->{cgi} = CGI->new;    # required by C4::Auth::gettemplate and friends
        my $template = $plugin->get_template( { file => 'templates/print_slip.tt' } );

        my $req = Koha::ILL::Requests->find($illrequest_id);

        return $c->render_resource_not_found("ILL request")
            unless $req;

        my $illrequestattributes = {};
        my $attributes           = $req->extended_attributes;
        while ( my $attribute = $attributes->next ) {
            $illrequestattributes->{ $attribute->type } = $attribute->value;
        }

        # Koha::Illrequest->get_notice with hardcoded letter_code
        my $title     = $req->extended_attributes->find( { type => 'title' } );
        my $author    = $req->extended_attributes->find( { type => 'author' } );
        my $metahash  = $req->metadata;
        my @metaarray = ();

        while ( my ( $key, $value ) = each %{$metahash} ) {
            push @metaarray, "- $key: $value" if $value;
        }

        my $metastring = join( "\n", @metaarray );

        my $item_id;
        if ( $req->status =~ /^O_/ ) {

            # 'lending'
            my $item_id_attr = $req->extended_attributes->find( { type => 'itemId' } );
            $item_id = ($item_id_attr) ? $item_id_attr->value : '';
        } elsif ( $req->status =~ /^B_/ ) {

            # 'borrowing' (itemId is the lending system's, use itemBarcode instead)
            my $barcode_attr = $req->extended_attributes->find( { type => 'itemBarcode' } );
            my $barcode      = ($barcode_attr) ? $barcode_attr->value : '';
            if ($barcode) {
                if ( Koha::Items->search( { barcode => $barcode } )->count > 0 ) {
                    my $item = Koha::Items->search( { barcode => $barcode } )->next;
                    $item_id = $item->id;
                }
            }
        } else {
            $plugin->logger->warn("Unable to determine request type for print slip generation");
        }

        my $slip = C4::Letters::GetPreparedLetter(
            module                 => 'ill',
            letter_code            => $print_slip_id,
            branchcode             => $req->branchcode,
            message_transport_type => 'print',
            lang                   => $req->patron->lang,
            tables                 => {

                illrequests => $req->illrequest_id, 
                borrowers => $req->borrowernumber,
                biblio    => $req->biblio_id,
                item      => $item_id,
                branches  => $req->branchcode,
            },
            substitute => {
                illrequestattributes => $illrequestattributes,
                ill_bib_title        => $title  ? $title->value  : '',
                ill_bib_author       => $author ? $author->value : '',
                ill_full_metadata    => $metastring
            }
        );

        # / Koha::Illrequest->get_notice

        $template->param(
            slip  => $slip->{content},
            title => $slip->{title},
        );

        return $c->render(
            status => 200,
            data   => Encode::encode( 'UTF-8', $template->output() )
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

1;
