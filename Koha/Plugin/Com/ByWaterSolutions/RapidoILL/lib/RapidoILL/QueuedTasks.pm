package RapidoILL::QueuedTasks;

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

use C4::Context;
use RapidoILL::QueuedTask;

use base qw(Koha::Objects);

=head1 NAME

RapidoILL::QueuedTasks - Queued tasks object set class

=head1 API

=head2 Class methods

=head3 filter_by_active

    my $active_tasks = $tasks->filter_by_active($attributes);

Filters the current resultset so it only contains active tasks.
I<$attributes> are passed through.

=cut

sub filter_by_active {
    my ( $self, $attributes ) = @_;

    return $self->search( { status => [qw(queued retry)] }, $attributes );
}

=head3 filter_by_runnable

    my $runnable_tasks = $tasks->filter_by_runnable();

Filters the current resultset so it only contains runnable tasks. This is
tasks that have an active status and also that are scheduled to be run.
I<$attributes> are passed through.

=cut

sub filter_by_runnable {
    my ( $self, $attributes ) = @_;

    return $self->search(
        {
            status => [qw(queued retry)],
            -or    => [ { run_after => undef }, { run_after => { '<' => \'NOW()' } } ]
        },
        $attributes
    );
}

=head3 enqueue

    my $queued_task = $queued_tasks->enqueue($params);

Enqueues a new task. I<$params> can include the task attributes.
Returns the new I<RapidoILL::QueuedTask> object.

=cut

sub enqueue {
    my ( $self, $attributes ) = @_;

    $attributes->{status} //= 'queued';

    # Use passed context or create default context
    $attributes->{context} //= {
        userenv   => C4::Context->userenv,
        interface => C4::Context->interface,
    };

    return RapidoILL::QueuedTask->new($attributes)->store();
}

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
