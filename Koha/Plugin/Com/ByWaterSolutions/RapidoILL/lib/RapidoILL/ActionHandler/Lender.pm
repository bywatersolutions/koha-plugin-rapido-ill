package RapidoILL::ActionHandler::Lender;

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

use List::MoreUtils qw( any );
use Try::Tiny qw(catch try);

use Koha::Database;
use Koha::Items;
use Koha::Patrons;

use RapidoILL::Exceptions;

=head1 RapidoILL::ActionHandler::Lender

A class implementing Rapido ILL lender site actions.

=head2 Class methods

=head3 new

Constructor for the Lender ActionHandler.

    my $handler = RapidoILL::ActionHandler::Lender->new({
        pod    => $pod_name,
        plugin => $plugin_instance
    });

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

=head3 handle_from_action

    $action_handler->handle_from_action( $action );

Method for dispatching methods based on the passed I<$action> status.

=cut

sub handle_from_action {
    my ( $self, $action ) = @_;

    my $status_to_method = {
        'BORROWING_SITE_CANCEL' => \&borrowing_site_cancel,
        'ITEM_IN_TRANSIT'       => \&item_in_transit,
        'ITEM_RECEIVED'         => \&item_received,
        'DEFAULT'               => \&default_handler,
    };

    # Statuses that require no action from lender perspective
    my @no_op_statuses = qw(
        FINAL_CHECKIN
        ITEM_HOLD
        ITEM_SHIPPED
    );

    # Check if this is a no-op status first
    if ( any { $_ eq $action->lastCircState } @no_op_statuses ) {
        # No action needed for these statuses (triggered by us)
        return;
    }

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

=head3 item_received

    $handler->item_received($action);

Handle incoming I<ITEM_RECEIVED> action.

=cut

sub item_received {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {
            if ( !$req->extended_attributes->search( { type => q{checkout_id} } )->count ) {
                my $item   = Koha::Items->find( { barcode => $action->itemId } );
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

                $self->{plugin}->logger->warn(
                    sprintf(
                        "[lender_actions][item_received]: Request %s set to O_ITEM_RECEIVED_DESTINATION but didn't have a 'checkout_id' attribute",
                        $req->id
                    )
                );
            }

            $req->status('O_ITEM_RECEIVED_DESTINATION')->store;
        }
    );

    return;
}

=head3 item_in_transit

    $handler->item_in_transit($action);

Handle incoming I<ITEM_IN_TRANSIT> action.

=cut

sub item_in_transit {
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

                $self->{plugin}->logger->warn(
                    sprintf(
                        "[lender_actions][item_in_transit]: Request %s set to O_ITEM_IN_TRANSIT but didn't have a 'checkout_id' attribute",
                        $req->id
                    )
                );
            }

            $req->status('O_ITEM_IN_TRANSIT')->store;
        }
    );

    return;
}

=head3 borrowing_site_cancel

    $handler->borrowing_site_cancel($action);

Handle incoming I<BORROWING_SITE_CANCEL> action when the borrowing site cancels the request.

=cut

sub borrowing_site_cancel {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    # Wrap in transaction to ensure data consistency
    Koha::Database->schema->storage->txn_do(
        sub {
            # Set request status to cancelled
            $req->status('O_ITEM_CANCELLED')->store;

            # Cancel any associated hold if it exists
            my $attrs = $req->extended_attributes;
            my $hold_id_attr = $attrs->find( { type => 'hold_id' } );
            
            if ( $hold_id_attr ) {
                my $hold = Koha::Holds->find( $hold_id_attr->value );
                if ( $hold ) {
                    $hold->cancel;
                }
            }
        }
    );

    return;
}

1;
