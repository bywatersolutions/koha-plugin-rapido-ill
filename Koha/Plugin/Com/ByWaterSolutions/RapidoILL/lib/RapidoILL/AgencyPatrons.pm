package RapidoILL::AgencyPatrons;

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

use RapidoILL::AgencyPatron;

use base qw(Koha::Objects);

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillAgencyToPatron';
}

sub object_class {
    return 'RapidoILL::AgencyPatron';
}

1;
