package RapidoILL::APIHttpClient;

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

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw( ua access_token dev_mode plugin ));

use DateTime;
use HTTP::Request::Common qw(DELETE GET POST PUT);
use JSON                  qw(decode_json encode_json);
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64url encode_base64url );
use URI          ();

use RapidoILL::Exceptions;

=head1 RapidoILL::APIHttpClient

An OAuth2-enabled HTTP client for the Rapido ILL API.

This class provides authenticated HTTP communication with Rapido ILL central servers.
It handles OAuth2 token management (acquisition, refresh, expiration checking) and 
HTTP request execution with proper authentication headers.

=head2 Class methods

=head3 new

    my $client = RapidoILL::APIHttpClient->new(
        {
            client_id      => 'a_client_id',
            client_secret  => 'a_client_secret',
            base_url       => 'https://api.base.url',
          [ debug_requests => 1|0 ]
        }
    );

Constructor for the authenticated HTTP client.

=cut

sub new {
    my ( $class, $args ) = @_;

    my @mandatory_params = qw(base_url client_id client_secret );
    foreach my $param (@mandatory_params) {
        RapidoILL::Exception::MissingParameter->throw("Missing parameter: $param")
            unless $args->{$param};
    }

    my $base_url = $args->{base_url};

    my $client_id     = $args->{client_id};
    my $client_secret = $args->{client_secret};
    my $credentials   = encode_base64url("$client_id:$client_secret");

    my $self = $class->SUPER::new($args);
    $self->{base_url}       = $base_url;
    $self->{token_endpoint} = $self->{base_url} . "/view/broker/auth";
    $self->{ua}             = LWP::UserAgent->new();
    $self->{scope}          = "innreach_tp";
    $self->{grant_type}     = 'client_credentials';
    $self->{credentials}    = $credentials;
    $self->{request}        = POST(
        $self->{token_endpoint},
        Authorization => "Basic $credentials",
        Accept        => "application/json",

        ContentType => "application/x-www-form-urlencoded",
        Content     => [
            grant_type => 'client_credentials',
            scope      => $self->{scope},
            undefined  => undef,
        ]
    );
    $self->{debug_mode} = ( $args->{debug_requests} ) ? 1 : 0;

    bless $self, $class;

    # Get the first token we will use
    $self->refresh_token
        unless $self->dev_mode;

    return $self;
}

=head3 logger

Access to the plugin's logger instance

=cut

sub logger {
    my ($self) = @_;

    return $self->plugin ? $self->plugin->logger : undef;
}

=head3 post_request

Generic request for POST

=cut

