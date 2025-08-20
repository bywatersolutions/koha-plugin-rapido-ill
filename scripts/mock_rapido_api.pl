#!/usr/bin/env perl

# Mock Rapido API Service - Working Configurable Version
# Based on actual RapidoILL::Client API paths, without problematic modules

use Modern::Perl;
use Mojolicious::Lite -signatures;
use Mojo::JSON qw(decode_json encode_json);
use Getopt::Long;
use Pod::Usage;
use DateTime;

=head1 NAME

mock_rapido_api_working.pl - Mock Rapido API with Correct Endpoints

=head1 SYNOPSIS

mock_rapido_api_working.pl [options]

 Options:
   --port=N             Port to run on (default: 3000)
   --config=FILE        Configuration file (default: mock_config.json)
   --scenario=NAME      Load predefined scenario (borrowing|lending|mixed)
   --help              This help message

=head1 DESCRIPTION

Mock API service with actual Rapido ILL endpoint paths from RapidoILL::Client:

Authentication: POST /view/broker/auth
Circulation Requests: GET /view/broker/circ/circrequests
Lender Actions: POST /view/broker/circ/{circId}/lendercancel, /lendershipped
Borrower Actions: POST /view/broker/circ/{circId}/itemreceived, /itemreturned

=cut

# Command line options
my $port        = 3000;
my $config_file = 'mock_config.json';
my $scenario    = '';
my $help        = 0;

