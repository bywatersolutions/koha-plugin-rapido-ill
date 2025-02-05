package RapidoILL::Backend;

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
use Try::Tiny qw(catch try);

use Koha::Database;

use C4::Biblio   qw(DelBiblio);
use C4::Reserves qw(AddReserve);

use Koha::Biblios;
use Koha::Checkouts;
use Koha::DateUtils qw(dt_from_string);
use Koha::Holds;
use Koha::Items;
use Koha::Patrons;

use RapidoILL::Exceptions;

#use INNReach::Commands::BorrowingSite;

=head1 NAME

RapidoILL::Backend - Koha ILL Backend for Rapido ILL

=head1 SYNOPSIS

Koha ILL implementation for the "RapidoILL" backend.

=head1 DESCRIPTION

=head2 Overview

The Rapido ILL system acts as a broker for the ILL interactions between different
ILS.

=head2 Implementation

The Rapido ILL backend is a simple backend that implements two flows:

=over 4

=item Owning site workflow

=item Borrowing site workflow

=back

=head1 API

=head2 Class methods

=cut

=head3 new

  my $plugin  = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;
  my $backend = RapidoILL::Backend->new( { plugin => $plugin } );

Constructor for the ILL backend.

=cut

sub new {
    my ( $class, $params ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'plugin' )
        unless $params->{plugin} && ref( $params->{plugin} ) eq 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL';

    my $self = {
        configuration => $params->{plugin}->configuration,
        plugin        => $params->{plugin},
        templates     => $params->{templates},
        logger        => $params->{logger},
    };

    bless( $self, $class );
    return $self;
}

=head3 name

Return the name of this backend.

=cut

sub name {
    return "RapidoILL";
}

=head3 bundle_path

    my $path = $backend->bundle_path();

Returns the backend's defined template path.
FIXME: Review when consensus is reached on https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39031

=cut

sub bundle_path {
    my ($self) = @_;
    return $self->{plugin}->bundle_path . "/templates/";
}

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes store. We may want to ignore certain values
that we do not consider to be metadata

=cut

sub metadata {
    my ( $self, $request ) = @_;
    my $attrs       = $request->extended_attributes;
    my $metadata    = {};
    my @ignore      = ('requested_partners');
    my $core_fields = _get_core_fields();
    while ( my $attr = $attrs->next ) {
        my $type = $attr->type;
        if ( !grep { $_ eq $type } @ignore ) {
            my $name;
            $name = $core_fields->{$type} || ucfirst($type);
            $metadata->{$name} = $attr->value;
        }
    }
    return $metadata;
}

=head3 status_graph

This backend provides no additional actions on top of the core_status_graph.

=cut

