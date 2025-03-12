package RapidoILL::CircAction;

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

use Koha::ILL::Requests;
use Koha::Items;

use base qw(Koha::Object);

=head1 NAME

RapidoILL::CircAction - Circulation action Object class

=head1 API

=head2 Class methods

=head3 ill_request

    my $req = $action->ill_request;

Get the linked I<Koha::ILL::Request> object.

=cut

sub ill_request {
    my ($self) = @_;
    return Koha::ILL::Requests->find( $self->illrequest_id );
}

=head3 item

    my $req = $action->item;

Get the linked I<Koha::Item> object.

=cut

sub item {
    my ($self) = @_;
    return Koha::Items->find( $self->itemId );
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillCircAction';
}

1;
