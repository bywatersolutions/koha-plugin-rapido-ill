package RapidoILL::SyncLog;

# Copyright 2026 ByWater Solutions
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

no warnings 'redefine';

use JSON qw(encode_json);

use base qw(Koha::Object);

=head1 NAME

RapidoILL::SyncLog - Sync log Object class

=head2 Class methods

=head3 store

Overloaded store that JSON-encodes error_details if it's a reference.

=cut

sub store {
    my ($self) = @_;

    my $details = $self->error_details;
    if ( defined $details && ref($details) ) {
        $self->set( { error_details => encode_json($details) } );
    }

    return $self->SUPER::store();
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillSyncLog';
}

1;