sub post_request {
    my ( $self, $args ) = @_;

    my $endpoint = $self->{base_url} . $args->{endpoint};

    my $request = POST(
        $endpoint,
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => ( exists $args->{data} )
        ? encode_json( $args->{data} )
        : undef
    );

    if ( $self->logger ) {
        $self->logger->info( "Making POST request to " . $endpoint );

        if ( $self->{debug_mode} ) {
            $self->logger->debug( "POST request to " . $endpoint );
            $self->logger->debug( "Request data: " . encode_json( $args->{data} ) ) if exists $args->{data};
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        if ( $response->is_success ) {
            $self->logger->info( "POST request successful: " . $response->code . " " . $response->message );
        } else {
            $self->logger->error(
                "POST request failed: " . $response->code . " " . $response->message . " to " . $endpoint );
        }
    }

    return $response;
}

=head3 put_request

Generic request for PUT

=cut

sub put_request {
    my ( $self, $args ) = @_;

    my $endpoint = $self->{base_url} . $args->{endpoint};

    my $request = PUT(
        $endpoint,
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => encode_json( $args->{data} )
    );

    if ( $self->logger ) {
        $self->logger->info( "Making PUT request to " . $endpoint );

        if ( $self->{debug_mode} ) {
            $self->logger->debug( "PUT request to " . $endpoint );
            $self->logger->debug( "Request data: " . encode_json( $args->{data} ) );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        if ( $response->is_success ) {
            $self->logger->info( "PUT request successful: " . $response->code . " " . $response->message );
        } else {
            $self->logger->error(
                "PUT request failed: " . $response->code . " " . $response->message . " to " . $endpoint );
        }
    }

    return $response;
}

=head3 get_request

    my $response = $client->get_request(
        {
            endpoint => "/some/endpoint",
          [ query    => {
                param_1 => "123",
                ...
                param_2 => [ "ASD", "QWE" ],
            } ]  
        }
    );

Generic request for GET.

The I<endpoint> parameter is mandatory. I<query> should
be a hashref where keys are the query parameters pointing to desired values.
If the value is an arrayref, then the query parameter will get repeated
for each of the contained values.

In the example above, the generated query will be
B<https://www.bywatersolutions.com/some/endpoint?param_1="123"&param_2="ASD"&param_2="QWE">

=cut

sub get_request {
    my ( $self, $args ) = @_;

    my $uri = URI->new( $self->{base_url} . ( $args->{endpoint} // "" ) );
    if ( $args->{query} ) {
        $uri->query_form( %{ $args->{query} } );
    }

    my $request = GET(
        $uri,
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json"
    );

    if ( $self->logger ) {
        $self->logger->info( "Making GET request to " . $uri->as_string );

        if ( $self->{debug_mode} ) {
            $self->logger->debug( "GET request to " . $uri->as_string );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        if ( $response->is_success ) {
            $self->logger->info( "GET request successful: " . $response->code . " " . $response->message );
        } else {
            $self->logger->error(
                "GET request failed: " . $response->code . " " . $response->message . " to " . $uri->as_string );
        }
    }

    return $response;
}

=head3 delete_request

Generic request for DELETE

=cut

sub delete_request {
    my ( $self, $args ) = @_;

    my $endpoint = $self->{base_url} . $args->{endpoint};

    my $request = DELETE(
        $endpoint,
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
    );

    if ( $self->logger ) {
        $self->logger->info( "Making DELETE request to " . $endpoint );

        if ( $self->{debug_mode} ) {
            $self->logger->debug( "DELETE request to " . $endpoint );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        if ( $response->is_success ) {
            $self->logger->info( "DELETE request successful: " . $response->code . " " . $response->message );
        } else {
            $self->logger->error(
                "DELETE request failed: " . $response->code . " " . $response->message . " to " . $endpoint );
        }
    }

    return $response;
}

=head2 Internal methods


=head3 get_token

    my $token = $oauth->get_token;

This method takes care of fetching an access token from INN-Reach.
It is cached, along with the calculated expiration date. I<refresh_token>
is I<is_token_expired> returns true.

In general, this method shouldn't be used when using this library. The
I<request_*> methods should be used directly, and they would request the
access token as needed.

=cut

sub get_token {
    my ($self) = @_;

    unless ( $self->dev_mode ) {
        if ( $self->is_token_expired ) {
            if ( $self->logger ) {
                $self->logger->info("OAuth2 token expired, refreshing...");
            }
            $self->refresh_token;
        }
    }

    return $self->{access_token};
}

=head3 refresh_token

    $oauth->refresh_token;

Method that takes care of retrieving a new token. This method is
B<not intended> to be used on its own. I<get_token> should be used
instead.

=cut

sub refresh_token {
    my ($self) = @_;

    if ( $self->logger ) {
        $self->logger->info( "Refreshing OAuth2 token for " . $self->{base_url} );
    }

    my $ua      = $self->{ua};
    my $request = $self->{request};

    my $response         = $ua->request($request);
    my $response_content = decode_json( $response->decoded_content );

    unless ( $response->code eq '200' ) {
        my $error_msg = "OAuth2 authentication failed: " . $response_content->{error_description};
        if ( $self->logger ) {
            $self->logger->error( $error_msg . " (HTTP " . $response->code . ")" );
        }
        RapidoILL::Exception::OAuth2::AuthError->throw(
            "Authentication error: " . $response_content->{error_description} );
    }

    $self->{access_token} = $response_content->{access_token};
    $self->{expiration} =
        DateTime->now()->add( seconds => $response_content->{expires_in} );

    if ( $self->logger ) {
        $self->logger->info(
            "OAuth2 token refreshed successfully, expires in " . $response_content->{expires_in} . " seconds" );
    }

    return $self;
}

=head3 is_token_expired

    if ( $oauth->is_token_expired ) { ... }

This helper method tests if the current token is expired.

=cut

sub is_token_expired {
    my ($self) = @_;

    return !defined $self->{expiration} || $self->{expiration} < DateTime->now();
}

1;
