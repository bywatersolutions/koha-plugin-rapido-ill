package RapidoILL::CircActions;

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

use RapidoILL::CircAction;

use base qw(Koha::Objects);

=head1 NAME

RapidoILL::CircActions - Rapido ILL circulation actions object set class

=head1 API

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillCircAction';
}

=head3 object_class

=cut

sub object_class {
    return 'RapidoILL::CircAction';
}

1;
