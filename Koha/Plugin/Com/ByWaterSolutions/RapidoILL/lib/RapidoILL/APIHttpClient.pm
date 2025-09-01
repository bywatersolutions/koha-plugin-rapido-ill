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
use Koha::Logger;
use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64url encode_base64url );
use Try::Tiny    qw( catch try );
use URI          ();

use RapidoILL::Exceptions;

=head1 RapidoILL::APIHttpClient

An OAuth2-enabled HTTP client for the Rapido ILL API.

This class provides authenticated HTTP communication with Rapido ILL central servers.
It handles OAuth2 token management (acquisition, refresh, expiration checking) and 
HTTP request execution with proper authentication headers.

OAuth2 tokens are refreshed on-demand (deferred) - the first request will trigger
token acquisition, and subsequent requests will refresh tokens only when expired.

=head2 Class methods

=head3 new

    my $client = RapidoILL::APIHttpClient->new(
        {
            client_id      => 'a_client_id',
            client_secret  => 'a_client_secret',
            base_url       => 'https://api.base.url',
        }
    );

Constructor for the authenticated HTTP client.

=cut

sub new {
    my ( $class, $args ) = @_;

    my @mandatory_params = qw(base_url client_id client_secret plugin pod);
    foreach my $param (@mandatory_params) {
        RapidoILL::Exception::MissingParameter->throw( param => $param )
            unless $args->{$param};
    }

    my $base_url = $args->{base_url};

    my $client_id     = $args->{client_id};
    my $client_secret = $args->{client_secret};
    my $credentials   = encode_base64url("$client_id:$client_secret");

    my $self = $class->SUPER::new($args);
    $self->{base_url}       = $base_url;
    $self->{pod}            = $args->{pod};
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

    bless $self, $class;

    return $self;
}

=head3 logger

Access to the API-specific logger instance

=cut

