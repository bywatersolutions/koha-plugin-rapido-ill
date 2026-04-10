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
use Try::Tiny qw(catch try finally);

use C4::Context;
use Koha::Checkouts;
use Koha::Database;
use Koha::Logger;

use Koha::Script;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;
use RapidoILL::Exceptions;

# Initialize logger with custom category for daemon
my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
my $logger = $plugin->logger('rapidoill_daemon');

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

$logger->info("RapidoILL task queue daemon starting (batch_size: $batch_size, sleep: ${daemon_sleep}s)");

while (1) {
    try {

        run_tasks_batch();

    } catch {
        my $error = $_ || 'Unknown error';
        $logger->error("Task batch execution failed: $error");
        if ($verbose_logging) {
            print STDOUT "Warning : $error\n";
        }
    };

    sleep $daemon_sleep;
}

=head1 IMPLEMENTATION

=head2 run_tasks_batch

    run_tasks_batch();

Processes a batch of runnable tasks from the queue. Tasks are ordered by timestamp
and processed up to the configured batch_size limit.

=cut

sub run_tasks_batch {
    my ($args) = @_;

    # Reuse the global plugin instance to maintain HTTP client cache
    my $tasks = $plugin->get_queued_tasks->filter_by_runnable(
        {
            order_by => { -asc => ['timestamp'] },
            rows     => $batch_size,
        }
    );

    my $task_count = $tasks->count;
    if ( $task_count > 0 ) {
        $logger->info("Processing $task_count queued tasks");
    } else {
        $logger->debug("No tasks to process");
    }

    while ( my $task = $tasks->next ) {
        $logger->debug( "Dispatching task ID " . $task->id . " (action: " . $task->action . ")" );
        my $result = dispatch_task( { plugin => $plugin, task => $task } );

        if ( $result && $result->{backoff} ) {
            delay_all_runnable_tasks( $result->{delay_minutes} );
            last;
        }
    }
}

=head3 dispatch_task

    dispatch_task( { plugin => $plugin, task => $task } );

Dispatches a task to the appropriate handler based on its action type.
Handles success/failure states and retry logic with proper logging.

=cut