GetOptions(
    'port=i'     => \$port,
    'config=s'   => \$config_file,
    'scenario=s' => \$scenario,
    'help|?'     => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

# Global state for tracking requests and responses
my $api_state = {
    requests   => {},
    call_count => {},
    scenarios  => {},
};

# Load configuration from JSON file
sub load_config {
    my $config = {};

    if ( -f $config_file ) {
        # Load existing config
        eval {
            open my $fh, '<', $config_file or die "Cannot open $config_file: $!";
            my $json_text = do { local $/; <$fh> };
            close $fh;
            $config = decode_json($json_text);
            app->log->info("Loaded configuration from $config_file");
        };
        if ($@) {
            app->log->error("Failed to load config file: $@");
            die "Cannot load configuration file $config_file: $@";
        }
    } else {
        app->log->error("Configuration file $config_file not found");
        die "Configuration file $config_file not found. Please ensure it exists.";
    }

    return $config;
}

# Load configuration
my $config = load_config();

# Apply scenario if specified
if ( $scenario && $config->{scenarios}->{$scenario} ) {
    $api_state->{current_scenario} = $scenario;
    $api_state->{scenario_step}    = 0;
    app->log->info("Loaded scenario: $scenario");
}

# Helper to get current response based on scenario
sub get_scenario_response {
    my ($endpoint) = @_;

    my $current_scenario = $api_state->{current_scenario};
    return unless $current_scenario;

    my $scenario_config = $config->{scenarios}->{$current_scenario};
    return unless $scenario_config;

    my $step     = $api_state->{scenario_step} || 0;
    my $sequence = $scenario_config->{sequence};

    return unless $step < @$sequence;

    my $step_config = $sequence->[$step];
    return unless $step_config->{endpoint} eq $endpoint;

    # Advance to next step
    $api_state->{scenario_step}++;

    return $config->{responses}->{ $step_config->{response} };
}

# ACTUAL RAPIDO API ENDPOINTS (from RapidoILL::Client)

# Authentication endpoint: POST /view/broker/auth
post '/view/broker/auth' => sub ($c) {
    app->log->info("Authentication request received");

    $c->render(
        json => {
            access_token => 'mock_token_12345',
            token_type   => 'Bearer',
            expires_in   => 3600
        }
    );
};

# Circulation requests: GET /view/broker/circ/circrequests
get '/view/broker/circ/circrequests' => sub ($c) {
    my $start_time  = $c->param('startTime') || '';
    my $end_time    = $c->param('endTime')   || '';
    my @states      = $c->every_param('state');
    my $content     = $c->param('content')    || 'concise';        # Default to concise per spec
    my $time_target = $c->param('timeTarget') || 'lastUpdated';    # Default per spec

    # Default to ACTIVE if no states provided (per spec)
    @states = ('ACTIVE') unless @states;

    # Increment call count
    $api_state->{call_count}->{circulation_requests}++;
    my $call_num = $api_state->{call_count}->{circulation_requests};

    app->log->info("Circulation requests called (call #$call_num)");
    app->log->info("  startTime: $start_time, endTime: $end_time");
    app->log->info( "  states: [" . join( ', ', @states ) . "]" );
    app->log->info("  content: $content, timeTarget: $time_target");

    # Try to get response from scenario
    my $response = get_scenario_response('circulation_requests');

    # Fallback to empty response
    $response ||= { data => [] };

    # Transform data to match Rapido spec format
    my @rapido_format = ();
    for my $item ( @{ $response->{data} } ) {
        my $rapido_item = {};

        # Always include these fields (both concise and verbose)
        $rapido_item->{circId}             = $item->{circId};
        $rapido_item->{borrowerCode}       = $item->{borrowerCode} || $item->{patronAgencyCode};
        $rapido_item->{lenderCode}         = $item->{lenderCode};
        $rapido_item->{puaLocalServerCode} = $item->{puaLocalServerCode} || $item->{patronAgencyCode};
        $rapido_item->{lastCircState}      = $item->{circStatus};    # Map circStatus to lastCircState
        $rapido_item->{itemId}             = $item->{itemId};
        $rapido_item->{patronId}           = $item->{patronId};

        # Convert DateTime strings to Unix epoch (per spec)
        if ( $item->{needBefore} ) {
            $rapido_item->{needBefore} = DateTime->from_epoch( epoch => time() )->add( days => 30 )->epoch;
        }
        if ( $item->{dateCreated} ) {

            # Parse ISO8601 and convert to epoch
            my $dt = DateTime->now->subtract( hours => 2 );
            $rapido_item->{dateCreated} = $dt->epoch;
        }
        if ( $item->{lastUpdated} ) {
            my $dt = DateTime->now->subtract( hours => 1 );
            $rapido_item->{lastUpdated} = $dt->epoch;
        }
        if ( $item->{dueDateTime} ) {
            my $dt = DateTime->now->add( days => 23 );
            $rapido_item->{dueDateTime} = $dt->epoch;
        }

        # Add verbose fields if requested
        if ( $content eq 'verbose' ) {
            $rapido_item->{puaAgencyCode}    = $item->{patronAgencyCode};
            $rapido_item->{circStatus}       = $item->{circStatus};
            $rapido_item->{itemBarcode}      = $item->{itemBarcode};
            $rapido_item->{itemAgencyCode}   = $item->{lenderCode} || $item->{patronAgencyCode};
            $rapido_item->{callNumber}       = $item->{callNumber} || '';
            $rapido_item->{patronName}       = $item->{patronName};
            $rapido_item->{patronAgencyCode} = $item->{patronAgencyCode};
            $rapido_item->{pickupLocation} =
                  $item->{pickupLocation}
                ? $item->{pickupLocation} . ':' . $item->{pickupLocation} . ' Library'
                : 'ffyh:Facultad de Filosofía y Humanidades';
            $rapido_item->{title}  = $item->{title};
            $rapido_item->{author} = $item->{author};
        }

        push @rapido_format, $rapido_item;
    }

    # Return array directly (per spec - no wrapper object)
    $c->render( json => \@rapido_format );
};

# Locals endpoint: GET /view/broker/locals
get '/view/broker/locals' => sub ($c) {
    app->log->info("Locals endpoint called");

    # Return agency list for sync_agencies
    my $locals_data = [
        {
            localCode  => "11747",    # Our server code
            agencyList => [
                {
                    agencyCode              => "ffyh",
                    description             => "Facultad de Filosofía y Humanidades",
                    requiresPasscode        => Mojo::JSON->false,
                    visitingCheckoutAllowed => Mojo::JSON->true
                },
                {
                    agencyCode              => "famaf",
                    description             => "Facultad de Matemática, Astronomía, Física y Computación",
                    requiresPasscode        => Mojo::JSON->false,
                    visitingCheckoutAllowed => Mojo::JSON->true
                },
                {
                    agencyCode              => "derecho",
                    description             => "Facultad de Derecho y Ciencias Sociales",
                    requiresPasscode        => Mojo::JSON->false,
                    visitingCheckoutAllowed => Mojo::JSON->true
                },
                {
                    agencyCode              => "psico",
                    description             => "Facultad de Psicología",
                    requiresPasscode        => Mojo::JSON->false,
                    visitingCheckoutAllowed => Mojo::JSON->true
                }
            ]
        }
    ];

    $c->render( json => $locals_data );
};

# Lender cancel: POST /view/broker/circ/{circId}/lendercancel
post '/view/broker/circ/:circId/lendercancel' => sub ($c) {
    my $circ_id = $c->param('circId');
    my $json    = $c->req->json || {};

    app->log->info("Lender cancel for circId: $circ_id");

    $c->render(
        json => {
            success => 1,
            message => "Lender cancel processed successfully",
            circId  => $circ_id,
            data    => $json
        }
    );
};

# Lender shipped: POST /view/broker/circ/{circId}/lendershipped
post '/view/broker/circ/:circId/lendershipped' => sub ($c) {
    my $circ_id = $c->param('circId');
    my $json    = $c->req->json || {};

    app->log->info("Lender shipped for circId: $circ_id");

    $c->render(
        json => {
            success => 1,
            message => "Lender shipped processed successfully",
            circId  => $circ_id,
            data    => $json
        }
    );
};

# Borrower item received: POST /view/broker/circ/{circId}/itemreceived
post '/view/broker/circ/:circId/itemreceived' => sub ($c) {
    my $circ_id = $c->param('circId');

    app->log->info("Borrower item received for circId: $circ_id");

    $c->render(
        json => {
            success => 1,
            message => "Borrower item received processed successfully",
            circId  => $circ_id
        }
    );
};

# Borrower item returned: POST /view/broker/circ/{circId}/itemreturned
post '/view/broker/circ/:circId/itemreturned' => sub ($c) {
    my $circ_id = $c->param('circId');

    app->log->info("Borrower item returned for circId: $circ_id");

    $c->render(
        json => {
            success => 1,
            message => "Borrower item returned processed successfully",
            circId  => $circ_id
        }
    );
};

# Debug endpoint to show format differences
get '/debug/formats' => sub ($c) {
    my $concise_example = {
        circId             => "315600",
        borrowerCode       => "mclc1",
        lenderCode         => "jclc1",
        puaLocalServerCode => "vclc1",
        lastCircState      => "PATRON_HOLD",
        itemId             => "2306434",
        patronId           => "91",
        dateCreated        => 1658527642,
        lastUpdated        => 1658527689,
        needBefore         => 1659132473
    };

    my $verbose_example = {
        %$concise_example,
        puaAgencyCode    => "ffyh",
        circStatus       => "PATRON_HOLD",
        itemBarcode      => "3999900000001",
        itemAgencyCode   => "famaf",
        callNumber       => "005.133 KER",
        patronName       => "Tanya Daniels",
        patronAgencyCode => "ffyh",
        pickupLocation   => "RES_SHARE:Polaris Resource Sharing Library",
        title            => "E Street shuffle",
        author           => "Heylin, Clinton",
        dueDateTime      => 1693526400
    };

    $c->render(
        json => {
            spec_info      => "Based on official Rapido API specification",
            concise_format => $concise_example,
            verbose_format => $verbose_example,
            notes          => {
                timestamps      => "All times are Unix epoch seconds (not ISO8601)",
                default_content => "concise",
                default_state   => "ACTIVE",
                response_format => "Array of objects (no wrapper)"
            }
        }
    );
};

# Status endpoint
get '/status' => sub ($c) {
    $c->render(
        json => {
            service             => 'Mock Rapido API (Working)',
            version             => '2.2.0',
            uptime              => time() - $^T,
            current_scenario    => $api_state->{current_scenario} || 'none',
            scenario_step       => $api_state->{scenario_step}    || 0,
            call_counts         => $api_state->{call_count},
            available_scenarios => [ keys %{ $config->{scenarios} } ],
            endpoints           => [
                'POST /view/broker/auth',
                'GET /view/broker/circ/circrequests',
                'POST /view/broker/circ/{circId}/lendercancel',
                'POST /view/broker/circ/{circId}/lendershipped',
                'POST /view/broker/circ/{circId}/itemreceived',
                'POST /view/broker/circ/{circId}/itemreturned'
            ]
        }
    );
};

# Control endpoints
post '/control/scenario/:name' => sub ($c) {
    my $scenario_name = $c->param('name');

    if ( $config->{scenarios}->{$scenario_name} ) {
        $api_state->{current_scenario} = $scenario_name;
        $api_state->{scenario_step}    = 0;

        $c->render(
            json => {
                success  => 1,
                message  => "Switched to scenario: $scenario_name",
                scenario => $config->{scenarios}->{$scenario_name}
            }
        );
    } else {
        $c->render(
            json => {
                success   => 0,
                error     => "Unknown scenario: $scenario_name",
                available => [ keys %{ $config->{scenarios} } ]
            },
            status => 400
        );
    }
};

post '/control/reset' => sub ($c) {
    $api_state = {
        requests   => {},
        call_count => {},
        scenarios  => {},
    };

    $c->render(
        json => {
            success => 1,
            message => "API state reset"
        }
    );
};

# Start the server
app->log->info("Starting Mock Rapido API (Working) on port $port");
app->log->info("Configuration file: $config_file");
app->log->info( "Current scenario: " . ( $api_state->{current_scenario} || 'none' ) );
app->log->info("Endpoints based on actual RapidoILL::Client paths");

app->start( 'daemon', '-l', "http://*:$port" );
