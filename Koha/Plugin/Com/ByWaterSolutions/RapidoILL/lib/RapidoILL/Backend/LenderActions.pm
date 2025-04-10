package RapidoILL::Backend::LenderActions;

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

use Encode;
use JSON      qw( decode_json );
use Try::Tiny qw(catch try);

use Koha::Checkouts;
use Koha::Database;
use Koha::Items;
use Koha::Holds;
use Koha::Patrons;

use RapidoILL::Exceptions;

=head1 RapidoILL::Backend::LenderActions

A class implementing Rapido ILL lender site actions.

=head2 Class methods

=head3 new

    my $actions = RapidoILL::Backend::LenderActions->new(
        {
            pod    => $pod,
            plugin => $plugin,
        }
    );

Constructor for the API client class.

=cut

sub new {
    my ( $class, $params ) = @_;

    my @mandatory_params = qw(pod plugin);
    foreach my $param (@mandatory_params) {
        RapidoILL::Exception::MissingParameter->throw("Missing parameter: $param")
            unless $params->{$param};
    }

    my $self = {
        pod    => $params->{pod},
        plugin => $params->{plugin},
    };

    bless $self, $class;

    return $self;
}

=head3 handle_from_action

    $lender_actions->handle_from_action( $action );

Method for dispatching methods based on the passed I<$action> status.

=cut

sub handle_from_action {
    my ( $self, $action ) = @_;

    my $status_to_method = {
        'FINAL_CHECKIN'   => \&lender_final_checkin,
        'ITEM_RECEIVED'   => \&borrower_item_received,
        'ITEM_IN_TRANSIT' => \&borrower_item_in_transit,
        'ITEM_SHIPPED'    => \&lender_item_shipped,
        'DEFAULT'         => \&default_handler,
    };

    my $status =
        exists $status_to_method->{ $action->lastCircState }
        ? $action->lastCircState
        : 'DEFAULT';

    return $status_to_method->{$status}->( $self, $action );
}

=head3 default_handler

Throws an exception.

=cut

sub default_handler {
    my ( $self, $action ) = @_;
    RapidoILL::Exception::UnhandledException->throw(
        sprintf(
            "[lender_actions][handle_action] No method implemented for handling a %s status",
            $action->lastCircState
        )
    );
}

=head2 Borrower-generated actions

=head3 borrower_item_received

    $client->borrower_item_received( { action  => $action } );

FIXME: This should probably take an ILL request instead or have them both optional.
       implement as needed, Tomas!

=cut

sub borrower_item_received {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {
            if ( !$req->extended_attributes->search( { type => q{checkout_id} } )->count ) {
                my $item   = Koha::Items->find( $action->itemId );
                my $patron = Koha::Patrons->find( $req->borrowernumber );

                my $checkout = $self->{plugin}->add_issue( { patron => $patron, barcode => $item->barcode } );

                $self->{plugin}->add_or_update_attributes(
                    {
                        request    => $req,
                        attributes => {
                            checkout_id => $checkout->id,
                        }
                    }
                );

                $self->{plugin}->rapido_warn(
                    sprintf(
                        "[lender_actions][borrower_item_received]: Request %s set to O_ITEM_RECEIVED_DESTINATION but didn't have a 'checkout_id' attribute",
                        $req->id
                    )
                );
            }

            $req->status('O_ITEM_RECEIVED_DESTINATION')->store;
        }
    );

    return;
}

=head3 borrower_item_in_transit

    $client->borrower_item_in_transit( { action  => $action } );

FIXME: This should probably take an ILL request instead or have them both optional.
       implement as needed, Tomas!

=cut

sub borrower_item_in_transit {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {
            if ( !$req->extended_attributes->search( { type => q{checkout_id} } )->count ) {
                my $item   = Koha::Items->find( { barcode => $action->itemBarcode } );
                my $patron = Koha::Patrons->find( $req->borrowernumber );

                my $checkout = $self->{plugin}->add_issue( { patron => $patron, barcode => $item->barcode } );

                $self->{plugin}->add_or_update_attributes(
                    {
                        request    => $req,
                        attributes => {
                            checkout_id => $checkout->id,
                        }
                    }
                );

                $self->{plugin}->rapido_warn(
                    sprintf(
                        "[lender_actions][borrower_item_in_transit]: Request %s set to O_ITEM_IN_TRANSIT but didn't have a 'checkout_id' attribute",
                        $req->id
                    )
                );
            }

            $req->status('O_ITEM_IN_TRANSIT')->store;
        }
    );

    return;
}

=head3 final_checkin

    $client->final_checkin( $action );

=cut

sub lender_final_checkin {
    my ( $self, $action ) = @_;

    $action->ill_request->status('COMP')->store;

    return;
}

=head3 item_shipped

    $client->item_shipped( $action );

=cut

sub lender_item_shipped {
    my ( $self, $action ) = @_;

    # This was triggered by us. No action

    return;
}

=head3 cancel_request

    $client->cancel_request( $req );

=cut

sub cancel_request {
    my ( $self, $req ) = @_;

    Koha::Database->schema->storage->txn_do(
        sub {
            my $attrs = $req->extended_attributes;

            my $circId = $self->{plugin}->get_req_circ_id($req);
            my $pod    = $self->{plugin}->get_req_pod($req);

            my $patronName = $attrs->find( { type => 'patronName' } )->value;

            # Cancel after the request status change, so the condition for the hook is not met
            my $hold = Koha::Holds->find( $attrs->find( { type => 'hold_id' } )->value );
            $hold->cancel
                if $hold;

            # notify Rapido. Throws an exception if failed
            $self->{plugin}->get_client($pod)->lender_cancel(
                {
                    circId     => $circId,
                    localBibId => $req->biblio_id,
                    patronName => $patronName,
                }
            );

            $req->status('O_ITEM_CANCELLED_BY_US')->store;
        }
    );

    return;
}

=head3 item_shipped

    $client->item_shipped( $req );

=cut

sub item_shipped {
    my ( $self, $req ) = @_;

    my $circId = $self->{plugin}->get_req_circ_id($req);
    my $pod    = $self->{plugin}->get_req_pod($req);

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
                }
            );
        }
    );

    return;
}

1;
