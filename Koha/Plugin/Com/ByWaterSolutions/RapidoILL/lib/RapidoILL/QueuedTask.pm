package RapidoILL::QueuedTask;

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

# Suppress redefinition warnings when plugin is reloaded
no warnings 'redefine';

use JSON qw(encode_json);
use Koha::ILL::Requests;

use base qw(Koha::Object);

=head1 NAME

RapidoILL::QueuedTask - Task queue row Object class

=head1 API

=head2 Class methods

=head3 ill_request

    my $req = $task->ill_request;

Accessor for the linked I<Koha::ILL::Request> object.

=cut

sub ill_request {
    my ($self) = @_;

    return Koha::ILL::Requests->find( $self->illrequest_id );
}

=head3 can_retry

    if ( $task->can_retry( [ $max_retries ] ) ) { ... }

Returns I<true> if the task can be retried. Useful for final error recording.
If I<$max_retries> is passed, it is used. Otherwise it defaults to 10.

=cut

sub can_retry {
    my ( $self, $max_retries ) = @_;

    $max_retries //= 10;

    return ( $self->attempts <= $max_retries ) ? 1 : 0;
}

=head3 error

    $task->error($error);

Marks the task as failed. Expects a hashref as I<$error> or nothing.

=cut

sub error {
    my ( $self, $error ) = @_;

    $self->set(
        {
            status => 'error',
            ( $error ? ( last_error => encode_json($error) ) : () ),
        }
    )->store();

    return $self;
}

=head3 retry

    $task->retry( { [ delay => $delay_secs ] } );

Marks the task for retry. If I<delay> is not passed it defaults to B<120> seconds.

=cut

sub retry {
    my ( $self, $params ) = @_;

    my $retry_delay = $params->{delay} // 120;
    my $error       = $params->{error};

    $self->set(
        {
            status   => 'retry',
            attempts => $self->attempts + 1,
            ( $error ? ( last_error => encode_json( { error => $error } ) ) : () ),
            run_after => \"DATE_ADD(NOW(), INTERVAL $retry_delay SECOND)"
        }
    )->store();

    return $self;
}

=head3 success

    $task->success();

Marks the task as successful.

=cut

sub success {
    my ($self) = @_;

    $self->set( { status => 'success', } )->store();

    return $self;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillTaskQueue';
}

1;
