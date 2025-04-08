package RapidoILL::QueuedTasks;

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

use RapidoILL::QueuedTask;

use base qw(Koha::Objects);

=head1 NAME

RapidoILL::QueuedTasks - Queued tasks object set class

=head1 API

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillTaskQueue';
}

=head3 object_class

=cut

sub object_class {
    return 'RapidoILL::QueuedTask';
}

1;