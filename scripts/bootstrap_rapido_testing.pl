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
3. Creates sample configuration with KTD-compatible data
4. Sets up database permissions
5. Provides instructions for running tests

Run this after starting a fresh KTD environment.

=cut

# Command line options
my $mock_port = 3001;
my $help = 0;

GetOptions(
    'mock-port=i' => \$mock_port,
    'help|?'      => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

print "=== Rapido ILL Plugin Testing Bootstrap ===\n\n";

# Step 1: Install the plugin
print "1. Installing Rapido ILL plugin...\n";
my $install_result = system("cd /kohadevbox/koha && perl misc/devel/install_plugins.pl 2>/dev/null");
if ($install_result == 0) {
    print "   ✓ Plugin installed successfully\n";
} else {
    print "   ⚠ Plugin installation had warnings (this is normal)\n";
}

# Step 2: Configure the plugin with mock API settings
print "\n2. Configuring plugin for mock API testing...\n";

my $plugin_config = {
    'mock-pod' => {
        base_url => "http://localhost:$mock_port",
        client_id => 'mock_client',
        client_secret => 'mock_secret',
        server_code => '11747',
        partners_library_id => 'MPL',
        partners_category => 'ILL',
        default_item_type => 'ILL',
        default_patron_agency => 'MPL',
        default_location => '',
        default_checkin_note => 'Additional processing required (ILL)',
        default_hold_note => 'Placed by ILL',
        default_marc_framework => 'FA',
        default_item_ccode => 'RAPIDO',
        default_notforloan => '',
        materials_specified => JSON::true,
        default_materials_specified => 'Additional processing required (ILL)',
        location_to_library => {
            RES_SHARE => 'MPL'
        },
        borrowing => {
            automatic_item_in_transit => JSON::false,
            automatic_item_receive => JSON::false
        },
        lending => {
            automatic_final_checkin => JSON::false,
            automatic_item_shipped => JSON::false
        },
        debt_blocks_holds => JSON::true,
        max_debt_blocks_holds => 100,
        expiration_blocks_holds => JSON::true,
        restriction_blocks_holds => JSON::true,
        debug_mode => JSON::true,
        debug_requests => JSON::true,
        dev_mode => JSON::false,
        default_retry_delay => 120
    }
};

my $yaml_config = YAML::XS::Dump($plugin_config);

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
    
    if ($sth->rows > 0) {
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

# Step 3: Create sample mock API configuration
print "\n3. Creating mock API configuration...\n";

my $mock_config_path = "/kohadevbox/plugins/rapido-ill/scripts/mock_config.json";
if (-f $mock_config_path) {
    print "   ✓ Mock API configuration already exists\n";
} else {
    # The mock API will create its own config on first run
    print "   ✓ Mock API will create configuration on first run\n";
}

# Step 4: Set up environment
print "\n4. Setting up environment...\n";

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

write_file('/kohadevbox/plugins/rapido-ill/scripts/run_sync.sh', $sync_helper);
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

write_file('/kohadevbox/plugins/rapido-ill/scripts/test_mock_api.sh', $test_helper);
system('chmod +x /kohadevbox/plugins/rapido-ill/scripts/test_mock_api.sh');
print "   ✓ Created API test script: test_mock_api.sh\n";

# Step 5: Verify KTD sample data
print "\n5. Verifying KTD sample data...\n";

eval {
    my $dbh = DBI->connect(
        "DBI:mysql:database=koha_kohadev;host=db",
        "root",
        "password",
        { RaiseError => 1, AutoCommit => 1 }
    );
    
    # Check for sample patrons
    my $patron_sth = $dbh->prepare("SELECT cardnumber, firstname, surname FROM borrowers WHERE cardnumber IN ('23529000445172', '23529000152273', '23529000105040') LIMIT 3");
    $patron_sth->execute();
    my $patron_count = 0;
    while (my $row = $patron_sth->fetchrow_hashref) {
        $patron_count++;
        print "   ✓ Found patron: $row->{firstname} $row->{surname} ($row->{cardnumber})\n";
    }
    
    # Check for sample items
    my $item_sth = $dbh->prepare("SELECT i.barcode, b.title FROM items i JOIN biblio b ON i.biblionumber = b.biblionumber WHERE i.barcode IN ('3999900000001', '3999900000018', '3999900000021') LIMIT 3");
    $item_sth->execute();
    my $item_count = 0;
    while (my $row = $item_sth->fetchrow_hashref) {
        $item_count++;
        my $short_title = substr($row->{title}, 0, 30) . (length($row->{title}) > 30 ? "..." : "");
        print "   ✓ Found item: $row->{barcode} - $short_title\n";
    }
    
    $dbh->disconnect;
    
    if ($patron_count == 0 || $item_count == 0) {
        print "   ⚠ Some sample data missing - mock API will still work but with placeholder data\n";
    }
};

if ($@) {
    print "   ⚠ Could not verify sample data: $@\n";
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
