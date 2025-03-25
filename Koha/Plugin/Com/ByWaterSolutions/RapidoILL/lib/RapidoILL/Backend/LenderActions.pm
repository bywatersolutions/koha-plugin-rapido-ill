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

=head3 handle_action

=cut

sub handle_action {
    my ( $self, $action ) = @_;

    my $status_to_method = {
        'ITEM_RECEIVED' => \&borrower_item_received,
    };

    if ( !exists $status_to_method->{ $action->lastCircState } ) {
        RapidoILL::Exception::UnhandledException->throw(
            sprintf(
                "[lender_actions][handle_action] No method implemented for handling a %s status",
                $action->lastCircState
            )
        );
    }

    return $self->$action;
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
                    );
                );
            }

            $req->status('O_ITEM_RECEIVED_DESTINATION')->store;
        }
    );

    return;
}

1;
