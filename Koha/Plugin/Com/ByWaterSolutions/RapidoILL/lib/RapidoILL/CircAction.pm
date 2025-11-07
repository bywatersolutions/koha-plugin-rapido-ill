package RapidoILL::CircAction;

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

# Suppress redefinition warnings when plugin is reloaded
no warnings 'redefine';

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
    return Koha::Items->find( { barcode => $self->itemId } );
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillCircAction';
}

1;
