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

    my $task_count = $tasks->count;
    if ( $task_count > 0 ) {
        $logger->info("Processing $task_count queued tasks");
    } else {
        $logger->debug("No tasks to process");
    }

    while ( my $task = $tasks->next ) {
        $logger->debug( "Dispatching task ID " . $task->id . " (action: " . $task->action . ")" );
        dispatch_task( { plugin => $plugin, task => $task } );
    }
}

=head3 dispacth_task

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
        'renewal'           => \&renewal,
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
        if ( $task->can_retry ) {
            $task->retry( { error => "$error" } );
            $logger->warn( "Task ID " . $task->id . " failed, will retry: $error" );
        } else {
            $task->error( { error => "$error" } );
            $logger->error( "Task ID " . $task->id . " failed permanently: $error" );
        }
    };
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

Handle the o_item_shipped action.

=cut

sub o_item_shipped {
    my ($params) = @_;

    my $req = $params->{task}->ill_request;
    my $pod = $params->{plugin}->get_req_pod($req);

    $params->{plugin}->get_lender_actions($pod)->item_shipped($req);
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

    my $task   = $params->{task};
    my $plugin = $params->{plugin};

    Koha::Database->schema->storage->txn_do(
        sub {

            my $req = $task->ill_request();

            $req->status('B_ITEM_RECEIVED')->store;

            # notify Rapido. Throws an exception if failed
            $plugin->get_client( $plugin->get_req_pod($req) )->borrower_item_received(
                {
                    circId => $plugin->get_req_circ_id($req),
                }
            );
        }
    );
}

=head3 renewal

    renewal( { plugin => $plugin, task => $task } );

Handle the renewal action.

=cut

sub renewal {
    my ($params) = @_;

    my $task     = $params->{task};
    my $plugin   = $params->{plugin};
    my $checkout = Koha::Checkouts->find( $task->object_id );

    RapidoILL::Exception->throw( sprintf( "Invalid checkout_id passed [%s]", $task->object_id ) )
        unless $checkout;

    # notify renewal to pod
    my $circId = $plugin->get_req_circ_id( $task->ill_request );
    $plugin->get_client( $task->pod )->borrower_renew( { circId => $circId, dueDateTime => $checkout->date_due } );
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
