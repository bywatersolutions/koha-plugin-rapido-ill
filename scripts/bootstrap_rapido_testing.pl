#!/usr/bin/perl

# Bootstrap Script for Rapido ILL Plugin Testing
# Sets up everything needed to test the Rapido plugin with mock API

use Modern::Perl;
use DBI;
use YAML::XS;
use JSON;
use File::Slurp;
use Getopt::Long;
use Pod::Usage;

=head1 NAME

bootstrap_rapido_testing.pl - Bootstrap Rapido ILL Plugin Testing Environment

=head1 SYNOPSIS

bootstrap_rapido_testing.pl [options]

 Options:
   --mock-port=N        Port for mock API (default: 3001)
   --help              This help message

=head1 DESCRIPTION

This script sets up everything needed to test the Rapido ILL plugin:

1. Installs the plugin in Koha
2. Configures the plugin with mock API settings
3. Sets up ILL prerequisites (ILLModule, IllLog, item types, patron categories)
4. Creates sample configuration with KTD-compatible data
5. Sets up database permissions and helper scripts
6. Provides instructions for running tests

Run this after starting a fresh KTD environment.

=cut

# Command line options
my $mock_port = 3001;
my $help      = 0;

GetOptions(
    'mock-port=i' => \$mock_port,
    'help|?'      => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

print "=== Rapido ILL Plugin Testing Bootstrap ===\n\n";

# Step 1: Install the plugin
print "1. Installing Rapido ILL plugin...\n";
my $install_result = system("cd /kohadevbox/koha && perl misc/devel/install_plugins.pl 2>/dev/null");
if ( $install_result == 0 ) {
    print "   ✓ Plugin installed successfully\n";
} else {
    print "   ⚠ Plugin installation had warnings (this is normal)\n";
}

# Step 2: Configure the plugin with mock API settings
print "\n2. Configuring plugin for mock API testing...\n";

# Get all existing branches (excluding our created Rapido agencies) for location mapping
my $dbh_branches = DBI->connect(
    "DBI:mysql:database=koha_kohadev;host=db",
    "root",
    "password",
    { RaiseError => 1, AutoCommit => 1 }
);

my $branch_sth =
    $dbh_branches->prepare("SELECT branchcode FROM branches WHERE branchcode != 'RAPIDO' ORDER BY branchcode");
$branch_sth->execute();

my %location_to_library = ();
while ( my ($branchcode) = $branch_sth->fetchrow_array() ) {
    $location_to_library{$branchcode} = $branchcode;    # 1:1 mapping
}
$dbh_branches->disconnect();

my $plugin_config = {
    'mock-pod' => {
        base_url                    => "http://localhost:$mock_port",
        client_id                   => 'mock_client',
        client_secret               => 'mock_secret',
        server_code                 => '11747',
        partners_library_id         => 'RAPIDO',                              # Use RAPIDO branch for agency patrons
        partners_category           => 'ILL',
        default_item_type           => 'ILL',
        default_patron_agency       => 'ffyh',                                # This is the agency code, not branch code
        default_location            => '',
        default_checkin_note        => 'Additional processing required (ILL)',
        default_hold_note           => 'Placed by ILL',
        default_marc_framework      => 'FA',
        default_item_ccode          => 'RAPIDO',
        default_notforloan          => '',
        materials_specified         => 1,
        default_materials_specified => 'Additional processing required (ILL)',
        location_to_library         => \%location_to_library,
        borrowing                   => {
            automatic_item_in_transit => 0,
            automatic_item_receive    => 0
        },
        lending => {
            automatic_final_checkin => 0,
            automatic_item_shipped  => 0
        },
        debt_blocks_holds        => 1,
        max_debt_blocks_holds    => 100,
        expiration_blocks_holds  => 1,
        restriction_blocks_holds => 1,
        debug_mode               => 1,
        debug_requests           => 1,
        dev_mode                 => 0,
        default_retry_delay      => 120
    }
};

my $yaml_config = YAML::XS::Dump($plugin_config);

# Clean up the YAML to use proper boolean values
$yaml_config =~ s/: 1$/: true/gm;
$yaml_config =~ s/: 0$/: false/gm;

# Update plugin configuration in database
eval {
    my $dbh = DBI->connect(
        "DBI:mysql:database=koha_kohadev;host=db",
        "root",
        "password",
        { RaiseError => 1, AutoCommit => 1 }
    );

    my $sth = $dbh->prepare(
        "UPDATE plugin_data SET plugin_value = ? 
         WHERE plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL' 
         AND plugin_key = 'configuration'"
    );

    $sth->execute($yaml_config);

    if ( $sth->rows > 0 ) {
        print "   ✓ Plugin configuration updated\n";
    } else {
        print "   ⚠ Plugin configuration not found, creating new entry\n";

        my $insert_sth = $dbh->prepare(
            "INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value) 
             VALUES ('Koha::Plugin::Com::ByWaterSolutions::RapidoILL', 'configuration', ?)"
        );
        $insert_sth->execute($yaml_config);
        print "   ✓ Plugin configuration created\n";
    }

    $dbh->disconnect;
};

if ($@) {
    print "   ✗ Database configuration failed: $@\n";
    print "   You may need to configure the plugin manually through the web interface\n";
}

# Step 3: Setup ILL prerequisites
print "\n3. Setting up ILL prerequisites...\n";

eval {
    my $dbh = DBI->connect(
        "DBI:mysql:database=koha_kohadev;host=db",
        "root",
        "password",
        { RaiseError => 1, AutoCommit => 1 }
    );

    # Enable ILL Module
    my $ill_pref_sth = $dbh->prepare(
        "INSERT INTO systempreferences (variable, value, explanation, type) 
         VALUES ('ILLModule', '1', 'If ON, enables the interlibrary loans module.', 'YesNo')
         ON DUPLICATE KEY UPDATE value = '1'"
    );
    $ill_pref_sth->execute();
    print "   ✓ ILL Module enabled\n";

    # Enable ILL Logging
    my $ill_log_sth = $dbh->prepare(
        "INSERT INTO systempreferences (variable, value, explanation, type) 
         VALUES ('IllLog', '1', 'If ON, log ILL activity.', 'YesNo')
         ON DUPLICATE KEY UPDATE value = '1'"
    );
    $ill_log_sth->execute();
    print "   ✓ ILL Logging enabled\n";

    # Create ILL item type
    my $itemtype_sth = $dbh->prepare(
        "INSERT IGNORE INTO itemtypes (itemtype, description, rentalcharge, notforloan, imageurl, summary, checkinmsg, checkinmsgtype, sip_media_type, hideinopac, searchcategory) 
         VALUES ('ILL', 'Interlibrary Loan', 0.00, 0, '', '', '', 'message', '001', 0, '')"
    );
    $itemtype_sth->execute();
    print "   ✓ ILL item type created\n";

    # Create ILL patron category
    my $category_sth = $dbh->prepare(
        "INSERT IGNORE INTO categories (categorycode, description, enrolmentperiod, upperagelimit, dateofbirthrequired, enrolmentfee, overduenoticerequired, reservefee, hidelostitems, category_type) 
         VALUES ('ILL', 'Interlibrary Loan', 99, 999, 0, 0.00, 0, 0.00, 0, 'A')"
    );
    $category_sth->execute();
    print "   ✓ ILL patron category created\n";

    # Create RAPIDO branch for agency patrons
    my $rapido_branch_sth = $dbh->prepare(
        "INSERT IGNORE INTO branches (branchcode, branchname, branchaddress1, branchcity, branchzip, branchcountry, branchphone, branchemail, branchurl, issuing, branchip, branchnotes, pickup_location, public) 
         VALUES ('RAPIDO', 'Rapido ILL Central Hub', 'Rapido ILL Network', 'Virtual', '0000', 'Network', '+00-000-0000000', 'rapido\@ill.network', 'https://rapido.ill.network', 1, '', 'Central hub for Rapido ILL agency patrons', 0, 0)"
    );
    $rapido_branch_sth->execute();
    print "   ✓ Created RAPIDO branch for agency patrons\n";

    $dbh->disconnect;
};

if ($@) {
    print "   ✗ ILL prerequisites setup failed: $@\n";
}

# Step 4: Create agencies for mock API data
print "\n4. Creating agencies for mock API testing...\n";

# Agencies used in mock API responses that need patrons
my @mock_agencies = (
    {
        agency_id    => 'famaf',
        description  => 'Facultad de Matemática, Astronomía, Física y Computación',
        local_server => 'famaf'
    },
    {
        agency_id    => 'derecho',
        description  => 'Facultad de Derecho y Ciencias Sociales',
        local_server => 'derecho'
    },
    {
        agency_id    => 'psico',
        description  => 'Facultad de Psicología',
        local_server => 'psico'
    },
    {
        agency_id    => 'ffyh',
        description  => 'Facultad de Filosofía y Humanidades',
        local_server => 'ffyh'
    }
);

foreach my $agency (@mock_agencies) {
    my $cmd =
          "cd /kohadevbox/plugins/rapido-ill && "
        . "PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. "
        . "perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/manage_agencies.pl "
        . "--pod mock-pod --add "
        . "--agency_id '$agency->{agency_id}' "
        . "--local_server '$agency->{local_server}' "
        . "--description '$agency->{description}' "
        . "--visiting_checkout 2>/dev/null";

    my $result = system($cmd);
    if ( $result == 0 ) {
        print "   ✓ Created agency: $agency->{agency_id} - $agency->{description}\n";
    } else {
        print "   ⚠ Agency $agency->{agency_id} may already exist or creation failed\n";
    }
}

# Step 5: Create sample mock API configuration
print "\n5. Creating mock API configuration...\n";

my $mock_config_path = "/kohadevbox/plugins/rapido-ill/scripts/mock_config.json";
if ( -f $mock_config_path ) {
    print "   ✓ Mock API configuration already exists\n";
} else {

    # The mock API will create its own config on first run
    print "   ✓ Mock API will create configuration on first run\n";
}

# Step 6: Set up environment
print "\n6. Setting up environment...\n";

# Create a helper script for running sync
my $sync_helper = '#!/bin/bash
# Helper script for running sync_requests.pl with proper environment

cd /kohadevbox/plugins/rapido-ill
export PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

echo "Available pods:"
perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --list_pods

echo ""
echo "Running sync for mock-pod..."
perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod mock-pod "$@"
';

write_file( '/kohadevbox/plugins/rapido-ill/scripts/run_sync.sh', $sync_helper );
system('chmod +x /kohadevbox/plugins/rapido-ill/scripts/run_sync.sh');
print "   ✓ Created sync helper script: run_sync.sh\n";

# Create a helper script for testing the mock API
my $test_helper = '#!/bin/bash
# Helper script for testing the mock API

API_URL="http://localhost:' . $mock_port . '"

echo "=== Testing Mock Rapido API ==="
echo ""

echo "1. Checking API status..."
curl -s "$API_URL/status" | python3 -m json.tool 2>/dev/null || curl -s "$API_URL/status"

echo ""
echo ""
echo "2. Testing authentication..."
curl -s -X POST "$API_URL/view/broker/auth" \
  -H "Content-Type: application/json" \
  -d \'{"grant_type":"client_credentials","client_id":"mock_client","client_secret":"mock_secret"}\'

echo ""
echo ""
echo "3. Testing circulation requests (will advance through scenario)..."
for i in {1..3}; do
  echo "   Step $i:"
  curl -s "$API_URL/view/broker/circ/circrequests?state=ACTIVE&startTime=1742713250&endTime=1755204317" | \
    python3 -c "import sys,json; data=json.load(sys.stdin); print(f\"    Status: {data.get(\'data\',[{}])[0].get(\'circStatus\',\'NO_DATA\') if data.get(\'data\') else \'EMPTY\'}\")" 2>/dev/null || \
    echo "    (Raw response - install python3 for formatted output)"
done

echo ""
echo "=== Mock API Test Complete ==="
';

write_file( '/kohadevbox/plugins/rapido-ill/scripts/test_mock_api.sh', $test_helper );
system('chmod +x /kohadevbox/plugins/rapido-ill/scripts/test_mock_api.sh');
print "   ✓ Created API test script: test_mock_api.sh\n";

# Step 7: Verify KTD sample data
print "\n7. Verifying KTD sample data...\n";

eval {
    my $dbh = DBI->connect(
        "DBI:mysql:database=koha_kohadev;host=db",
        "root",
        "password",
        { RaiseError => 1, AutoCommit => 1 }
    );

    # Check for sample patrons
    my $patron_sth = $dbh->prepare(
        "SELECT cardnumber, firstname, surname FROM borrowers WHERE cardnumber IN ('23529000445172', '23529000152273', '23529000105040') LIMIT 3"
    );
    $patron_sth->execute();
    my $patron_count = 0;
    while ( my $row = $patron_sth->fetchrow_hashref ) {
        $patron_count++;
        print "   ✓ Found patron: $row->{firstname} $row->{surname} ($row->{cardnumber})\n";
    }

    # Check for sample items
    my $item_sth = $dbh->prepare(
        "SELECT i.barcode, b.title FROM items i JOIN biblio b ON i.biblionumber = b.biblionumber WHERE i.barcode IN ('3999900000001', '3999900000018', '3999900000021') LIMIT 3"
    );
    $item_sth->execute();
    my $item_count = 0;
    while ( my $row = $item_sth->fetchrow_hashref ) {
        $item_count++;
        my $short_title = substr( $row->{title}, 0, 30 ) . ( length( $row->{title} ) > 30 ? "..." : "" );
        print "   ✓ Found item: $row->{barcode} - $short_title\n";
    }

    $dbh->disconnect;

    if ( $patron_count == 0 || $item_count == 0 ) {
        print "   ⚠ Some sample data missing - mock API will still work but with placeholder data\n";
    }
};

if ($@) {
    print "   ⚠ Could not verify sample data: $@\n";
}

# Step 8: Validate plugin configuration
print "\n8. Validating plugin configuration...\n";

eval {
    # Create a temporary validation script
    my $validation_script = '/tmp/validate_config.pl';
    open my $fh, '>', $validation_script or die "Cannot create validation script: $!";
    print $fh q{
        use lib '/usr/share/koha/lib';
        use lib '/kohadevbox/plugins/rapido-ill/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
        use C4::Context;
        use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;
        
        # Clear cached preferences
        C4::Context->clear_syspref_cache();
        
        my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
        my $config_check = $plugin->check_configuration();
        
        if (@$config_check) {
            print "ERRORS:" . scalar(@$config_check) . "\n";
            foreach my $error (@$config_check) {
                print "  - " . $error->{code} . "\n";
            }
        } else {
            print "OK\n";
        }
    };
    close $fh;

    my $config_result = `cd /kohadevbox/plugins/rapido-ill && perl $validation_script 2>/dev/null`;
    unlink $validation_script;

    if ( $config_result =~ /^OK/ ) {
        print "   ✅ Plugin configuration is valid\n";
    } elsif ( $config_result =~ /^ERRORS:/ ) {
        print "   ⚠ Configuration issues found:\n";
        print $config_result;
        print "   The plugin may still work but some features might be limited\n";
    } else {
        print "   ⚠ Could not validate configuration\n";
        print "   You can manually test with: check_configuration() method\n";
    }
};

if ($@) {
    print "   ⚠ Could not validate configuration: $@\n";
}

# Final instructions
print "\n" . "=" x 60 . "\n";
print "🎉 BOOTSTRAP COMPLETE!\n";
print "=" x 60 . "\n\n";

print "📋 NEXT STEPS:\n\n";

print "1. START MOCK API:\n";
print "   cd /kohadevbox/plugins/rapido-ill/scripts\n";
print "   ./mock_rapido_api.pl --scenario=borrowing --port=$mock_port\n\n";

print "2. TEST MOCK API (in another terminal):\n";
print "   cd /kohadevbox/plugins/rapido-ill/scripts\n";
print "   ./test_mock_api.sh\n\n";

print "3. RUN SYNC SCRIPT:\n";
print "   cd /kohadevbox/plugins/rapido-ill/scripts\n";
print "   ./run_sync.sh\n\n";

print "4. SWITCH SCENARIOS:\n";
print "   curl -X POST http://localhost:$mock_port/control/scenario/lending\n";
print "   curl -X POST http://localhost:$mock_port/control/scenario/borrowing\n";
print "   curl -X POST http://localhost:$mock_port/control/reset\n\n";

print "📚 DOCUMENTATION:\n";
print "   - Mock API Guide: MOCK_API_GUIDE.md\n";
print "   - Plugin README: README.md\n\n";

print "🔧 CONFIGURATION:\n";
print "   - Plugin configured for mock-pod at http://localhost:$mock_port\n";
print "   - Debug mode enabled for detailed logging\n";
print "   - Uses KTD sample data (patrons, items, libraries)\n\n";

print "🎯 READY TO TEST RAPIDO ILL WORKFLOWS!\n";

=head1 EXAMPLES

After running bootstrap:

  # Terminal 1: Start mock API
  ./mock_rapido_api.pl --scenario=borrowing --port=3001

  # Terminal 2: Test the setup
  ./test_mock_api.sh
  ./run_sync.sh

  # Switch to lending scenario
  curl -X POST http://localhost:3001/control/scenario/lending
  ./run_sync.sh

=cut
