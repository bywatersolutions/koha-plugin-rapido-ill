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

use Try::Tiny;
use Koha::Database;

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
                    request    => $request,
                    attributes => $attributes,
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

    Koha::Database->new->schema->txn_do(
        sub {
            $req->status('B_ITEM_CANCELLED_BY_US')->store;

            $self->{plugin}->get_client( $self->{pod} )->borrower_cancel( { circId => $circId }, $options );
        }
    );

    return $self;
}

1;
