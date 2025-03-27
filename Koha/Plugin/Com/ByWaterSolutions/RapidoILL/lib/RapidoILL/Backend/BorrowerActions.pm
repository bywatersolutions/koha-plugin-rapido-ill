package RapidoILL::Backend::BorrowerActions;

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

use RapidoILL::Exceptions;

=head1 RapidoILL::Backend::BorrowerActions

A class implementing Rapido ILL borrower site actions.

=head2 Class methods

=head3 new

    my $actions = RapidoILL::Backend::BorrowerActions->new(
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

    $borrower_actions->handle_from_action( $action );

Method for dispatching methods based on the passed I<$action> status.

=cut

sub handle_from_action {
    my ( $self, $action ) = @_;

    my $status_to_method = {
        'DEFAULT'      => \&default_handler,
        'ITEM_SHIPPED' => \&lender_item_shipped,
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
            "[borrower_actions][handle_action] No method implemented for handling a %s status",
            $action->lastCircState
        )
    );
}

=head2 Class methods

=head3 lender_item_shipped

=cut

sub lender_item_shipped {
    my ($self, $action) = @_;

    my $req     = $action->ill_request;
    my $barcode = $action->itemBarcode;

    RapidoILL::Exception->throw( "[borrower_actions][lender_item_shipped] No barcode in request. FIXME" )
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

            my $config = $self->{plugin}->configuration->{$action->pod};

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

            # Update request
            $req->set(
                {
                    biblio_id => $item->biblionumber,
                    status    => 'B_ITEM_SHIPPED',
                }
            );
        }
    );

    return;
}

=head3 borrower_receive_unshipped

    $client->borrower_receive_unshipped(
        {
            circId => $circId,
        },
        [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_receive_unshipped {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(request callnumber barcode)], } );

    my $req = $params->{request};

    my $attributes = {
        itemBarcode => $params->{barcode},
        callNumber  => $params->{callnumber},
    };

    my $barcode = $params->{barcode};

    my $schema = Koha::Database->new->schema;
    try {
        $schema->txn_do(
            sub {
                # check if already catalogued. INN-Reach requires no barcode collision
                my $item = Koha::Items->find( { barcode => $barcode } );

                if ($item) {

                    # already exists, add suffix
                    my $i = 1;
                    my $done;

                    while ( !$done ) {
                        my $tmp_barcode = $barcode . "-$i";
                        $item = Koha::Items->find( { barcode => $tmp_barcode } );

                        if ( !$item ) {
                            $barcode = $tmp_barcode;
                            $done    = 1;
                        } else {
                            $i++;
                        }
                    }

                    $attributes->{barcode_collision} = 1;
                }

                my $config = $self->{configuration}->{ $self->{pod} };

                # Create the MARC record and item
                $item = $self->{plugin}->add_virtual_record_and_item(
                    {
                        req         => $req,
                        config      => $config,
                        call_number => $params->{callnumber},
                        barcode     => $params->{barcode},
                    }
                );

                # Place an item-level hold
                my $hold_id = $self->{plugin}->add_hold(
                    {
                        branchcode       => $req->branchcode,
                        borrowernumber   => $req->borrowernumber,
                        biblionumber     => $item->biblionumber,
                        priority         => 1,
                        reservation_date => undef,
                        expiration_date  => undef,
                        notes            => $config->{default_hold_note} // 'Placed by ILL',
                        title            => q{},
                        itemnumber       => $item->id,
                        found            => undef,
                        itemtype         => $item->effective_itemtype
                    }
                );

                $attributes->{hold_id} = $hold_id;

                # Update request
                $req->biblio_id( $item->biblionumber )->status('B_ITEM_RECEIVED')->store;

                $self->{plugin}->add_or_update_attributes(
                    {
                        attributes => $attributes,
                        request    => $req,
                    }
                );

                $self->{plugin}->get_client( $self->{pod} )->borrower_receive_unshipped;
            }
        );
    } catch {
        $_->rethrow();
    };

    return;
}

=head3 item_in_transit

    $client->item_in_transit(
        {
            request => $request,
        },
      [ { skip_api_request => 0|1 } ]
    );

=cut

sub item_in_transit {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(request)], } );

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $circId = $self->{plugin}->get_req_circ_id($req);

    my $schema = Koha::Database->new->schema;
    try {
        $schema->txn_do(
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
                    foreach my $item ( $biblio->items->as_list ) {
                        $item->delete( { skip_record_index => 1 } );
                    }
                    DelBiblio( $biblio->id );
                }

                $req->status('B_ITEM_IN_TRANSIT')->store;

                $self->{plugin}->get_client( $self->{pod} )->borrower_item_returned( { circId => $circId }, $options );
            }
        );
    } catch {
        $_->rethrow();
    };

    return;
}

=head3 borrower_cancel

    $client->borrower_cancel(
        {
            request => $request,
        },
      [ { skip_api_request => 0|1 } ]
    );

=cut

sub borrower_cancel {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(request)], } );

    my $req    = $params->{request};
    my $circId = $self->{plugin}->get_req_circ_id($req);

    my $schema = Koha::Database->new->schema;
    try {
        $schema->txn_do(
            sub {
                $req->status('B_ITEM_CANCELLED_BY_US')->store;

                $self->{plugin}->get_client( $self->{pod} )->borrower_cancel( { circId => $circId }, $options );
            }
        );
    } catch {
        $_->rethrow();
    };

    return;
}

1;
