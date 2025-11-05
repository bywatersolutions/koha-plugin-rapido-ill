package RapidoILL::Backend::BorrowerActions;

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
# along with The Rapido ILL plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Try::Tiny qw(catch try);
use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
use C4::Biblio      qw( DelBiblio );

use RapidoILL::Exceptions;

=head1 NAME

RapidoILL::Backend::BorrowerActions - Backend utilities for borrower-side ILL request operations

=head1 SYNOPSIS

    use RapidoILL::Backend::BorrowerActions;

    my $actions = RapidoILL::Backend::BorrowerActions->new(
        {
            pod    => $pod,
            plugin => $plugin,
        }
    );

    # ILL request utility methods
    $actions->borrower_receive_unshipped( $req, $params );
    $actions->item_in_transit( $req, $params );
    $actions->borrower_cancel( $req, $params );

=head1 DESCRIPTION

Backend utility class for borrower-side ILL request operations. This class provides
methods for performing backend operations on ILL requests from the borrower perspective.

Note: CircAction processing is handled by RapidoILL::ActionHandler::Borrower.

=head2 Class methods

=head3 new

    my $actions = RapidoILL::Backend::BorrowerActions->new(
        {
            pod    => $pod,
            plugin => $plugin,
        }
    );

Constructor for the borrower actions utility class.

=cut

sub new {
    my ( $class, $params ) = @_;

    my @mandatory_params = qw(pod plugin);
    foreach my $param (@mandatory_params) {
        RapidoILL::Exception::MissingParameter->throw( param => $param )
            unless $params->{$param};
    }

    my $self = {
        pod    => $params->{pod},
        plugin => $params->{plugin},
    };

    bless $self, $class;

    return $self;
}

=head2 Instance methods

=head3 borrower_receive_unshipped

    $actions->borrower_receive_unshipped( $ill_request, $params );

Handle receiving an unshipped item from the borrower side.

Parameters:
- $ill_request: The ILL request object
- $params: Hashref with:
  - circId: Circulation ID
  - attributes: Item attributes for virtual record creation
  - barcode: Item barcode
  - client_options: Optional options to pass to the Rapido client

=cut

sub borrower_receive_unshipped {
    my ( $self, $request, $params ) = @_;

    my $circId     = $params->{circId};
    my $attributes = $params->{attributes};
    my $barcode    = $params->{barcode};
    my $options    = $params->{client_options} // {};

    return try {
        Koha::Database->new->schema->txn_do(
            sub {
                # check if already catalogued. INN-Reach requires no barcode collision
                my $existing_item = Koha::Items->find( { barcode => $barcode } );

                if ($existing_item) {

                    # already exists, add suffix
                    my $i = 1;
                    my $done;

                    while ( !$done ) {
                        my $tmp_barcode = $barcode . "-$i";
                        $existing_item = Koha::Items->find( { barcode => $tmp_barcode } );

                        if ( !$existing_item ) {
                            $barcode = $tmp_barcode;
                            $done    = 1;
                        }

                        $i++;
                    }

                    $attributes->{barcode_collision} = 1;
                }

                my $config = $self->{plugin}->configuration->{ $self->{pod} };

                # Create the MARC record and item
                my $item = $self->{plugin}->add_virtual_record_and_item(
                    {
                        req         => $request,
                        config      => $config,
                        call_number => $attributes->{callNumber},
                        barcode     => $attributes->{barcode},
                    }
                );

                $request->set(
                    {
                        biblio_id => $item->biblionumber,
                    }
                );
                $request->status('B_ITEM_RECEIVED')->store();

                if ( $options && $options->{notify_rapido} ) {
                    $self->{plugin}->get_client( $self->{pod} )->borrower_receive_unshipped( {}, $options );
                }
            }
        );
        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    }
}

=head3 item_in_transit

    $actions->item_in_transit( $ill_request, $params );

Mark an ILL request as item in transit from the borrower side.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - client_options: Options to pass to the Rapido client

=cut

sub item_in_transit {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    my $attrs = $req->extended_attributes;

    my $circId = $self->{plugin}->get_req_circ_id($req);

    return try {
        Koha::Database->new->schema->txn_do(
            sub {
                # Return the item first
                my $barcode = $attrs->find( { type => 'itemBarcode' } )->value;

                my $item = Koha::Items->find( { barcode => $barcode } );

                if ($item) {    # is the item still on the database
                    my $checkout = Koha::Checkouts->find( { itemnumber => $item->id } );

                    if ($checkout) {
                        $self->{plugin}->add_return( { barcode => $barcode } );
                    }
                }

                my $biblio = Koha::Biblios->find( $req->biblio_id );

                if ($biblio) {    # is the biblio still on the database
                                  # Remove the virtual items. there should only be one
                    my $items = $biblio->items;
                    while ( my $item = $items->next ) {
                        $item->delete;
                    }

                    # Remove the virtual biblio
                    $biblio->delete;
                }

                $req->status('B_ITEM_IN_TRANSIT')->store;

                $self->{plugin}->get_client( $self->{pod} )->borrower_item_returned( { circId => $circId }, $options );
            }
        );
        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    }
}

=head3 borrower_cancel

    $actions->borrower_cancel( $ill_request, $params );

Cancel an ILL request from the borrower side.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - client_options: Options to pass to the Rapido client

=cut

