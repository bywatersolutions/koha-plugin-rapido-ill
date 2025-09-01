package RapidoILL::ActionHandler::Borrower;

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

use DateTime;
use Encode;
use JSON            qw( decode_json );
use List::MoreUtils qw( any );
use Try::Tiny       qw(catch try);

use C4::Biblio qw(DelBiblio);

use Koha::Biblios;
use Koha::Checkouts;
use Koha::Database;
use Koha::Items;

use RapidoILL::Exceptions;

=head1 RapidoILL::ActionHandler::Borrower

A class implementing Rapido ILL borrower site actions.

=head2 Class methods

=head3 new

Constructor for the Borrower ActionHandler.

    my $handler = RapidoILL::ActionHandler::Borrower->new({
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

    $handler->handle_from_action( $action );

Method for dispatching methods based on the passed I<$action> status.

=cut

sub handle_from_action {
    my ( $self, $action ) = @_;

    my $status_to_method = {
        'DEFAULT'       => \&default_handler,
        'FINAL_CHECKIN' => \&final_checkin,
        'ITEM_RECEIVED' => \&handle_item_received,
        'ITEM_SHIPPED'  => \&item_shipped,
        'OWNER_RENEW'   => \&owner_renew,
    };

    # Statuses that require no action from borrower perspective
    my @no_op_statuses = qw(
        BORROWER_RENEW
        ITEM_IN_TRANSIT
        PATRON_HOLD
    );

    # Check if this is a no-op status first
    if ( any { $_ eq $action->lastCircState } @no_op_statuses ) {

        # No action needed for these statuses
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
            "[borrower_actions][handle_action] No method implemented for handling a %s status",
            $action->lastCircState
        )
    );
}

=head2 Lender-generated actions

=head3 final_checkin

    $handler->final_checkin( $action );

Handle incoming I<ITEM_RECEIVED> action. From borrower perspective - the
lender has received the item back and completed the transaction.

=cut

sub final_checkin {
    my ( $self, $action ) = @_;

    # The lender has received the item back and completed the transaction
    # From the borrower's perspective, this means the request is complete
    my $req = $action->ill_request;
    $req->status('B_ITEM_CHECKED_IN')->store();
    $req->status('COMP')->store();

    return;
}

=head3 item_shipped

    $handler->item_shipped( $action );

Handle incoming I<ITEM_SHIPPED> action. Creates a virtual record and item,
places a hold for the patron, and updates the ILL request status. If the
action contains a dueDateTime (epoch), sets the due_date on the ILL request.

=cut

sub item_shipped {
    my ( $self, $action ) = @_;

    my $req     = $action->ill_request;
    my $barcode = $action->itemBarcode;

    RapidoILL::Exception->throw("[borrower_actions][item_shipped] No barcode in request. FIXME")
        unless $barcode;

    my $attributes = {
        author             => $action->author,
        borrowerCode       => $action->borrowerCode,
        callNumber         => $action->callNumber,
        circ_action_id     => $action->circ_action_id,
        circId             => $action->circId,
        circStatus         => $action->circStatus,
        dateCreated        => $action->dateCreated,
        dueDateTime        => $action->dueDateTime,
        itemAgencyCode     => $action->itemAgencyCode,
        itemBarcode        => $action->itemBarcode,
        itemId             => $action->itemId,
        lastCircState      => $action->lastCircState,
        lastUpdated        => $action->lastUpdated,
        lenderCode         => $action->lenderCode,
        needBefore         => $action->needBefore,
        patronAgencyCode   => $action->patronAgencyCode,
        patronId           => $action->patronId,
        patronName         => $action->patronName,
        pickupLocation     => $action->pickupLocation,
        pod                => $action->pod,
        puaLocalServerCode => $action->puaLocalServerCode,
        title              => $action->title,
    };

    Koha::Database->new->schema->txn_do(
        sub {
            my ( $biblio_id, $item_id, $biblioitemnumber );

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
                    } else {
                        $i++;
                    }
                }

                $attributes->{barcode_collision} = 1;
            }

            my $config = $self->{plugin}->configuration->{ $action->pod };

            # Create the MARC record and item
            my $item = $self->{plugin}->add_virtual_record_and_item(
                {
                    req         => $req,
                    config      => $config,
                    call_number => $attributes->{callNumber},
                    barcode     => $barcode,
                }
            );

            # Place a hold on the item
            my $hold_id = $self->{plugin}->add_hold(
                {
                    biblio_id  => $item->biblionumber,
                    item_id    => $item->id,
                    library_id => $req->branchcode,
                    patron_id  => $req->borrowernumber,
                    notes      => exists $config->{default_hold_note}
                    ? $config->{default_hold_note}
                    : 'Placed by ILL',
                }
            );

            # We need to store the hold_id
            $attributes->{hold_id} = $hold_id;

            # Update attributes
            $self->{plugin}->add_or_update_attributes(
                {
                    attributes => $attributes,
                    request    => $req,
                }
            );

            my $due_date;

            # Set due_date from dueDateTime epoch if available
            $due_date = DateTime->from_epoch( epoch => $action->dueDateTime )
                if $action->dueDateTime;

            $req->set(
                {
                    biblio_id => $item->biblionumber,
                    ( $due_date ? ( due_date => $due_date->datetime() ) : () ),
                }
            );

            $req->status('B_ITEM_SHIPPED')->store();
        }
    );

    return;
}