sub status_graph {
    return {

        # status graph for owning site
        O_ITEM_REQUESTED => {
            prev_actions   => [],
            id             => 'O_ITEM_REQUESTED',
            name           => 'Item Requested',
            ui_method_name => 'Item Requested',
            method         => q{},
            next_actions   => [ 'O_ITEM_SHIPPED', 'O_ITEM_CANCELLED_BY_US' ],
            ui_method_icon => q{},
        },
        O_LOCAL_HOLD => {
            prev_actions   => [],
            id             => 'O_LOCAL_HOLD',
            name           => 'Local hold requested',
            ui_method_name => 'Local hold requested',
            method         => q{},
            next_actions   => ['COMP'],
            ui_method_icon => q{},
        },
        O_ITEM_CANCELLED => {
            prev_actions   => ['O_ITEM_REQUESTED'],
            id             => 'O_ITEM_CANCELLED',
            name           => 'Item request cancelled by requesting library',
            ui_method_name => 'Item request cancelled by requesting library',
            method         => q{},
            next_actions   => ['COMP'],
            ui_method_icon => q{},
        },
        O_ITEM_CANCELLED_BY_US => {
            prev_actions   => ['O_ITEM_REQUESTED'],
            id             => 'O_ITEM_CANCELLED_BY_US',
            name           => 'Item request cancelled',
            ui_method_name => 'Cancel request',
            method         => 'cancel_request',
            next_actions   => ['COMP'],
            ui_method_icon => 'fa-times',
        },
        O_ITEM_SHIPPED => {
            prev_actions   => ['O_ITEM_REQUESTED'],
            id             => 'O_ITEM_SHIPPED',
            name           => 'Item shipped to borrowing library',
            ui_method_name => 'Ship item',
            method         => 'item_shipped',
            next_actions   => [],
            ui_method_icon => 'fa-send-o',
        },
        O_ITEM_RECEIVED_DESTINATION => {
            prev_actions   => ['O_ITEM_SHIPPED'],
            id             => 'O_ITEM_RECEIVED_DESTINATION',
            name           => 'Item received by borrowing library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => [ 'O_ITEM_RECALLED', 'O_ITEM_CHECKED_IN' ],
            ui_method_icon => q{},
        },
        O_ITEM_RECALLED => {
            prev_actions   => ['O_ITEM_RECEIVED_DESTINATION'],
            id             => 'O_ITEM_RECALLED',
            name           => 'Item recalled to borrowing library',
            ui_method_name => 'Recall item',
            method         => 'item_recalled',
            next_actions   => [],
            ui_method_icon => 'fa-exclamation-circle',
        },
        O_ITEM_CLAIMED_RETURNED => {
            prev_actions   => ['O_ITEM_RECEIVED_DESTINATION'],
            id             => 'O_ITEM_CLAIMED_RETURNED',
            name           => 'Item claimed returned at borrowing library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => [],
            ui_method_icon => q{},
        },
        O_ITEM_IN_TRANSIT => {
            prev_actions   => [ 'O_ITEM_RECEIVED_DESTINATION', 'O_ITEM_CLAIMED_RETURNED' ],
            id             => 'O_ITEM_IN_TRANSIT',
            name           => 'Item in transit from borrowing library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => ['O_ITEM_CHECKED_IN'],
            ui_method_icon => 'fa-inbox',
        },
        O_ITEM_RETURN_UNCIRCULATED => {
            prev_actions   => [ 'O_ITEM_RECEIVED_DESTINATION', 'O_ITEM_CLAIMED_RETURNED' ],
            id             => 'O_ITEM_RETURN_UNCIRCULATED',
            name           => 'Item in transit from borrowing library (uncirculated)',
            ui_method_name => q{},
            method         => q{},
            next_actions   => ['O_ITEM_CHECKED_IN'],
            ui_method_icon => 'fa-inbox',
        },
        O_ITEM_CHECKED_IN => {
            prev_actions   => ['O_ITEM_IN_TRANSIT'],
            id             => 'O_ITEM_CHECKED_IN',
            name           => 'Item checked-in at owning library',
            ui_method_name => 'Check-in',
            method         => 'item_checkin',
            next_actions   => ['COMP'],
            ui_method_icon => 'fa-inbox',
        },

        # status graph for borrowing site
        B_ITEM_REQUESTED => {
            prev_actions   => [],
            id             => 'B_ITEM_REQUESTED',
            name           => 'Item requested to owning library',
            ui_method_name => 'Item requested to owning library',
            method         => q{},
            next_actions   => [ 'B_ITEM_CANCELLED_BY_US', 'B_RECEIVE_UNSHIPPED' ],
            ui_method_icon => q{},
        },
        B_ITEM_CANCELLED => {
            prev_actions   => [],
            id             => 'B_ITEM_CANCELLED',
            name           => 'Item request cancelled by owning library',
            ui_method_name => 'Item request cancelled by owning library',
            method         => q{},
            next_actions   => ['COMP'],
            ui_method_icon => q{},
        },
        B_ITEM_CANCELLED_BY_US => {
            prev_actions   => ['B_ITEM_REQUESTED'],
            id             => 'B_ITEM_CANCELLED_BY_US',
            name           => 'Item request cancelled',
            ui_method_name => 'Cancel request',
            method         => 'cancel_request_by_us',
            next_actions   => ['COMP'],
            ui_method_icon => 'fa-times',
        },
        B_ITEM_SHIPPED => {
            prev_actions   => [],
            id             => 'B_ITEM_SHIPPED',
            name           => 'Item shipped by owning library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => ['B_ITEM_RECEIVED'],
            ui_method_icon => q{},
        },
        B_RECEIVE_UNSHIPPED => {    # will never be set. Only used to present a form
            prev_actions   => ['B_ITEM_REQUESTED'],
            id             => 'B_RECEIVE_UNSHIPPED',
            name           => 'Item received (unshipped)',
            ui_method_name => 'Receive item (unshipped)',
            method         => 'receive_unshipped',
            next_actions   => [],
            ui_method_icon => 'fa-inbox',
        },
        B_ITEM_RECEIVED => {
            prev_actions   => ['B_ITEM_SHIPPED'],
            id             => 'B_ITEM_RECEIVED',
            name           => 'Item received',
            ui_method_name => 'Receive item',
            method         => 'item_received',
            next_actions   => [ 'B_ITEM_IN_TRANSIT', 'B_ITEM_CLAIMED_RETURNED', 'B_ITEM_RETURN_UNCIRCULATED' ],
            ui_method_icon => 'fa-inbox',
        },
        B_ITEM_RECALLED => {
            prev_actions   => [],
            id             => 'B_ITEM_RECALLED',
            name           => 'Item recalled by owning library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => ['B_ITEM_IN_TRANSIT'],
            ui_method_icon => q{},
        },
        B_ITEM_CLAIMED_RETURNED => {
            prev_actions   => ['B_ITEM_RECEIVED'],
            id             => 'B_ITEM_CLAIMED_RETURNED',
            name           => 'Claimed as returned',
            ui_method_name => 'Claim returned',
            method         => 'claims_returned',
            next_actions   => ['B_ITEM_IN_TRANSIT'],
            ui_method_icon => 'fa-exclamation-triangle',
        },
        B_ITEM_IN_TRANSIT => {
            prev_actions   => [ 'B_ITEM_RECEIVED', 'B_ITEM_CLAIMED_RETURNED' ],
            id             => 'B_ITEM_IN_TRANSIT',
            name           => 'Item in transit to owning library',
            ui_method_name => 'Item in transit',
            method         => 'item_in_transit',
            next_actions   => [],
            ui_method_icon => 'fa-send-o',
        },
        B_ITEM_RETURN_UNCIRCULATED => {
            prev_actions   => ['B_ITEM_RECEIVED'],
            id             => 'B_ITEM_RETURN_UNCIRCULATED',
            name           => 'Item in transit to owning library (uncirculated)',
            ui_method_name => 'Return uncirculated',
            method         => 'return_uncirculated',
            next_actions   => [],
            ui_method_icon => 'fa-send-o',
        },
        B_ITEM_CHECKED_IN => {
            prev_actions   => [ 'B_ITEM_IN_TRANSIT', 'B_ITEM_RETURN_UNCIRCULATED' ],
            id             => 'B_ITEM_CHECKED_IN',
            name           => 'Item checked-in at owning library',
            ui_method_name => 'Check-in',
            method         => q{},
            next_actions   => ['COMP'],
            ui_method_icon => q{},
        }
    };
}

