package RapidoILL::OAuth2;

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

__PACKAGE__->mk_accessors(qw( ua access_token dev_mode ));

use DateTime;
use DDP;
use HTTP::Request::Common qw(DELETE GET POST PUT);
use JSON                  qw(decode_json encode_json);
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64url encode_base64url );
use URI          ();

use RapidoILL::Exceptions;

=head1 RapidoILL::OAuth2

A class implementing the a user agent for connecting to Rapido ILL central servers.

=head2 Class methods

=head3 new

    my $ua = RapidoILL::OAuth2->new(
        {
            client_id      => 'a_client_id',
            client_secret  => 'a_client_secret',
            base_url       => 'https://api.base.url',
          [ debug_requests => 1|0 ]
        }
    );

Constructor for the user agent class.

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

=head3 post_request

Generic request for POST

=cut

sub post_request {
    my ( $self, $args ) = @_;

    my $request = POST(
        $self->{base_url} . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => ( exists $args->{data} )
        ? encode_json( $args->{data} )
        : undef
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 put_request

Generic request for PUT

=cut

sub put_request {
    my ( $self, $args ) = @_;

    my $request = PUT(
        $self->{base_url} . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json",
        'Content'       => encode_json( $args->{data} )
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 get_request

    my $response = $client->get_request(
        {
            base_url => "https://www.bywatersolutions.com",
            endpoint => "/some/endpoint",
          [ query    => {
                param_1 => "123",
                ...
                param_2 => [ "ASD", "QWE" ],
            } ]  
        }
    );

Generic request for GET.

Both $<base_url> and I<endpoint> parameters are mandatory. I<query> should
be a hashref where keys are the query parameters pointing to desired values.
If the value is an arrayref, then the query parameter will get repeated
for each of the contained values.

In the example above, the generated query will be
B<https://www.bywatersolutions.com/some/endpoint?param_1="123"&param_2="ASD"&param_2="QWE">

=cut

sub get_request {
    my ( $self, $args ) = @_;

    my $query = "";
    if ( $args->{query} ) {
        my $uri = URI->new();
        $uri->query_form( %{ $args->{query} } );
        $query = $uri;
    }

    my $request = GET(
        $self->{base_url} . $args->{endpoint} . $query,
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
        'Content-Type'  => "application/json"
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
}

=head3 delete_request

Generic request for DELETE

=cut

sub delete_request {
    my ( $self, $args ) = @_;

    my $request = DELETE(
        $self->{base_url} . $args->{endpoint},
        'Authorization' => "Bearer " . $self->get_token,
        'Accept'        => "application/json",
    );

    if ( $self->{debug_mode} ) {
        warn p($request);
    }

    return $self->ua->request($request);
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
        $self->refresh_token
            if $self->is_token_expired;
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

    my $ua      = $self->{ua};
    my $request = $self->{request};

    my $response         = $ua->request($request);
    my $response_content = decode_json( $response->decoded_content );

    unless ( $response->code eq '200' ) {
        RapidoILL::Exception::OAuth2::AuthError->throw(
            "Authentication error: " . $response_content->{error_description} );
    }

    $self->{access_token} = $response_content->{access_token};
    $self->{expiration} =
        DateTime->now()->add( seconds => $response_content->{expires_in} );

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
