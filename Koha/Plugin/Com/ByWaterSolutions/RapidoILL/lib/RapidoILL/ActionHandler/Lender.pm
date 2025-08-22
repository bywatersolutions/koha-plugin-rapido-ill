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
        'FINAL_CHECKIN'   => \&final_checkin,
        'ITEM_IN_TRANSIT' => \&item_in_transit,
        'ITEM_RECEIVED'   => \&item_received,
        'ITEM_SHIPPED'    => \&item_shipped,
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

                $self->{plugin}->rapido_warn(
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

                $self->{plugin}->rapido_warn(
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

=head2 Lender-generated actions (us)

=head3 final_checkin

    $handler->final_checkin( $action );

Handle incoming I<FINAL_CHECKIN> action.

=cut

sub final_checkin {
    my ( $self, $action ) = @_;

    # This was triggered by us. No action

    return;
}

=head3 item_shipped

    $handler->item_shipped( $action );

Handle incoming I<ITEM_SHIPPED> action.

=cut

sub item_shipped {
    my ( $self, $action ) = @_;

    # This was triggered by us. No action

    return;
}

1;
