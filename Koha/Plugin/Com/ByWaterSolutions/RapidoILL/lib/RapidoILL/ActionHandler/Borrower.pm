package RapidoILL::ActionHandler::Borrower;

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

use DateTime;
use Encode;
use JSON            qw( decode_json );
use List::MoreUtils qw( any );
use Try::Tiny       qw(catch try);

use Koha::Biblios;
use Koha::Checkouts;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
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
        'DEFAULT'            => \&default_handler,
        'FINAL_CHECKIN'      => \&final_checkin,
        'ITEM_RECEIVED'      => \&item_received,
        'ITEM_SHIPPED'       => \&item_shipped,
        'OWNER_RENEW'        => \&owner_renew,
        'OWNING_SITE_CANCEL' => \&owner_cancel,
        'PATRON_HOLD'        => \&patron_hold,
        'RECALL'             => \&recall,
    };

    # Statuses that require no action from borrower perspective
    my @no_op_statuses = qw(
        BORROWER_RENEW
        BORROWING_SITE_CANCEL
        ITEM_IN_TRANSIT
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
places a hold for the patron, and updates the ILL request status. The Rapido
dueDateTime is captured on the sync record but not applied: the checkout due
date is ILS-defined (calculated by Koha's circulation rules when the hold is
filled).

=cut

sub item_shipped {
    my ( $self, $action ) = @_;

    my $req     = $action->ill_request;
    my $barcode = $action->itemBarcode;

    RapidoILL::Exception->throw("[borrower_actions][item_shipped] No barcode in request. FIXME")
        unless $barcode;

    # Idempotency guard: if the request already has a virtual biblio/item, this
    # ITEM_SHIPPED action is a replay (e.g. the pod re-sent it with a newer
    # lastUpdated). Creating a new record here would collide with the barcode of
    # the record we already created and produce a duplicate '-N' biblio/item.
    if ( $req->biblio_id ) {
        $self->{plugin}->logger->info(
            sprintf(
                "[borrower_actions][item_shipped] ILL request %d (circId=%s) already has biblio_id=%s; skipping virtual record creation (replayed action)",
                $req->id, $action->circId, $req->biblio_id
            )
        );
        return;
    }

    my $attributes = {
        author             => $action->author,
        borrowerCode       => $action->borrowerCode,
        callNumber         => $action->callNumber,
        centralItemType    => $action->centralItemType,
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

            # Resolve item type from centralItemType if present
            my $item_type = $self->{plugin}->get_item_type_from_central(
                {
                    central_item_type => $action->centralItemType,
                    pod               => $action->pod,
                    fallback          => $config->{default_item_type} // 'ILL',
                }
            );

            # Create the MARC record and item
            my $item = $self->{plugin}->add_virtual_record_and_item(
                {
                    req         => $req,
                    config      => $config,
                    call_number => $attributes->{callNumber},
                    barcode     => $barcode,
                    item_type   => $item_type,
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

            # Due dates are ILS-defined: the checkout due date is calculated by
            # Koha's circulation rules when the hold is filled. The Rapido
            # dueDateTime is captured on the sync record (see attributes above)
            # but is not applied to the ILL request.

            # Update attributes
            $self->{plugin}->add_or_update_attributes(
                {
                    attributes => $attributes,
                    request    => $req,
                }
            );

            $req->set(
                {
                    biblio_id => $item->biblionumber,
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
owner has accepted our renewal request. Due dates are ILS-defined, so the
Rapido dueDateTime is not applied to the checkout or the ILL request; the
renewal due date is calculated by Koha's circulation rules.

=cut

sub owner_renew {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {

            $req->status('B_ITEM_RENEWAL_ACCEPTED')->store();

            # Set checkout note for renewal acceptance if configured
            my $config = $self->{plugin}->pod_config( $self->{pod} );
            if ( $config->{renewal_accepted_note} ) {
                my $checkout = $self->{plugin}->get_checkout($req);
                if ($checkout) {
                    $checkout->set(
                        {
                            notedate => dt_from_string(),
                            note     => $config->{renewal_accepted_note},
                            noteseen => 0
                        }
                    )->store();
                }
            }
        }
    );

    return;
}

=head3 item_received

    $handler->item_received( $action );

Handle incoming I<ITEM_RECEIVED> action. This could be either:
1. Initial item receipt (no action needed)
2. Renewal rejection (need to update status)

=cut

sub item_received {
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

=head3 recall

    $handler->recall( $action );

Handle incoming I<RECALL> action. Transitions the ILL request to B_ITEM_RECALLED status.

=cut

sub recall {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {
            $req->status('B_ITEM_RECALLED')->store;

            $self->{plugin}->logger->info(
                sprintf(
                    "Item recalled for ILL request %d (circId: %s) - status set to B_ITEM_RECALLED",
                    $req->id,
                    $action->circId
                )
            );
        }
    );

    return;
}

=head3 owner_cancel

    $handler->owner_cancel( $action );

Handle incoming I<OWNING_SITE_CANCEL> action. The owning site has cancelled
the request. Updates the ILL request status and cleans up any virtual records.

=cut

sub owner_cancel {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    Koha::Database->new->schema->txn_do(
        sub {
            # Update the ILL request status to cancelled by owner
            $req->status('B_CANCELLED_BY_OWNER')->store();

            # Add cancellation attributes for tracking
            $self->{plugin}->add_or_update_attributes(
                {
                    attributes => {
                        cancelled_by_owner  => \'NOW()',
                        cancellation_reason => 'OWNING_SITE_CANCEL'
                    },
                    request => $req,
                }
            );

            # Clean up the virtual record (biblio/item/hold) and item-specific
            # attributes created during item_shipped, if any.
            $self->_cleanup_virtual_record( { request => $req, context => 'owner_cancel' } );

            $self->{plugin}->logger->info(
                sprintf(
                    "Request cancelled by owner for ILL request %d (circId: %s) - status set to B_CANCELLED_BY_OWNER",
                    $req->id,
                    $action->circId
                )
            );
        }
    );

    return;
}

=head3 patron_hold

    $handler->patron_hold( $action );

Handle incoming I<PATRON_HOLD> action.

In the normal forward flow this is the initial state and requires no action.
However, Rapido also sends I<PATRON_HOLD> when the lending library B<unships>
an item that had already been shipped, but another copy is still available
(the request goes back to waiting for a shipment). In that case we must undo
whatever was created for the previous shipment: delete the virtual
bib/item/hold, remove the item-specific attributes, and revert the request to
B_ITEM_REQUESTED so a later ITEM_SHIPPED is processed cleanly.

The unship cleanup runs when the request is at B_ITEM_REQUESTED or
B_ITEM_SHIPPED; any other status is treated as a no-op.

A paper trail is recorded for each unship: an C<unshipped> timestamp, an
C<unship_count> running counter (so repeated ship/unship cycles are
visible), and C<last_unship_state>. The B_ITEM_SHIPPED -> B_ITEM_REQUESTED
status change is additionally logged in Koha's ILL request status log.

=cut

sub patron_hold {
    my ( $self, $action ) = @_;

    my $req = $action->ill_request;

    my %unship_from = map { $_ => 1 } qw( B_ITEM_REQUESTED B_ITEM_SHIPPED );
    return unless $unship_from{ $req->status };

    Koha::Database->new->schema->txn_do(
        sub {
            my $was_shipped = $req->status eq 'B_ITEM_SHIPPED';

            # Undo any shipment artifacts (virtual record + item-specific attrs).
            $self->_cleanup_virtual_record( { request => $req, context => 'patron_hold' } );

            # Back to waiting for a shipment.
            $req->status('B_ITEM_REQUESTED')->store();

            # Paper trail: record the unship. Keep a running count so repeated
            # ship/unship cycles are visible (a single timestamp attribute would
            # otherwise be overwritten each time). The status change itself
            # (B_ITEM_SHIPPED -> B_ITEM_REQUESTED) is also recorded in Koha's
            # ILL request status log.
            my $count_attr = $req->extended_attributes->find( { type => 'unship_count' } );
            my $count = ( $count_attr && $count_attr->value ) ? $count_attr->value : 0;
            $self->{plugin}->add_or_update_attributes(
                {
                    attributes => {
                        unshipped         => \'NOW()',
                        unship_count      => $count + 1,
                        last_unship_state => ( $was_shipped ? 'B_ITEM_SHIPPED' : 'B_ITEM_REQUESTED' ),
                    },
                    request => $req,
                }
            );

            $self->{plugin}->logger->info(
                sprintf(
                    "Item unshipped for ILL request %d (circId: %s) - status reverted to B_ITEM_REQUESTED (unship #%d)",
                    $req->id,
                    $action->circId,
                    $count + 1,
                )
            );
        }
    );

    return;
}

=head3 _cleanup_virtual_record

    $handler->_cleanup_virtual_record( { request => $req, context => 'patron_hold' } );

Internal helper. Deletes the virtual biblio (and its items/holds, via
C<delete_virtual_biblio>) linked to the request, clears the request's
C<biblio_id>, and removes the item-specific attributes created during
C<item_shipped>. Safe to call when no virtual record exists.

=cut

sub _cleanup_virtual_record {
    my ( $self, $params ) = @_;

    my $req     = $params->{request};
    my $context = $params->{context} || 'cleanup_virtual_record';

    if ( $req->biblio_id ) {
        my $biblio = Koha::Biblios->find( $req->biblio_id );

        if ($biblio) {
            my $error = $self->{plugin}->delete_virtual_biblio(
                {
                    biblio  => $biblio,
                    context => $context,
                }
            );

            if ($error) {
                $self->{plugin}->logger->warn( "[$context] Failed to delete biblio "
                        . $req->biblio_id
                        . " for ILL request "
                        . $req->id
                        . ": $error" );
            }
        } else {
            $self->{plugin}->logger->warn( "[$context] Biblio "
                    . $req->biblio_id
                    . " not found for ILL request "
                    . $req->id
                    . " - biblio should have been created during item_shipped" );
        }

        $req->set( { biblio_id => undef } )->store();
    }

    # Remove item-specific attributes tied to the (now removed) shipment.
    my @item_specific = qw(
        barcode_collision
        callNumber
        centralItemType
        dueDateTime
        hold_id
        itemBarcode
        itemId
    );

    $req->extended_attributes->search( { type => { -in => \@item_specific } } )->delete;

    return;
}

1;
