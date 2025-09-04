package RapidoILL::Backend::LenderActions;

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

use RapidoILL::Exceptions;

=head1 NAME

RapidoILL::Backend::LenderActions - Backend utilities for lender-side ILL request operations

=head1 SYNOPSIS

    use RapidoILL::Backend::LenderActions;

    my $actions = RapidoILL::Backend::LenderActions->new(
        {
            pod    => $pod,
            plugin => $plugin,
        }
    );

    # ILL request utility methods
    $actions->cancel_request( $req, $params );
    $actions->item_shipped( $req, $params );
    $actions->final_checkin( $req, $params );

=head1 DESCRIPTION

Backend utility class for lender-side ILL request operations. This class provides
methods for performing backend operations on ILL requests from the lender perspective.

Note: CircAction processing is handled by RapidoILL::ActionHandler::Lender.

=head2 Class methods

=head3 new

    my $actions = RapidoILL::Backend::LenderActions->new(
        {
            pod    => $pod,
            plugin => $plugin,
        }
    );

Constructor for the lender actions utility class.

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

=head3 cancel_request

    $actions->cancel_request( $ill_request, $params );

Cancel an ILL request from the lender side.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - client_options: Options to pass to the Rapido client

=cut

sub cancel_request {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $attrs = $req->extended_attributes;

                my $circId = $self->{plugin}->get_req_circ_id($req);
                my $pod    = $self->{pod};

                # Handle missing patronName attribute gracefully
                my $patronName = '';
                my $patronName_attr = $attrs->find( { type => 'patronName' } );
                if ($patronName_attr) {
                    $patronName = $patronName_attr->value;
                } else {
                    $self->{plugin}->logger->warn(
                        sprintf(
                            "Missing patronName attribute for ILL request %d, using empty string",
                            $req->id
                        )
                    );
                }

                # Handle missing hold_id attribute gracefully
                my $hold_id_attr = $attrs->find( { type => 'hold_id' } );
                if ($hold_id_attr) {
                    my $hold = Koha::Holds->find( $hold_id_attr->value );
                    $hold->cancel if $hold;
                } else {
                    $self->{plugin}->logger->warn(
                        sprintf(
                            "Missing hold_id attribute for ILL request %d, skipping hold cancellation",
                            $req->id
                        )
                    );
                }

                # notify Rapido. Throws an exception if failed
                $self->{plugin}->get_client($pod)->lender_cancel(
                    {
                        circId     => $circId,
                        localBibId => $req->biblio_id,
                        patronName => $patronName,
                    },
                    $options
                );

                $req->status('O_ITEM_CANCELLED_BY_US')->store;
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

=head3 item_shipped

    $actions->item_shipped( $ill_request, $params );

Mark an ILL request as item shipped from the lender side.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - client_options: Options to pass to the Rapido client

=cut

sub item_shipped {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    my $circId = $self->{plugin}->get_req_circ_id($req);
    my $pod    = $self->{pod};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $attrs  = $req->extended_attributes;
                my $itemId = $attrs->find( { type => 'itemId' } )->value;

                my $item     = Koha::Items->find( { barcode => $itemId } );
                my $patron   = Koha::Patrons->find( $req->borrowernumber );
                my $checkout = Koha::Checkouts->find( { itemnumber => $item->id } );

                if ($checkout) {
                    if ( $checkout->borrowernumber != $req->borrowernumber ) {
                        RapidoILL::Exception->throw(
                            sprintf(
                                "Request borrowernumber (%s) doesn't match the checkout borrowernumber (%s)",
                                $checkout->borrowernumber, $req->borrowernumber
                            )
                        );
                    }

                    # else {} # The item is already checked out to the right patron
                } else {    # no checkout, proceed
                    $checkout = $self->{plugin}->add_issue( { patron => $patron, barcode => $item->barcode } );
                }

                # record checkout_id
                $self->{plugin}->add_or_update_attributes(
                    {
                        request    => $req,
                        attributes => { checkout_id => $checkout->id },
                    }
                );

                # update status
                $req->status('O_ITEM_SHIPPED')->store;

                # notify Rapido. Throws an exception if failed
                $self->{plugin}->get_client($pod)->lender_shipped(
                    {
                        callNumber  => $item->itemcallnumber,
                        circId      => $circId,
                        itemBarcode => $item->barcode,
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

=head3 final_checkin

    $actions->final_checkin( $ill_request, $params );

Perform final checkin for an ILL request from the lender side.

Parameters:
- $ill_request: The ILL request object
- $params: Optional hashref with:
  - client_options: Options to pass to the Rapido client

=cut

sub final_checkin {
    my ( $self, $req, $params ) = @_;

    $params //= {};
    my $options = $params->{client_options} // {};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $circId = $self->{plugin}->get_req_circ_id($req);
                my $pod    = $self->{pod};

                # update status with paper trail
                $req->status('O_ITEM_CHECKED_IN')->store();
                $req->status('COMP')->store();

                # notify Rapido. Throws an exception if failed
                $self->{plugin}->get_client($pod)->lender_checkin( { circId => $circId, }, $options );
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

=head3 renewal_request

    $actions->renewal_request( $ill_request, $params );

Process a renewal approval from the lender. Rejection is not supported by the Rapido API.

Parameters:
- $ill_request: The ILL request object
- $params: Hashref with:
  - approve: Must be true (rejections not supported)
  - new_due_date: New due date if approved (optional)
  - client_options: Options to pass to the Rapido client

=cut

sub renewal_request {
    my ( $self, $req, $params ) = @_;

    my $approve      = $params->{approve} // 0;
    my $new_due_date = $params->{new_due_date};
    my $options      = $params->{client_options} // {};

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $circId = $self->{plugin}->get_req_circ_id($req);
                my $pod    = $self->{pod};

                if ($approve) {

                    # Update due date if provided
                    if ($new_due_date) {

                        # Update checkout due date
                        my $checkout = $self->{plugin}->get_checkout($req);
                        if ($checkout) {
                            $checkout->date_due($new_due_date)->store();
                        }

                        # Store new due date in attributes
                        $self->{plugin}->add_or_update_attributes(
                            {
                                request    => $req,
                                attributes => {
                                    due_date              => $new_due_date,
                                    renewal_approved_date => \'NOW()',
                                }
                            }
                        );
                    }

                    # Notify Rapido of approval
                    $self->{plugin}->get_client($pod)->lender_renew(
                        {
                            circId => $circId,
                            ( $new_due_date ? ( dueDateTime => $new_due_date->epoch ) : () ),
                        },
                        $options
                    );

                    $self->{plugin}->logger->info(
                        sprintf(
                            "Renewal approved for ILL request %d (circId: %s)",
                            $req->id,
                            $circId
                        )
                    );

                    # Return to ITEM_RECEIVED status after approval
                    $req->status('O_ITEM_RECEIVED_DESTINATION')->store();
                }

                # Note: Rejection is not supported by the Rapido API as per Ex Libris announcement
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

1;