=head3 owner_renew

    $handler->owner_renew( $action );

Handle incoming I<OWNER_RENEW> action. From borrower perspective - the
owner has accepted our renewal request and a new due date needs to be set.

=cut

sub owner_renew {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {

            my $due_date;

            # Set due_date from dueDateTime epoch if available
            $due_date = DateTime->from_epoch( epoch => $action->dueDateTime )
                if $action->dueDateTime;

            $req->set(
                {
                    ( $due_date ? ( due_date => $due_date->datetime() ) : () ),
                }
            );

            $req->status('B_ITEM_RENEWAL_ACCEPTED')->store();

            # [#61] Update checkout due date if we have a new dueDateTime
            if ($due_date) {
                my $checkout = $self->{plugin}->get_checkout($req);
                if ($checkout) {
                    $checkout->date_due( $due_date->datetime() );
                    $checkout->store();
                } else {
                    $self->{plugin}->logger->warn(
                        sprintf(
                            "No checkout found for ILL request %d during renewal approval - could not update checkout due date",
                            $req->id
                        )
                    );
                }
            }
        }
    );

    return;
}

=head3 handle_item_received

    $handler->handle_item_received( $action );

Handle incoming I<ITEM_RECEIVED> action. This could be either:
1. Initial item receipt (no action needed)
2. Renewal rejection (need to update status)

=cut

sub handle_item_received {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    # Check if this is a renewal rejection by looking at the current ILL request status
    # If the request is in a renewal state, this ITEM_RECEIVED is a rejection
    if ( $req->status eq 'B_ITEM_RENEWAL_REQUESTED' ) {

        Koha::Database->new->schema->txn_do(
            sub {
                # Get the previous due date from attributes
                my $prev_due_attr = $req->extended_attributes->find( { type => 'prevDueDateTime' } );
                my $prev_due_date;

                if ( $prev_due_attr && $prev_due_attr->value ) {
                    $prev_due_date = DateTime->from_epoch( epoch => $prev_due_attr->value );

                    # Restore the previous due date in the ILL request
                    $req->set( { due_date => $prev_due_date->datetime() } );

                    # Update the checkout due date as well
                    my $checkout = $self->{plugin}->get_checkout($req);
                    if ($checkout) {
                        $checkout->date_due( $prev_due_date->datetime() );
                        $checkout->store();
                    } else {
                        $self->{plugin}->logger->warn(
                            sprintf(
                                "No checkout found for ILL request %d during renewal rejection - could not restore checkout due date",
                                $req->id
                            )
                        );
                    }
                }

                # Renewal was rejected, transition back to received state
                $req->status('B_ITEM_RECEIVED')->store();

                # Add renewal rejection attribute for staff notices
                $self->{plugin}->add_or_update_attributes(
                    {
                        attributes => { renewal_rejected => \'NOW()' },
                        request    => $req,
                    }
                );

                # Log the renewal rejection
                $self->{plugin}->logger->info(
                    sprintf(
                        "Renewal rejected for ILL request %d (circId: %s) - status reverted to B_ITEM_RECEIVED, due date restored",
                        $req->id,
                        $action->circId
                    )
                );
            }
        );
    }

    # Otherwise, this is just a regular ITEM_RECEIVED state - no action needed

    return;
}

1;