sub borrower_cancel {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    my $circId = $self->{plugin}->get_req_circ_id($req);

    return try {
        Koha::Database->new->schema->txn_do(
            sub {
                $req->status('B_ITEM_CANCELLED_BY_US')->store;

                $self->{plugin}->get_client( $self->{pod} )->borrower_cancel( { circId => $circId }, $options );
            }
        );
        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    }
}

=head3 borrower_renew

    $actions->borrower_renew( $ill_request, $params );

Renew an ILL request from the borrower side. The renewal is announced
to the lender.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - due_date: The new due date
  - client_options: Options to pass to the Rapido client

=cut

sub borrower_renew {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    my $circId = $self->{plugin}->get_req_circ_id($req);

    return try {
        Koha::Database->new->schema->txn_do(
            sub {
                $req->status('B_ITEM_RENEWAL_REQUESTED')->store;

                # Convert due_date to DateTime with end-of-day time (23:59:59)
                my $due_datetime = dt_from_string( $params->{due_date} );
                $due_datetime->set_time_zone('local');
                $due_datetime->set( hour => 23, minute => 59, second => 59 );

                # Store current due_date as prevDueDateTime before updating
                if ( $req->due_date ) {
                    my $prev_due_epoch = dt_from_string( $req->due_date )->epoch;
                    $self->{plugin}->add_or_update_attributes(
                        {
                            request    => $req,
                            attributes => { prevDueDateTime => $prev_due_epoch }
                        }
                    );
                }

                $req->set( { due_date => $due_datetime->datetime() } )->store();

                # Set checkout note for renewal request if configured
                my $config = $self->{plugin}->configuration->{ $self->{pod} };
                if ( $config->{renewal_request_note} ) {
                    my $checkout = $self->{plugin}->get_checkout($req);
                    if ($checkout) {
                        $checkout->set(
                            {
                                notedate => dt_from_string(),
                                note     => $config->{renewal_request_note},
                                noteseen => 0
                            }
                        )->store();
                    }
                }

                $self->{plugin}->get_client( $self->{pod} )->borrower_renew(
                    {
                        circId      => $circId,
                        dueDateTime => $due_datetime
                    },
                    $options
                );
            }
        );
        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    }
}

=head3 item_received

Method to notify the owning site that the item has been received.

=cut

sub item_received {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $circId = $self->{plugin}->get_req_circ_id($req);

                # Update status
                $req->status('B_ITEM_RECEIVED')->store;

                # Notify Rapido API
                $self->{plugin}->get_client( $self->{pod} )->borrower_item_received(
                    {
                        circId => $circId,
                    },
                    $options
                );
            }
        );

        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    };
}

=head3 return_uncirculated

Method to notify the owning site that the item is being returned uncirculated
and perform cleanup of biblio, items, and holds.

This method expects the following data to exist (created during item_shipped):
- Biblio: The temporary biblio record created for the ILL request
- Hold: The hold placed on the biblio for the requesting patron
- Item: The unique item record created and attached to the biblio

If any of these are missing, warnings will be logged but the method will continue
to ensure the API notification is sent and status is updated.

=cut

sub return_uncirculated {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $circId = $self->{plugin}->get_req_circ_id($req);

                # Notify Rapido API first
                $self->{plugin}->get_client( $self->{pod} )->borrower_return_uncirculated(
                    {
                        circId => $circId,
                    },
                    $options
                );

                # Cleanup biblio, items, and holds (created during item_shipped)
                my $biblio = Koha::Biblios->find( $req->biblio_id );

                if ($biblio) {

                    # Remove hold(s) - should be exactly one hold for the requesting patron
                    my $holds      = $biblio->holds;
                    my $hold_count = 0;

                    while ( my $hold = $holds->next ) {
                        $hold->cancel;
                        $hold_count++;
                    }

                    if ( $hold_count == 0 ) {
                        $self->{plugin}->logger->warn( "[return_uncirculated] No holds found for biblio "
                                . $req->biblio_id
                                . " (ILL request "
                                . $req->id
                                . ") - hold should have been created during item_shipped" );
                    }

                    # Remove item(s) - should be exactly one item created during item_shipped
                    my $items      = $biblio->items;
                    my $item_count = 0;

                    while ( my $item = $items->next ) {
                        $item->safe_delete;
                        $item_count++;
                    }

                    if ( $item_count == 0 ) {
                        $self->{plugin}->logger->warn( "[return_uncirculated] No items found for biblio "
                                . $req->biblio_id
                                . " (ILL request "
                                . $req->id
                                . ") - item should have been created during item_shipped" );
                    } elsif ( $item_count > 1 ) {
                        $self->{plugin}
                            ->logger->warn( "[return_uncirculated] Multiple items ($item_count) found for biblio "
                                . $req->biblio_id
                                . " (ILL request "
                                . $req->id
                                . ") - expected exactly one item" );
                    }

                    # Delete the biblio record
                    DelBiblio( $req->biblio_id );
                } else {
                    $self->{plugin}->logger->warn( "[return_uncirculated] Biblio "
                            . $req->biblio_id
                            . " not found for ILL request "
                            . $req->id
                            . " - biblio should have been created during item_shipped" );
                }

                # Update status
                $req->status('B_ITEM_RETURN_UNCIRCULATED')->store;
            }
        );

        return $self;
    } catch {
        RapidoILL::Exception->throw(
            sprintf(
                "Unhandled exception: %s",
                $_
            )
        );
    };
}

1;
