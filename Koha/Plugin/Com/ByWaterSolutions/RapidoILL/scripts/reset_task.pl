#!/usr/bin/env perl

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

use Getopt::Long;
use Pod::Usage;

use Koha::Script;
use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

use RapidoILL::QueuedTasks;

my $help;
my $task_id;
my $status;
my $action;
my $pod;

GetOptions(
    'h|help'     => \$help,
    't|task=i'   => \$task_id,
    's|status=s' => \$status,
    'a|action=s' => \$action,
    'p|pod=s'    => \$pod,
) or pod2usage(2);

pod2usage(1) if $help;

unless ( $task_id || $status || $action || $pod ) {
    pod2usage(
        {
            -message => "At least one filter option is required (--task, --status, --action, or --pod)",
            -exitval => 1
        }
    );
}

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
my $tasks  = RapidoILL::QueuedTasks->new();

# Build search criteria
my $search = {};
$search->{id}     = $task_id if $task_id;
$search->{status} = $status  if $status;
$search->{action} = $action  if $action;
$search->{pod}    = $pod     if $pod;

my $task_set = $tasks->search($search);
my $count    = $task_set->count;

if ( $count == 0 ) {
    print "No tasks found matching the criteria.\n";
    exit 0;
}

print "Found $count task(s) to reset.\n";
print "Resetting tasks...\n";

my $reset_count = 0;
while ( my $task = $task_set->next ) {
    print "  Task ID " . $task->id . " (action: " . $task->action . ", status: " . $task->status . ")\n";
    $task->reset();
    $reset_count++;
}

print "Successfully reset $reset_count task(s).\n";

=head1 NAME

reset_task.pl - Reset Rapido ILL queued tasks

=head1 SYNOPSIS

reset_task.pl [options]

 Options:
   -h --help          Display this help message
   -t --task=ID       Reset specific task by ID
   -s --status=STATUS Reset all tasks with given status (error, retry, etc.)
   -a --action=ACTION Reset all tasks with given action (o_item_shipped, etc.)
   -p --pod=POD       Reset all tasks for given pod

 Examples:
   # Reset a specific task
   reset_task.pl --task=123

   # Reset all error tasks
   reset_task.pl --status=error

   # Reset all retry tasks for a specific action
   reset_task.pl --status=retry --action=o_item_shipped

   # Reset all tasks for a specific pod
   reset_task.pl --pod=innreach

=head1 DESCRIPTION

This script resets Rapido ILL queued tasks back to 'queued' status,
clearing attempts and errors. This is useful for retrying failed tasks
after fixing underlying issues.

=cut
