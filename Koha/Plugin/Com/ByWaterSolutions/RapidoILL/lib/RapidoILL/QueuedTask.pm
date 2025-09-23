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

use JSON qw(encode_json decode_json);
use Try::Tiny;
use C4::Context;
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

=head3 decoded_payload

    my $data = $task->decoded_payload;

Returns the JSON-decoded content of the payload attribute.

=cut

sub decoded_payload {
    my ($self) = @_;

    return decode_json( $self->payload );
}

=head3 decoded_context

    my $context = $task->decoded_context;

Returns the context column as a Perl data structure.

=cut

sub decoded_context {
    my ($self) = @_;

    my $context = $self->context;
    return unless defined $context && $context ne '';

    my $decoded_context;
    try {
        $decoded_context = decode_json($context);
    } catch {
        warn "Failed to decode context JSON: $_";
        return;
    };

    return $decoded_context;
}

=head3 store

    $task->store();

Overloaded store method that automatically JSON-encodes the payload and context attributes
if they contain references (hash, array, etc.) before storing to database.

=cut

sub store {
    my ($self) = @_;

    # If payload is set and is a reference, JSON-encode it
    if ( defined $self->payload && ref( $self->payload ) ) {
        $self->set( { payload => encode_json( $self->payload ) } );
    }

    # If context is set and is a reference, JSON-encode it
    if ( defined $self->context && ref( $self->context ) ) {
        $self->set( { context => encode_json( $self->context ) } );
    }

    return $self->SUPER::store();
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
            (
                $error
                ? ( last_error => encode_json( ref($error) ? $error : { error => $error } ) )
                : ()
            ),
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

=head3 execute_with_context

    $task->execute_with_context($code_ref);

Executes the provided code reference with the context stored in the task's context column.
Restores the original userenv and interface state afterwards.

=cut

sub execute_with_context {
    my ( $self, $code_ref ) = @_;

    my $stored_context = $self->decoded_context;

    return $code_ref->() unless $stored_context;

    my $original_userenv   = C4::Context->userenv;
    my $original_interface = C4::Context->interface;

    try {
        # Set interface if stored
        if ( $stored_context->{interface} ) {
            C4::Context->interface( $stored_context->{interface} );
        }

        # Set userenv from stored data
        my $stored_userenv = $stored_context->{userenv};
        if ($stored_userenv) {
            if ( ref($stored_userenv) eq 'HASH' ) {

                # Handle hash format (from t::lib::Mocks::mock_userenv)
                C4::Context->set_userenv(
                    $stored_userenv->{number}        || 0,
                    $stored_userenv->{id}            || 'rapidoill_daemon',
                    $stored_userenv->{cardnumber}    || '',
                    $stored_userenv->{firstname}     || 'RapidoILL',
                    $stored_userenv->{surname}       || 'Daemon',
                    $stored_userenv->{branch}        || $stored_userenv->{branchcode} || '',
                    $stored_userenv->{branchname}    || '',
                    $stored_userenv->{flags}         || 0,
                    $stored_userenv->{emailaddress}  || '',
                    $stored_userenv->{shibboleth}    || '',
                    $stored_userenv->{desk_id}       || '',
                    $stored_userenv->{desk_name}     || '',
                    $stored_userenv->{register_id}   || '',
                    $stored_userenv->{register_name} || ''
                );
            } elsif ( ref($stored_userenv) eq 'ARRAY' ) {

                # Handle array format (from C4::Context->userenv direct storage)
                C4::Context->set_userenv(@$stored_userenv);
            }
        }

        return $code_ref->();
    } catch {
        die $_;
    } finally {

        # Restore original interface
        if ( defined $original_interface ) {
            C4::Context->interface($original_interface);
        }

        # Restore original userenv state
        if ($original_userenv) {
            C4::Context->set_userenv(
                $original_userenv->{number},
                $original_userenv->{id},
                $original_userenv->{cardnumber},
                $original_userenv->{firstname},
                $original_userenv->{surname},
                $original_userenv->{branch},
                $original_userenv->{branchname},
                $original_userenv->{flags},
                $original_userenv->{emailaddress},
                $original_userenv->{shibboleth},
                $original_userenv->{desk_id},
                $original_userenv->{desk_name},
                $original_userenv->{register_id},
                $original_userenv->{register_name}
            );
        } else {
            C4::Context->unset_userenv();
        }
    };
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillTaskQueue';
}

1;