sub dispatch_task {
    my ($params) = @_;

    my $plugin = $params->{plugin};
    my $task   = $params->{task};

    my $action_to_method = {

        'o_final_checkin'   => \&o_final_checkin,
        'o_item_shipped'    => \&o_item_shipped,
        'o_cancel_request'  => \&o_cancel_request,
        'b_item_in_transit' => \&b_item_in_transit,
        'b_item_received'   => \&b_item_received,
        'b_item_renewal'    => \&b_item_renewal,
        'DEFAULT'           => \&default_handler,
    };

    my $action =
        exists $action_to_method->{ $task->action }
        ? $task->action
        : 'DEFAULT';

    try {
        $action_to_method->{$action}->( { task => $task, plugin => $plugin } );
        $task->success();
        $logger->info( "Task ID " . $task->id . " completed successfully (action: " . $task->action . ")" );
    } catch {
        my $error = $_ || 'Unknown error';

        # Detect Rapido 5xx errors and trigger global backoff
        my $status_code = ref($error) eq 'RapidoILL::Exception::RequestFailed' ? ( $error->status_code // 0 ) : 0;
        if ( $status_code >= 500 && $status_code < 600 ) {
            $task->retry( { error => "$error" } );

            my $pod_config    = $plugin->configuration->{ $task->pod } // {};
            my $delay_minutes = $pod_config->{task_queue_5xx_delay_minutes} // 20;

            $logger->warn(
                "Rapido returned $status_code on task ID "
                    . $task->id
                    . ", backing off all tasks for ${delay_minutes} minutes"
            );

            return { backoff => 1, delay_minutes => $delay_minutes };
        }

        if ( $task->can_retry ) {
            $task->retry( { error => "$error" } );
            $logger->warn( "Task ID " . $task->id . " failed, will retry: $error" );
        } else {
            $task->error( { error => "$error" } );
            $logger->error( "Task ID " . $task->id . " failed permanently: $error" );
        }
    };
}

=head3 delay_all_runnable_tasks

    delay_all_runnable_tasks($delay_minutes);

Sets C<run_after> on all currently runnable tasks to delay them by the
given number of minutes. Used when Rapido returns a 5xx error to avoid
hammering the server while it recovers.

=cut

sub delay_all_runnable_tasks {
    my ($delay_minutes) = @_;

    my $delay_seconds = $delay_minutes * 60;

    $plugin->get_queued_tasks->filter_by_runnable->update(
        { run_after => \"DATE_ADD(NOW(), INTERVAL $delay_seconds SECOND)" } );
}

=head3 default_handler

Throws an exception.

=cut

sub default_handler {
    my ($params) = @_;
    RapidoILL::Exception::UnhandledException->throw(
        sprintf(
            "No handler implemented for action [%s]",
            $params->{task}->{action}
        )
    );
}

=head3 o_final_checkin

    o_final_checkin( { plugin => $plugin, task => $task } );

Handle the o_final_checkin action.

=cut

sub o_final_checkin {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    $params->{plugin}->get_lender_actions($pod)->final_checkin($req);
}

=head3 o_item_shipped

    o_item_shipped( { plugin => $plugin, task => $task } );

Handle the o_item_shipped action. Executes within the stored user context
from the task to maintain proper permissions and environment.

=cut

sub o_item_shipped {
    my ($params) = @_;

    my $task = $params->{task};
    my $req  = $task->ill_request;
    my $pod  = $params->{plugin}->get_req_pod($req);

    # Execute with stored userenv from payload
    $task->execute_with_context(
        sub {
            $params->{plugin}->get_lender_actions($pod)->item_shipped($req);
        }
    );
}

=head3 o_cancel_request

    o_cancel_request( { plugin => $plugin, task => $task } );

Handle the o_cancel_request action.

=cut

sub o_cancel_request {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    $params->{plugin}->get_lender_actions($pod)->cancel_request($req);
}

=head3 b_item_in_transit

    b_item_in_transit( { plugin => $plugin, task => $task } );

Handle the b_item_in_transit action.

=cut

sub b_item_in_transit {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    $params->{plugin}->get_borrower_actions($pod)->item_in_transit($req);
}

=head3 b_item_received

    b_item_received( { plugin => $plugin, task => $task } );

Handle the b_item_received action.

=cut

sub b_item_received {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    $params->{plugin}->get_borrower_actions($pod)->item_received($req);
}

=head3 b_item_renewal

    b_item_renewal( { plugin => $plugin, task => $task } );

Handle the b_item_renewal action.

=cut

sub b_item_renewal {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    my $payload = $params->{task}->decoded_payload();

    $plugin->get_borrower_actions($pod)->borrower_renew(
        $req,
        { due_date => $payload->{due_date} }
    );
}

=head1 NAME

task_queue_daemon.pl

=head1 SYNOPSIS

task_queue_daemon.pl -s 5

 Options:
   -?|--help        brief help message
   -v               Be verbose
   --sleep N        Polling frequency
   --batch_size N   Process tasks in batches of N

=head1 OPTIONS

=over 8

=item B<--help|-?>

Print a brief help message and exits

=item B<-v>

Be verbose

=item B<--sleep N>

Use I<N> as the database polling frequency.

=item B<--batch_size N>

Process tasks in batches of I<N>.

=back

=head1 DESCRIPTION

A task queue processor daemon that takes care of notifying Rapido ILL about
relevant circulation events. The daemon processes tasks in batches, maintaining
proper user context and permissions for each operation. Tasks are automatically
retried on failure with exponential backoff.

=head1 FUNCTIONS

=head2 Task Processing

=cut
