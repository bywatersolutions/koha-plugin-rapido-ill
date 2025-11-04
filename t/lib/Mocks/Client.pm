package t::lib::Mocks::Client;

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

use base 'Test::Builder::Module';
use base qw(Class::Accessor);

use Test::MockModule;
use Test::MockObject;
use HTTP::Response;
use JSON qw(encode_json);

my $CLASS = __PACKAGE__;

=head1 NAME

t::lib::Mocks::Client - A library to mock HTTP client for testing

=head1 API

=head2 Methods

=head3 new

    my $client_mock = t::lib::Mocks::Client->new($plugin);

Mocks HTTP client for testing purposes. Captures request parameters
and provides methods to test them.

=cut

sub new {
    my ( $class, $plugin ) = @_;

    my $self = $class->SUPER::new(
        {
            requests         => [],
            response_code    => 200,
            response_message => 'OK',
            response_body    => { success => 1 },
        }
    );
    bless $self, $class;

    if ($plugin) {
        $self->_mock_plugin($plugin);
    }

    return $self;
}

=head3 _mock_plugin

Internal method to mock the plugin's get_http_client method.

=cut

sub _mock_plugin {
    my ( $self, $plugin ) = @_;

    my $mock_http_client = Test::MockObject->new();

    foreach my $method (qw(get_request post_request put_request delete_request)) {
        $mock_http_client->mock(
            $method,
            sub {
                my ( $client, $params ) = @_;

                # Capture request details
                push @{ $self->{requests} }, {
                    method   => $method,
                    endpoint => $params->{endpoint},
                    data     => $params->{data},
                    context  => $params->{context},
                };

                # Return mock response
                my $response = HTTP::Response->new(
                    $self->{response_code},
                    $self->{response_message}
                );
                $response->content( encode_json( $self->{response_body} ) );
                $response->header( 'Content-Type', 'application/json' );
                return $response;
            }
        );
    }

    my $plugin_mock = Test::MockModule->new( ref $plugin );
    $plugin_mock->mock( 'get_http_client', sub { return $mock_http_client; } );

    $self->{plugin_mock} = $plugin_mock;
    return $self;
}

=head3 set_response

    $client_mock->set_response(200, 'OK', { result => 'success' });

Sets the response that will be returned by HTTP requests.

=cut

sub set_response {
    my ( $self, $code, $message, $body ) = @_;

    $self->{response_code}    = $code;
    $self->{response_message} = $message;
    $self->{response_body}    = $body;

    return $self;
}

=head3 endpoint_is

    $client_mock->endpoint_is('/view/broker/circ/123/lendercancel', 'Correct endpoint');

Tests that the last request used the expected endpoint.

=cut

sub endpoint_is {
    my ( $self, $expected, $name ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $last_request = $self->_last_request();
    my $endpoint     = $last_request ? $last_request->{endpoint} : undef;

    my $tb = $CLASS->builder;
    return $tb->is_eq( $endpoint, $expected, $name );
}

=head3 data_is

    $client_mock->data_is({ param => 'value' }, 'Correct data sent');

Tests that the last request sent the expected data.

=cut

sub data_is {
    my ( $self, $expected, $name ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $last_request = $self->_last_request();
    my $data         = $last_request ? $last_request->{data} : undef;

    my $tb = $CLASS->builder;
    return $tb->is_eq( $data, $expected, $name ) if !ref($expected);

    # For complex data structures, use Test::More::is_deeply
    require Test::More;
    return Test::More::is_deeply( $data, $expected, $name );
}

=head3 data_type_is

    $client_mock->data_type_is('localBibId', 'string', 'localBibId sent as string');

Tests that a specific field in the last request data has the expected type.

=cut

sub data_type_is {
    my ( $self, $field, $expected_type, $name ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $last_request = $self->_last_request();
    my $data         = $last_request ? $last_request->{data} : undef;
    my $value        = $data         ? $data->{$field}       : undef;

    my $actual_type;
    if ( !defined $value ) {
        $actual_type = 'undef';
    } elsif ( ref $value ) {
        $actual_type = ref $value;
    } else {

        # Use JSON encoding to detect type - strings get quotes, numbers don't
        require JSON;
        my $json_encoded = JSON::encode_json( [$value] );
        if ( $json_encoded =~ /^\[".*"\]$/ ) {
            $actual_type = 'string';
        } else {
            $actual_type = 'integer';
        }
    }

    my $tb = $CLASS->builder;
    return $tb->is_eq( $actual_type, $expected_type, $name );
}

=head3 context_is

    $client_mock->context_is('lender_cancel', 'Correct context');

Tests that the last request used the expected context.

=cut

sub context_is {
    my ( $self, $expected, $name ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $last_request = $self->_last_request();
    my $context      = $last_request ? $last_request->{context} : undef;

    my $tb = $CLASS->builder;
    return $tb->is_eq( $context, $expected, $name );
}

=head3 method_is

    $client_mock->method_is('post_request', 'Used POST method');

Tests that the last request used the expected HTTP method.

=cut

sub method_is {
    my ( $self, $expected, $name ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $last_request = $self->_last_request();
    my $method       = $last_request ? $last_request->{method} : undef;

    my $tb = $CLASS->builder;
    return $tb->is_eq( $method, $expected, $name );
}

=head3 request_count

    is( $client_mock->request_count(), 1, 'One request made' );

Returns the number of requests captured.

=cut

sub request_count {
    my ($self) = @_;
    return scalar @{ $self->{requests} };
}

=head3 clear

    $client_mock->clear();

Clears all captured requests.

=cut

sub clear {
    my ($self) = @_;
    $self->{requests} = [];
    return $self;
}

=head3 diag

    $client_mock->diag();

Outputs all captured requests for debugging.

=cut

sub diag {
    my ($self) = @_;
    my $tb = $CLASS->builder;

    $tb->diag("Captured requests:");
    if ( @{ $self->{requests} } ) {
        for my $i ( 0 .. $#{ $self->{requests} } ) {
            my $req = $self->{requests}->[$i];
            $tb->diag("  [$i] $req->{method} $req->{endpoint} (context: $req->{context})");
        }
    } else {
        $tb->diag("  (No requests captured)");
    }
    return;
}

=head2 Internal methods

=head3 _last_request

Returns the last captured request.

=cut

sub _last_request {
    my ($self) = @_;
    return @{ $self->{requests} } ? $self->{requests}->[-1] : undef;
}

1;
