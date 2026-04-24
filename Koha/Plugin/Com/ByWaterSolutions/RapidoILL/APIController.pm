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
            centralPatronType => 0,                              # hardcoded 0 as in the docs
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
                borrowers   => $req->borrowernumber,
                biblio      => $req->biblio_id,
                item        => $item_id,
                branches    => $req->branchcode,
            },
            substitute => {
                illrequestattributes => $illrequestattributes,
                ill_bib_title        => $title  ? $title->value  : '',
                ill_bib_author       => $author ? $author->value : '',
                ill_full_metadata    => $metastring
            }
        );

        # / Koha::Illrequest->get_notice

        unless ($slip) {
            $plugin->logger->warn(
                sprintf(
                    "No print slip template found for letter_code='%s', branchcode='%s', illrequest_id=%s",
                    $print_slip_id, $req->branchcode, $illrequest_id
                )
            );
        }

        $template->param(
            slip  => $slip ? $slip->{content} : undef,
            title => $slip ? $slip->{title}   : undef,
        );

        return $c->render(
            status => 200,
            data   => Encode::encode( 'UTF-8', $template->output() )
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 status_api

Returns the current Rapido integration status based on recent 5xx incidents
in the server_status_log table.

=cut

sub status_api {
    my $c = shift->openapi->valid_input or return;

    return try {
        require RapidoILL::ServerStatusLogs;

        my $incident = RapidoILL::ServerStatusLogs->new->search(
            { delayed_until => { '>'   => \'NOW()' } },
            { order_by      => { -desc => 'delayed_until' }, rows => 1 }
        )->next;

        if ($incident) {
            return $c->render(
                status => 200,
                json   => {
                    status        => 'outage',
                    status_code   => $incident->status_code,
                    since         => $incident->timestamp . "",
                    delayed_until => $incident->delayed_until . "",
                },
            );
        }

        return $c->render(
            status => 200,
            json   => { status => 'ok' },
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_tasks

Lists task queue entries with server-side pagination, filtering, and sorting
via Koha's REST framework.

=cut

sub list_tasks {
    my $c = shift->openapi->valid_input or return;

    return try {
        require RapidoILL::QueuedTasks;

        return $c->render(
            status  => 200,
            openapi => $c->objects->search( RapidoILL::QueuedTasks->new ),
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_incidents

Lists server status log entries with server-side pagination, filtering, and sorting
via Koha's REST framework.

=cut

sub list_incidents {
    my $c = shift->openapi->valid_input or return;

    return try {
        require RapidoILL::ServerStatusLogs;

        return $c->render(
            status  => 200,
            openapi => $c->objects->search( RapidoILL::ServerStatusLogs->new ),
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_task_filters

Returns distinct action and status values currently in the task queue.

=cut

sub list_task_filters {
    my $c = shift->openapi->valid_input or return;

    return try {
        require RapidoILL::QueuedTasks;

        my @actions =
            map { $_->action }
            RapidoILL::QueuedTasks->new->search( {}, { columns => ['action'], distinct => 1 } )->as_list;

        my @statuses =
            map { $_->status }
            RapidoILL::QueuedTasks->new->search( {}, { columns => ['status'], distinct => 1 } )->as_list;

        return $c->render(
            status => 200,
            json   => { actions => \@actions, statuses => \@statuses },
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_pods

Returns the list of configured pod identifiers.

=cut

sub list_pods {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
        return $c->render(
            status => 200,
            json   => $plugin->pods,
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_agencies

Lists agency-to-patron mappings.

=cut

sub list_agencies {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        return $c->render(
            status  => 200,
            openapi => $c->objects->search( $plugin->get_agency_patrons ),
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 get_agency

Gets a single agency-to-patron mapping.

=cut

sub get_agency {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $agency = $plugin->get_agency_patrons->search(
            {
                pod       => $c->param('pod'),
                agency_id => $c->param('agency_id'),
            }
        )->next;

        return $c->render_resource_not_found("Agency")
            unless $agency;

        return $c->render(
            status  => 200,
            openapi => $agency->to_api,
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 add_agency

Creates a single agency-to-patron mapping.

=cut

sub add_agency {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $body = $c->req->json;

        # Check for duplicate
        my $existing =
            $plugin->get_agency_patrons->search( { pod => $body->{pod}, agency_id => $body->{agency_id} } )->next;

        return $c->render(
            status  => 409,
            openapi => { error => "Agency already exists" },
        ) if $existing;

        my $agency;
        if ( $body->{patron_id} ) {
            $agency = $plugin->get_agency_patrons->object_class->new_from_api($body)->store;
        } else {
            my $config = $plugin->pod_config( $body->{pod} );
            $agency = $plugin->get_agency_patrons->create_with_patron(
                {
                    %$body,
                    library_id    => $config->{partners_library_id},
                    category_code => $config->{partners_category},
                }
            );
        }

        return $c->render(
            status  => 201,
            openapi => $agency->to_api,
        );
    } catch {
        if ( ref($_) =~ /Koha::Exceptions::Object::DuplicateID/ ) {
            return $c->render(
                status  => 409,
                openapi => { error => "Agency already exists" },
            );
        }
        if ( ref($_) =~ /Koha::Exceptions::Patron/ ) {
            return $c->render(
                status  => 500,
                openapi => { error => "Failed to create patron: $_" },
            );
        }
        return $c->unhandled_exception($_);
    };
}

=head3 add_agencies_batch

Creates multiple agency-to-patron mappings in a single request.

=cut

sub add_agencies_batch {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $body = $c->req->json;
        my @results;

        Koha::Database->new->schema->txn_do(
            sub {
                for my $entry (@$body) {
                    my $existing = $plugin->get_agency_patrons->search(
                        { pod => $entry->{pod}, agency_id => $entry->{agency_id} } )->next;

                    if ($existing) {
                        $existing->set_from_api($entry)->store;
                        push @results, { %{ $existing->to_api }, _status => 'updated' };
                    } elsif ( $entry->{patron_id} ) {
                        my $agency = $plugin->get_agency_patrons->object_class->new_from_api($entry)->store;
                        push @results, { %{ $agency->to_api }, _status => 'created' };
                    } else {
                        my $config = $plugin->pod_config( $entry->{pod} );
                        my $agency = $plugin->get_agency_patrons->create_with_patron(
                            {
                                %$entry,
                                library_id    => $config->{partners_library_id},
                                category_code => $config->{partners_category},
                            }
                        );
                        push @results, { %{ $agency->to_api }, _status => 'created' };
                    }
                }
            }
        );

        return $c->render(
            status  => 201,
            openapi => \@results,
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 update_agency

Updates an agency-to-patron mapping.

=cut

sub update_agency {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $agency = $plugin->get_agency_patrons->search(
            {
                pod       => $c->param('pod'),
                agency_id => $c->param('agency_id'),
            }
        )->next;

        return $c->render_resource_not_found("Agency")
            unless $agency;

        $agency->set_from_api( $c->req->json )->store;

        return $c->render(
            status  => 200,
            openapi => $agency->to_api,
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 delete_agency

Deletes an agency-to-patron mapping.

=cut

sub delete_agency {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

        my $agency = $plugin->get_agency_patrons->search(
            {
                pod       => $c->param('pod'),
                agency_id => $c->param('agency_id'),
            }
        )->next;

        return $c->render_resource_not_found("Agency")
            unless $agency;

        $agency->delete;

        return $c->render(
            status  => 204,
            openapi => q{},
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

1;
