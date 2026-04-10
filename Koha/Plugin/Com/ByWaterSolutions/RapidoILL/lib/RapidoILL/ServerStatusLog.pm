package RapidoILL::ServerStatusLog;

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

use JSON qw(encode_json);

use base qw(Koha::Object);

=head1 NAME

RapidoILL::ServerStatusLog - Server status log entry Object class

=head2 Class methods

=head3 store

    $log->store();

Overloaded store method that JSON-encodes C<affected_task_ids> if it
contains a reference.

=cut

sub store {
    my ($self) = @_;

    if ( defined $self->affected_task_ids && ref( $self->affected_task_ids ) ) {
        $self->set( { affected_task_ids => encode_json( $self->affected_task_ids ) } );
    }

    return $self->SUPER::store();
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillServerStatusLog';
}

1;