sub logger {
    my ($self) = @_;

    # Use API-specific logger category through the plugin
    return $self->plugin ? $self->plugin->logger('rapidoill_api') : undef;
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

        if ( $self->logger->is_debug ) {
            $self->logger->debug( "POST request to " . $endpoint );
            $self->logger->debug( "Request data: " . encode_json( $args->{data} ) ) if exists $args->{data};
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        my $context_info = $args->{context} ? " [context: " . $args->{context} . "]" : "";

        if ( $response->is_success ) {
            my $status_message = $response->message || 'Success';
            $self->logger->info(
                "POST request successful: " . $response->code . " " . $status_message . $context_info );
        } else {

            # In debug mode, log detailed HTTP error information
            if ( $self->logger->is_debug ) {
                my $status_message = $response->message || 'Unknown';
                $self->logger->error( "POST request failed: "
                        . $response->code . " "
                        . $status_message . " to "
                        . $endpoint
                        . $context_info );

                # Log the full response content for troubleshooting
                my $content = $response->decoded_content || $response->content || 'No content';
                $self->logger->debug( "POST request failed response body" . $context_info . ": " . $content );

                # Also log request headers if available for debugging
                if ( $response->request ) {
                    $self->logger->debug(
                        "POST request headers" . $context_info . ": " . $response->request->headers->as_string );
                }
            } else {

                # Brief error log for production
                $self->logger->error( "POST request failed" . $context_info );
            }
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

        if ( $self->logger->is_debug ) {
            $self->logger->debug( "PUT request to " . $endpoint );
            $self->logger->debug( "Request data: " . encode_json( $args->{data} ) );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        my $context_info = $args->{context} ? " [context: " . $args->{context} . "]" : "";

        if ( $response->is_success ) {
            my $status_message = $response->message || 'Success';
            $self->logger->info( "PUT request successful: " . $response->code . " " . $status_message . $context_info );
        } else {

            # In debug mode, log detailed HTTP error information
            if ( $self->logger->is_debug ) {
                my $status_message = $response->message || 'Unknown';
                $self->logger->error( "PUT request failed: "
                        . $response->code . " "
                        . $status_message . " to "
                        . $endpoint
                        . $context_info );

                # Log the full response content for troubleshooting
                my $content = $response->decoded_content || $response->content || 'No content';
                $self->logger->debug( "PUT request failed response body" . $context_info . ": " . $content );

                # Also log request headers if available for debugging
                if ( $response->request ) {
                    $self->logger->debug(
                        "PUT request headers" . $context_info . ": " . $response->request->headers->as_string );
                }
            } else {

                # Brief error log for production
                $self->logger->error( "PUT request failed" . $context_info );
            }

            # In debug mode, log the full response content for troubleshooting
            if ( $self->logger->can('debug') ) {
                my $content = $response->decoded_content || $response->content || 'No content';
                $self->logger->debug( "PUT request failed response body" . $context_info . ": " . $content );

                # Also log request headers if available for debugging
                if ( $response->request ) {
                    $self->logger->debug(
                        "PUT request headers" . $context_info . ": " . $response->request->headers->as_string );
                }
            }
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

        if ( $self->logger->is_debug ) {
            $self->logger->debug( "GET request to " . $uri->as_string );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        my $context_info = $args->{context} ? " [context: " . $args->{context} . "]" : "";

        if ( $response->is_success ) {
            my $status_message = $response->message || 'Success';
            $self->logger->info( "GET request successful: " . $response->code . " " . $status_message . $context_info );
        } else {

            # In debug mode, log detailed HTTP error information
            if ( $self->logger->is_debug ) {
                my $status_message = $response->message || 'Unknown';
                $self->logger->error( "GET request failed: "
                        . $response->code . " "
                        . $status_message . " to "
                        . $uri->as_string
                        . $context_info );

                # Log the full response content for troubleshooting
                my $content = $response->decoded_content || $response->content || 'No content';
                $self->logger->debug( "GET request failed response body" . $context_info . ": " . $content );

                # Also log request headers if available for debugging
                if ( $response->request ) {
                    $self->logger->debug(
                        "GET request headers" . $context_info . ": " . $response->request->headers->as_string );
                }
            } else {

                # Brief error log for production
                $self->logger->error( "GET request failed" . $context_info );
            }
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

        if ( $self->logger->is_debug ) {
            $self->logger->debug( "DELETE request to " . $endpoint );
        }
    }

    my $response = $self->ua->request($request);

    if ( $self->logger ) {
        my $context_info = $args->{context} ? " [context: " . $args->{context} . "]" : "";

        if ( $response->is_success ) {
            my $status_message = $response->message || 'Success';
            $self->logger->info(
                "DELETE request successful: " . $response->code . " " . $status_message . $context_info );
        } else {

            # In debug mode, log detailed HTTP error information
            if ( $self->logger->is_debug ) {
                my $status_message = $response->message || 'Unknown';
                $self->logger->error( "DELETE request failed: "
                        . $response->code . " "
                        . $status_message . " to "
                        . $endpoint
                        . $context_info );

                # Log the full response content for troubleshooting
                my $content = $response->decoded_content || $response->content || 'No content';
                $self->logger->debug( "DELETE request failed response body" . $context_info . ": " . $content );

                # Also log request headers if available for debugging
                if ( $response->request ) {
                    $self->logger->debug(
                        "DELETE request headers" . $context_info . ": " . $response->request->headers->as_string );
                }
            } else {

                # Brief error log for production
                $self->logger->error( "DELETE request failed" . $context_info );
            }
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

        # Only load from database if we don't have a token in memory yet
        if ( !$self->{access_token} && !$self->{_token_loaded_from_db} ) {
            $self->_load_token_from_database();
            $self->{_token_loaded_from_db} = 1;
        }

        # If no token exists yet, or if token is expired, refresh it
        if ( !$self->{access_token} || $self->is_token_expired ) {
            if ( $self->logger ) {
                my $reason = !$self->{access_token} ? "No token available" : "OAuth2 token expired";
                $self->logger->info("$reason, refreshing...");
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

    # Save token to database for persistence across script runs
    $self->_save_token_to_database();

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

=head3 _load_token_from_database

    $self->_load_token_from_database();

Load cached OAuth2 token from plugin database storage.
Uses pod-specific key to support multiple pods with separate token caches.

=cut

sub _load_token_from_database {
    my ($self) = @_;

    return unless $self->{plugin};

    my $token_key  = "access_token_" . $self->{pod};
    my $token_data = $self->{plugin}->retrieve_data($token_key);

    if ( $token_data && ref($token_data) eq 'HASH' ) {
        $self->{access_token} = $token_data->{access_token};
        if ( $token_data->{expiration_epoch} ) {
            try {
                $self->{expiration} = DateTime->from_epoch( epoch => $token_data->{expiration_epoch} );
            } catch {
                delete $self->{access_token};
                delete $self->{expiration};
            };
        }
    }
}

=head3 _save_token_to_database

    $self->_save_token_to_database();

Save OAuth2 token to plugin database storage for persistence across script runs.
Uses pod-specific key that automatically overwrites old tokens for the same pod.

=cut

sub _save_token_to_database {
    my ($self) = @_;

    return unless $self->{plugin} && $self->{access_token};

    my $token_key  = "access_token_" . $self->{pod};
    my $token_data = {
        access_token     => $self->{access_token},
        expiration_epoch => $self->{expiration} ? $self->{expiration}->epoch() : undef,
        cached_at_epoch  => DateTime->now()->epoch(),
    };

    $self->{plugin}->store_data( { $token_key => $token_data } );
}

1;