=head2 Owning site methods

=head3 item_shipped

Method triggered by the UI, to notify the requesting site the item has been
shipped.

=cut

sub item_shipped {
    my ( $self, $params ) = @_;

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;
    my $itemId      = $attrs->find( { type => 'itemId' } )->value;

    my $item = Koha::Items->find($itemId);

    return try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $patron   = Koha::Patrons->find( $req->borrowernumber );
                my $checkout = Koha::Checkouts->find( { itemnumber => $itemId } );

                if ($checkout) {
                    if ( $checkout->borrowernumber != $req->borrowernumber ) {
                        return {
                            error   => 1,
                            status  => 'error_on_checkout',
                            message => "Item checked out to another patron.",
                            method  => 'item_shipped',
                            stage   => 'commit',
                            value   => q{},
                        };
                    }

                    # else {} # The item is already checked out to the right patron
                } else {    # no checkout, proceed
                    $checkout = $self->{plugin}->add_issue( { patron => $patron, barcode => $item->barcode } );
                }

                # record checkout_id
                $self->{plugin}->new_ill_request_attr(
                    {
                        illrequest_id => $req->illrequest_id,
                        type          => 'checkout_id',
                        value         => $checkout->id,
                        readonly      => 0
                    }
                )->store;

                # update status
                $req->status('O_ITEM_SHIPPED')->store;
            }
        );

        my $response = $self->{plugin}->get_ua($centralCode)->post_request(
            {
                endpoint    => "/innreach/v2/circ/itemshipped/$trackingId/$centralCode",
                centralCode => $centralCode,
                data        => {
                    callNumber  => $item->itemcallnumber // q{},
                    itemBarcode => $item->barcode        // q{},
                }
            }
        );

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'item_shipped',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        return {
            error   => 1,
            status  => 'error_on_checkout',
            message => "$_",
            method  => 'item_shipped',
            stage   => 'commit',
            value   => q{},
        };
    };
}

