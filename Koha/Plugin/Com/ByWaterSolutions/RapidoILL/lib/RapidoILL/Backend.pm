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
use Koha::ILL::Requests;
use Koha::ILL::Request::Attributes;
use Koha::Items;
use Koha::Patrons;

use RapidoILL::Exceptions;

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
        unless $params->{plugin}
        && ref( $params->{plugin} ) eq 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL';

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
            ui_method_icon => 'fa-solid fa-paper-plane',
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
        O_RENEWAL_REQUESTED => {
            prev_actions   => [],
            id             => 'O_RENEWAL_REQUESTED',
            name           => 'Renewal requested by borrowing library',
            ui_method_name => '',
            method         => '',
            next_actions   => ['O_RENEWAL_HANDLED'],
            ui_method_icon => '',
        },
        O_RENEWAL_HANDLED => {    # not a real status
            prev_actions   => ['O_RENEWAL_REQUESTED'],
            id             => 'O_RENEWAL_HANDLED',
            name           => 'Renewal requested by borrowing library',
            ui_method_name => 'Handle renewal',
            method         => 'renewal_request',
            next_actions   => ['O_ITEM_RECEIVED_DESTINATION'],
            ui_method_icon => 'fa-clock-rotate-left',

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
            method         => 'borrower_cancel',
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
            next_actions   => [
                'B_ITEM_IN_TRANSIT', 'B_ITEM_CLAIMED_RETURNED',
                'B_ITEM_RETURN_UNCIRCULATED'
            ],
            ui_method_icon => 'fa-inbox',
        },
        B_ITEM_RENEWAL_REQUESTED => {
            prev_actions   => ['B_ITEM_RECEIVED'],
            id             => 'B_ITEM_RENEWAL_REQUESTED',
            name           => 'Renewal requested to owning library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => [],
            ui_method_icon => 'fa-arrow-rotate-right',
        },
        B_ITEM_RENEWAL_ACCEPTED => {
            prev_actions   => ['B_ITEM_RENEWAL_REQUESTED'],
            id             => 'B_ITEM_RENEWAL_ACCEPTED',
            name           => 'Renewal accepted owning library',
            ui_method_name => q{},
            method         => q{},
            next_actions   => [],
            ui_method_icon => 'fa-arrow-rotate-right',
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

    my $request = $params->{request};
    my $pod     = $self->{plugin}->get_req_pod($request);

    return try {
        $self->{plugin}->get_lender_actions($pod)->item_shipped($request);

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
        $self->{plugin}->logger->warn("[item_shipped] $_");
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

        my $recall_due_date =
            dt_from_string( $params->{other}->{recall_due_date} );

        return try {

            my $response = $self->{plugin}->get_http_client($centralCode)->post_request(
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

    my $request = $params->{request};
    my $pod     = $self->{plugin}->get_req_pod($request);

    return try {
        $self->{plugin}->get_lender_actions($pod)->final_checkin($request);

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'item_checkin',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        $self->{plugin}->logger->warn("[item_checkin] $_");
        return {
            error   => 1,
            message => "$_",
            method  => 'item_checkin',
            stage   => 'commit',
            status  => 'error',
            value   => q{},
        };
    };
}

=head3 cancel_request

Method triggered by the UI, to cancel the request. Can only happen when the request
is on O_ITEM_REQUESTED status.

=cut

sub cancel_request {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $pod     = $self->{plugin}->get_req_pod($request);

    return try {

        $self->{plugin}->get_lender_actions($pod)->cancel_request($request);

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'cancel_request',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        $self->{plugin}->logger->warn("[cancel_request] $_");
        return {
            error    => 1,
            message  => "$_ | " . $_->method . " - " . $_->response->decoded_content,
            method   => 'cancel_request',
            stage    => 'init',
            status   => 'error',
            template => 'cancel_request',
        };
    };
}

=head2 Requesting site methods

=head3 item_received

Method triggered by the UI, to notify the owning site that the item has been
received.

=cut

sub item_received {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $pod     = $self->{plugin}->get_req_pod($request);

    return try {
        $self->{plugin}->get_borrower_actions($pod)->item_received($request);

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'item_received',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        $self->{plugin}->logger->warn("[item_received] $_");
        return {
            status   => 'error',
            error    => 1,
            message  => "$_",
            stage    => 'init',
            method   => 'item_received',
            template => 'item_received',
        };
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

        my $request = $params->{request};
        my $pod     = $self->{plugin}->get_req_pod($request);

        return try {

            $self->{plugin}->get_borrower_actions($pod)->borrower_receive_unshipped(
                $request,
                {
                    circId     => $self->{plugin}->get_req_circ_id($request),
                    attributes => {
                        callnumber => $params->{other}->{item_callnumber},
                        barcode    => $params->{other}->{item_barcode}
                    },
                    barcode => $params->{other}->{item_barcode}
                }
            );

            return {
                error   => 0,
                status  => q{},
                message => q{},
                method  => 'receive_unshipped',
                stage   => 'commit',
                next    => 'illview',
                value   => q{},
            };

        } catch {
            $self->{plugin}->logger->warn("[receive_unshipped] $_");

            # FIXME: need to check error type
            return {
                status   => 'error',
                error    => 1,
                message  => "$_ | " . $_->method . " - " . $_->response->decoded_content,
                stage    => 'init',
                method   => 'receive_unshipped',
                template => 'receive_unshipped',
            };
        };
    }
}

=head3 item_in_transit

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub item_in_transit {
    my ( $self, $params ) = @_;

    return try {
        my $pod = $self->{plugin}->get_req_pod( $params->{request} );
        $self->{plugin}->get_borrower_actions($pod)->item_in_transit( $params->{request} );

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
        $self->{plugin}->logger->warn("[item_in_transit] $_");

        # FIXME: need to check error type
        return {
            status   => 'error',
            error    => 1,
            message  => "$_ | " . $_->method . " - " . $_->response->decoded_content,
            stage    => 'init',
            method   => 'item_in_transit',
            template => 'item_in_transit',
        };
    };
}

=head3 return_uncirculated

Method triggered by the UI, to notify the owning site the item has been
sent back to them and is in transit.

=cut

sub return_uncirculated {
    my ( $self, $params ) = @_;

    my $request = $params->{request};
    my $pod     = $self->{plugin}->get_req_pod($request);

    return try {
        $self->{plugin}->get_borrower_actions($pod)->return_uncirculated($request);

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'return_uncirculated',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
    } catch {
        $self->{plugin}->logger->warn("[return_uncirculated] $_");
        return {
            error   => 1,
            message => "$_",
            method  => 'return_uncirculated',
            stage   => 'commit',
            status  => 'error',
            value   => q{},
        };
    };
}

=head3 borrower_cancel

Method triggered by the UI, to cancel the request. Can only happen when the request
is on B_ITEM_REQUESTED status.

=cut

sub borrower_cancel {
    my ( $self, $params ) = @_;

    my $req = $params->{request};

    return try {
        $self->{plugin}->get_borrower_actions( $self->{plugin}->get_req_pod($req) )->borrower_cancel($req);
        return {
            status  => q{},
            message => q{},
            method  => 'illview',
            stage   => 'commit',
        };
    } catch {

        # HTTP client already logged detailed HTTP info with [context: borrower_cancel]
        $self->{plugin}->logger->warn("[borrower_cancel] Operation failed");

        my $message = "Borrower cancellation failed";
        if ( ref($_) eq 'RapidoILL::Exception::RequestFailed' ) {

            # Extract basic error info for user-facing message
            my $status_line = $_->response->status_line || 'Unknown HTTP error';
            $message = "Borrower cancellation failed: HTTP " . $status_line;
        } else {
            $message = "Borrower cancellation failed: $_";
        }

        my $result = {
            status   => 'error',
            error    => 1,
            stage    => 'init',
            method   => 'borrower_cancel',
            template => 'borrower_cancel',
            message  => $message,
        };

        return $result;
    };
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

    my $response = $self->{plugin}->get_http_client($centralCode)->post_request(
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

=head3 renewal_request

    $backend->renewal_request( $params );

Handle renewal approval/rejection from the UI form.

=cut

sub renewal_request {
    my ( $self, $params ) = @_;

    my $request      = $params->{request};
    my $decision     = $params->{other}->{decision};
    my $new_due_date = $params->{other}->{new_due_date};
    my $stage        = $params->{other}->{stage};

    my $pod = $self->{plugin}->get_req_pod($request);

    if ( !$stage || $stage eq 'init' ) {

        # Get borrower's requested due date and convert from epoch
        my $borrower_requested_attr = $request->extended_attributes->find( { type => 'borrower_requested_due_date' } );
        my $borrower_requested_due_date;

        if ( $borrower_requested_attr && $borrower_requested_attr->value ) {
            $borrower_requested_due_date = $self->{plugin}->epoch_to_end_of_day( $borrower_requested_attr->value );
        }

        return {
            error   => 0,
            status  => q{},
            message => q{},
            method  => 'renewal_request',
            stage   => 'form',
            value   => { borrower_requested_due_date => $borrower_requested_due_date }
        };
    }

    return try {
        if ( $decision eq 'approve' ) {

            # Get the borrower's requested due date from attributes
            my $borrower_requested_attr =
                $request->extended_attributes->find( { type => 'borrower_requested_due_date' } );
            my $borrower_requested_due_date = $borrower_requested_attr ? $borrower_requested_attr->value : undef;

            # Determine which due date to use
            my $due_date_obj;
            if ($new_due_date) {

                # Staff override date
                try {
                    $due_date_obj = dt_from_string($new_due_date);

                    # Set time to 23:59:59 for Koha consistency
                    $due_date_obj->set_hour(23)->set_minute(59)->set_second(59);
                } catch {
                    return {
                        error   => 1,
                        status  => 'invalid_due_date',
                        message => "Invalid due date passed: $_",
                        method  => 'renewal_request',
                        stage   => 'commit',
                        next    => 'illview',
                        value   => q{},
                    };
                };
            } elsif ($borrower_requested_due_date) {

                # Use borrower's requested date - convert from epoch
                $due_date_obj = $self->{plugin}->epoch_to_end_of_day($borrower_requested_due_date);
            }

            # Process renewal decision
            $self->{plugin}->get_lender_actions($pod)
                ->process_renewal_decision( $request, { approve => 1, new_due_date => $due_date_obj } );

            return {
                error   => 0,
                status  => '',
                message => "Request renewed",
                method  => 'renewal_request',
                stage   => 'commit',
                next    => 'illview',
                value   => q{},
            };
        }

    } catch {
        $self->{plugin}->logger->error("Error processing renewal decision: $_");
        return {
            error   => 1,
            status  => 'error_on_renewal',
            message => "Error processing renewal decision: $_",
            method  => 'renewal_request',
            stage   => 'commit',
            next    => 'illview',
            value   => q{},
        };
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
