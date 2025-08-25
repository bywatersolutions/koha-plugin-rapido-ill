package RapidoILL::Client;

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
use JSON            qw( decode_json );
use Koha::DateUtils qw(dt_from_string);
use Try::Tiny       qw(catch try);

use RapidoILL::Exceptions;

=head1 RapidoILL::Client

A class implementing an API client for Rapido ILL.

=head2 Class methods

=head3 new

    my $client = RapidoILL::Client->new(
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
        RapidoILL::Exception::MissingParameter->throw( param => $param )
            unless $params->{$param};
    }

    my $pod = $params->{pod};

    my $self = {
        pod           => $pod,
        configuration => $params->{plugin}->configuration->{$pod},
        ua            => $params->{plugin}->get_http_client($pod),
        plugin        => $params->{plugin},
    };

    bless $self, $class;

    return $self;
}

=head2 Client methods

=head3 locals

    $client->locals(
      [ { skip_api_request => 0|1 } ]
    );

=cut

sub locals {
    my ( $self, $options ) = @_;

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->get_request(
            {
                endpoint => "/view/broker/locals",
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'locals', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head2 LENDING SITE Client methods

=head3 lender_cancel

    $client->lender_cancel(
        {
            circId     => $circId,
            localBibId => $localBibId,
            patronName => $patronName,
        },
      [ { skip_api_request => 0|1 } ]
    );

=cut

sub lender_cancel {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId localBibId patronName)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/lendercancel',
                data     => {
                    localBibId => $params->{localBibId},
                    patronName => $params->{patronName},
                    reason     => '',
                }
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'lender_cancel', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 lender_visiting_patron_checkout

    $client->lender_visiting_patron_checkout(
        {
            circId     => $circId,
            localBibId => $localBibId,
            patronName => $patronName,
        },
      [ { skip_api_request => 0|1 } ]
    );

=cut

sub lender_visiting_patron_checkout {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params(
        {
            params   => $params,
            required => [
                qw(
                    patronId
                    patronAgencyCode
                    centralPatronType
                    uuid
                    patronName
                    items
                )
            ],
        }
    );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/visitingpatroncheckout',
                data     => {
                    patronId          => $params->{localBibId},
                    patronAgencyCode  => $params->{patronAgencyCode},
                    centralPatronType => $params->{centralPatronType},
                    uuid              => $params->{uuid},
                    patronName        => $params->{patronName},
                    items             => $params->{items},
                }
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'lender_visiting_patron_checkout', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 lender_checkin

    $client->lender_checkin(
        {
            circId => $circId,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub lender_checkin {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/lendercheckin',
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'lender_checkin', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 lender_shipped

    $client->lender_shipped(
        {
            callNumber  => $callNumber,
            circId      => $circId,
            itemBarcode => $itemBarcode,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub lender_shipped {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(callNumber circId itemBarcode)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/lendershipped',
                data     => {
                    callNumber  => $params->{callNumber},
                    itemBarcode => $params->{itemBarcode},
                }
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'lender_shipped', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head2 BORROWING SITE Client methods

=head3 borrower_item_received

    $client->borrower_item_received(
        {
            circId => $circId,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_item_received {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/itemreceived',
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'borrower_item_received', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 borrower_receive_unshipped

    $client->borrower_item_receive_unshipped(
        {
            circId => $circId,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_receive_unshipped {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/receiveunshipped',
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'borrower_item_receive_unshipped', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 borrower_cancel

    $client->borrower_cancel(
        {
            circId => $circId,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_cancel {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response =
            $self->{ua}->post_request( { 
                endpoint => '/view/broker/circ/' . $params->{circId} . '/borrowercancel',
                context => 'borrower_cancel'
            } );

        RapidoILL::Exception::RequestFailed->throw( method => 'borrower_cancel', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 borrower_renew

    $client->borrower_renew(
        {
            circId      => $circId,
            dueDateTime => $checkout->date_due,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_renew {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId dueDateTime)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/borrowerrenew',
                data     => { dueDateTime => dt_from_string( $params->{dueDateTime} )->epoch }
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'borrower_renew', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head3 borrower_item_returned

    $client->borrower_item_returned(
        {
            circId => $circId,
        },
      [ { skip_api_request => 0 | 1 } ]
    );

=cut

sub borrower_item_returned {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(circId)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {
        my $response = $self->{ua}->post_request(
            {
                endpoint => '/view/broker/circ/' . $params->{circId} . '/itemreturned',
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'borrower_item_returned', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

=head2 General client methods

=head3 circulation_requests

    $client->circulation_requests(
        {
            startTime  => $epoch,
            endTime    => $epoch,
          [ state      => ['ACTIVE','COMPLETED','INACTIVE','CREATED','CANCELED'],
            content    => 'concise'|'verbose',
            timeTarget => 'lastUpdated'|'dateCreated', ]
        },
      [ { skip_api_request => 0 | 1 } ]
    );

I<startTime> and I<endTime> are the only mandatory parameter.

=cut

sub circulation_requests {
    my ( $self, $params, $options ) = @_;

    $self->{plugin}->validate_params( { params => $params, required => [qw(startTime endTime)], } );

    if ( !$self->{configuration}->{dev_mode} && !$options->{skip_api_request} ) {

        my $response = $self->{ua}->get_request(
            {
                endpoint => '/view/broker/circ/circrequests',
                query    => {
                    startTime => $params->{startTime},
                    endTime   => $params->{endTime},
                    ( $params->{state}      ? ( state      => $params->{state} )      : () ),
                    ( $params->{content}    ? ( content    => $params->{content} )    : () ),
                    ( $params->{timeTarget} ? ( timeTarget => $params->{timeTarget} ) : () ),
                }
            }
        );

        RapidoILL::Exception::RequestFailed->throw( method => 'circulation_requests', response => $response )
            unless $response->is_success;

        return decode_json( encode( 'UTF-8', $response->decoded_content ) );
    }

    return;
}

1;