=head3 item_recalled

Method triggered by the UI, to notify the requesting site the item has been
recalled.

=cut

sub item_recalled {
    my ( $self, $params ) = @_;

    my $stage = $params->{other}->{stage};

    if ( !$stage || $stage eq 'init' ) {    # initial form, allow choosing date
        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'item_recalled',
            stage   => 'form'
        };
    } else {
        my $req   = $params->{request};
        my $attrs = $req->extended_attributes;

        my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
        my $centralCode = $attrs->find( { type => 'centralCode' } )->value;
        my $itemId      = $attrs->find( { type => 'itemId' } )->value;

        my $recall_due_date = dt_from_string( $params->{other}->{recall_due_date} );

        return try {

            my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                {
                    endpoint    => "/innreach/v2/circ/recall/$trackingId/$centralCode",
                    centralCode => $centralCode,
                    data        => {
                        dueDateTime => $recall_due_date->epoch,
                    }
                }
            );

            $req->status('O_ITEM_RECALLED')->store;

            return {
                error   => 0,
                status  => q{},
                message => q{},
                method  => 'item_recalled',
                stage   => 'commit',
                next    => 'illview',
                value   => q{},
            };
        } catch {
            return {
                error   => 1,
                status  => 'error_on_recall',
                message => "$_",
                method  => 'item_recalled',
                stage   => 'commit',
                value   => q{},
            };
        };
    }
}

=head3 item_checkin

Method triggered by the UI, to notify the requesting site that the final
item check-in has taken place.

=cut

sub item_checkin {
    my ( $self, $params ) = @_;

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
        {
            endpoint    => "/innreach/v2/circ/finalcheckin/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    $req->status('O_ITEM_CHECKED_IN')->store;

    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'item_checkin',
        stage   => 'commit',
        next    => 'illview',
        value   => q{},
    };
}

=head3 cancel_request

Method triggered by the UI, to cancel the request. Can only happen when the request
is on O_ITEM_REQUESTED status.

=cut

sub cancel_request {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $result = {
        status  => q{},
        message => q{},
        method  => 'illview',
        stage   => 'commit',
    };

    try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $attrs = $req->extended_attributes;

                my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
                my $centralCode = $attrs->find( { type => 'centralCode' } )->value;
                my $patronName  = $attrs->find( { type => 'patronName' } )->value;

                $req->status('O_ITEM_CANCELLED_BY_US')->store;

                # Cancel after the request status change, so the condition for the hook is not met
                my $hold = Koha::Holds->find( $attrs->find( { type => 'hold_id' } )->value );
                $hold->cancel
                    if $hold;

                # Make sure we notify the item status
                $self->{plugin}->schedule_task(
                    {
                        action         => 'modify',
                        central_server => $centralCode,
                        object_type    => 'item',
                        object_id      => $hold->itemnumber,
                    }
                );

                # skip actual INN-Reach interactions in dev_mode
                unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {
                    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                        {
                            endpoint    => "/innreach/v2/circ/owningsitecancel/$trackingId/$centralCode",
                            centralCode => $centralCode,
                            data        => {
                                localBibId => $req->biblio_id,
                                reason     => q{},
                                reasonCode => '7',
                                patronName => $patronName
                            }
                        }
                    );

                    RapidoILL::Exception::RequestFailed->throw( method => 'cancel_request', response => $response )
                        unless $response->is_success;
                }
            }
        );
    } catch {
        warn "[innreach] [cancel_request()] $_";

        $result->{status}   = 'innreach_error';
        $result->{error}    = 1;
        $result->{message}  = "$_ | " . $_->method . " - " . $_->response->decoded_content;
        $result->{stage}    = 'init';
        $result->{method}   = 'cancel_request';
        $result->{template} = 'cancel_request';
    };

    return $result;
}

=head2 Requesting site methods

=head3 item_received

Method triggered by the UI, to notify the owning site that the item has been
received.

