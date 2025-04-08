#!/usr/bin/env perl

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

use Getopt::Long;
use Pod::Usage;
use Try::Tiny qw(catch try);

use Koha::Script;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

my $daemon_sleep = 1;
my $verbose_logging;
my $help;
my $batch_size;

my $result = GetOptions(
    'batch_size=i' => \$batch_size,
    'help|?'       => \$help,
    'v'            => \$verbose_logging,
    'sleep=s'      => \$daemon_sleep,
);

if ( not $result or $help ) {
    pod2usage(1);
}

$batch_size //= 100;

while (1) {
    try {

        run_tasks_batch();

    } catch {
        if ( $@ && $verbose_logging ) {
            print STDOUT "Warning : $@\n";
        }
    };

    sleep $daemon_sleep;
}

=head3 run_tasks_batch

=cut

sub run_tasks_batch {
    my ($args) = @_;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    my $tasks  = $plugin->get_queued_tasks->filter_by_runnable(
        {
            order_by => { -asc => ['timestamp'] },
            rows     => $batch_size,
        }
    );

    while ( my $task = $tasks->next ) {
        dispatch_task( { plugin => $plugin, task => $task } );
    }
}

=head3 dispacth_task

=cut

sub dispatch_task {
    my ($task) = @_;

}

=head1 NAME

task_queue_daemon.pl

=head1 SYNOPSIS

task_queue_daemon.pl -s 5

 Options:
   -?|--help        brief help message
   -v               Be verbose
   --sleep N        Polling frecquency
   --batch_size N   Process tasks in batches of N

=head1 OPTIONS

=over 8

=item B<--help|-?>

Print a brief help message and exits

=item B<-v>

Be verbose

=item B<--sleep N>

Use I<N> as the database polling frecquency.

=item B<--batch_size N>

Process tasks in batches of I<N>.

=back

=head1 DESCRIPTION

A task queue processor daemon that takes care of notifying Rapido ILL about
relevant circulation events.

=cut