=cut

sub item_received {
    my ( $self, $params ) = @_;

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

    # skip actual INN-Reach interactions in dev_mode
    unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {
        my $response = $self->{plugin}->get_ua($centralCode)->post_request(
            {
                endpoint    => "/innreach/v2/circ/itemreceived/$trackingId/$centralCode",
                centralCode => $centralCode,
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'cancel_request', response => $response )
            unless $response->is_success;
    }

    $req->status('B_ITEM_RECEIVED')->store;

    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'item_received',
        stage   => 'commit',
        next    => 'illview',
        value   => q{},
    };
}

=head3 receive_unshipped

Method triggered by the UI, to notify the owning site that the item has been
received.

=cut

sub receive_unshipped {
    my ( $self, $params ) = @_;

    my $stage = $params->{other}->{stage};

    if ( !$stage || $stage eq 'init' ) {    # initial form, allow choosing date
        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'receive_unshipped',
            stage   => 'form'
        };
    } else {                                # confirm

        my $req   = $params->{request};
        my $attrs = $req->extended_attributes;

        my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
        my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

        my $attributes = {
            callNumber  => $params->{other}->{item_callnumber},
            itemBarcode => $params->{other}->{item_barcode},
        };

        my $barcode = $params->{other}->{item_barcode};
        my $config  = $self->{configuration}->{$centralCode};

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

                    # Create the MARC record and item
                    $item = $self->{plugin}->add_virtual_record_and_item(
                        {
                            req         => $req,
                            config      => $config,
                            call_number => $attributes->{callNumber},
                            barcode     => $barcode,
                        }
                    );

                    # Place a hold on the item
                    my $patron_id = $req->borrowernumber;

                    my $hold_id = AddReserve(
                        {
                            branchcode       => $req->branchcode,
                            borrowernumber   => $patron_id,
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

                    my $commands = INNReach::Commands::BorrowingSite->new( { plugin => $self->{plugin} } );
                    try {
                        $commands->receive_unshipped($req);
                    } catch {
                        if ( ref($_) eq 'RapidoILL::Exception::RequestFailed' ) {
                            my $response = $_->response;
                            if ( $response->headers->header('X-IR-Allowed-Circulation') eq '[ITEM RECEIVED]' ) {

                                # we missed an 'itemshipped' message, and INN-Reach is rejecting
                                # the 'receiveunshipped' message we try to send. We are good, send itemreceived.
                                return $commands->item_received($req);
                            }
                        } else {

                            # unhandled exception!
                            $_->rethrow();
                        }
                    };
                }
            );
        } catch {
            $self->{plugin}->innreach_warn("$_");
            return {
                error   => 1,
                status  => q{},
                message => "$_",
                method  => 'receive_unshipped',
                stage   => 'form'
            };
        };
    }

    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'receive_unshipped',
        stage   => 'commit',
        next    => 'illview',
        value   => q{},
    };
}

=head3 item_in_transit

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub item_in_transit {
    my ( $self, $params ) = @_;

    return try {

        INNReach::Commands::BorrowingSite->new( { plugin => $self->{plugin} } )->item_in_transit( $params->{request} );

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'item_in_transit',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        return {
            error   => 1,
            status  => 'item_in_transit_error',
            message => "$_",
            method  => 'item_in_transit',
            stage   => 'commit',
            value   => q{},
        };
    };
}

=head3 return_uncirculated

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub return_uncirculated {
    my ( $self, $params ) = @_;

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
        {
            endpoint    => "/innreach/v2/circ/returnuncirculated/$trackingId/$centralCode",
            centralCode => $centralCode,
        }
    );

    Koha::Database->new->schema->txn_do(
        sub {
            # Cleanup!
            my $biblio = Koha::Biblios->find( $req->biblio_id );

            if ($biblio) {
                my $holds = $biblio->holds;

                # Remove hold(s)
                while ( my $hold = $holds->next ) {
                    $hold->cancel;
                }

                # Remove item(s)
                my $items = $biblio->items;
                while ( my $item = $items->next ) {
                    $item->safe_delete;
                }

                DelBiblio( $req->biblio_id );
            } else {
                $self->{plugin}->innreach_warn(
                    'Linked biblio_id (' . $req->biblio_id . ') not on the DB for ILL request (' . $req->id . ')' );
            }
        }
    );

    $req->status('B_ITEM_RETURN_UNCIRCULATED')->store;

    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'return_uncirculated',
        stage   => 'commit',
        next    => 'illview',
        value   => q{},
    };
}

=head3 cancel_request_by_us

Method triggered by the UI, to cancel the request. Can only happen when the request
is on B_ITEM_REQUESTED status.

=cut

sub cancel_request_by_us {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    my $result = {
        status  => q{},
        message => q{},
        method  => 'illview',
        stage   => 'commit',
    };

    try {
        Koha::Database->schema->storage->txn_do(
            sub {
                my $attrs = $req->extended_attributes;

                my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
                my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

                $req->status('B_ITEM_CANCELLED_BY_US')->store;

                # skip actual INN-Reach interactions in dev_mode
                unless ( $self->{configuration}->{$centralCode}->{dev_mode} ) {
                    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
                        {
                            endpoint    => "/innreach/v2/circ/cancelitemhold/$trackingId/$centralCode",
                            centralCode => $centralCode,
                        }
                    );

                    RapidoILL::Exception::RequestFailed->throw( method => 'cancel_request_by_us', response => $response )
                        unless $response->is_success;
                }
            }
        );
    } catch {
        $result->{status}   = 'innreach_error';
        $result->{error}    = 1;
        $result->{stage}    = 'init';
        $result->{method}   = 'cancel_request_by_us';
        $result->{template} = 'cancel_request_by_us';

        if ( ref($_) eq 'RapidoILL::Exception::RequestFailed' ) {
            $result->{message} = "$_ | " . $_->method . " - " . $_->response->decoded_content;
            warn "[innreach] [cancel_request_by_us()] " . $result->{message};
        } else {
            $result->{message} = "$_";
            warn "[innreach] [cancel_request_by_us()] $_";
        }
    };

    return $result;
}

=head3 claims_returned

Method triggered by the UI, to notify the owning site that the item has been
claimed returned.

=cut

sub claims_returned {
    my ( $self, $params ) = @_;

    my $req   = $params->{request};
    my $attrs = $req->extended_attributes;

    my $trackingId  = $attrs->find( { type => 'trackingId' } )->value;
    my $centralCode = $attrs->find( { type => 'centralCode' } )->value;

    my $response = $self->{plugin}->get_ua($centralCode)->post_request(
        {
            endpoint    => "/innreach/v2/circ/claimsreturned/$trackingId/$centralCode",
            centralCode => $centralCode,
            data        => { claimsReturnedDate => dt_from_string()->epoch }
        }
    );

    $req->status('B_ITEM_CLAIMED_RETURNED')->store;

    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'claims_returned',
        stage   => 'commit',
        next    => 'illview',
        value   => q{},
    };
}

=head3 get_log_template_path

    my $path = $backend->get_log_template_path($action);

Given an action, return the path to the template for displaying
that action log

=cut

sub get_log_template_path {
    my ( $self, $action ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'action' )
        unless $action;

    return $self->{templates}->{$action};
}

=head3 capabilities

    $capability = $backend->capabilities($name);

Return the sub implementing a capability selected by I<$name>, or 0 if that
capability is not implemented.

=cut

sub capabilities {
    my ( $self, $name ) = @_;
    my ($query) = @_;

    my $capabilities = {
        item_recalled => sub { $self->item_recalled(@_); }
    };

    return $capabilities->{$name};
}

=head2 Helper methods

=head3 create

=cut

sub create {
    return {
        error   => 0,
        status  => q{},
        message => q{},
        method  => 'create',
        stage   => q{},
        next    => 'illview',
        value   => q{},
    };
}

=head3 _get_core_fields

Return a hashref of core fields

=cut

sub _get_core_fields {
    return {
        type            => 'Type',
        title           => 'Title',
        container_title => 'Container Title',
        author          => 'Author',
        isbn            => 'ISBN',
        issn            => 'ISSN',
        part_edition    => 'Part / Edition',
        volume          => 'Volume',
        year            => 'Year',
        article_title   => 'Part Title',
        article_author  => 'Part Author',
        article_pages   => 'Part Pages',
    };
}

=head1 AUTHORS

Tomás Cohen Arazi <tomascohen@theke.io>

=cut

1;
