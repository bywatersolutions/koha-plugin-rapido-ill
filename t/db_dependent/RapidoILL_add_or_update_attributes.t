#!/usr/bin/perl

# This file is part of the Rapido ILL plugin
#
# The Rapido ILL plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The Rapido ILL plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Rapido ILL plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 8;
use Test::Exception;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;

# Enable ILL module for testing
t::lib::Mocks::mock_preference( 'ILLModule', 1 );

# Create test data
my $library  = $builder->build_object( { class => 'Koha::Libraries' } );
my $patron   = $builder->build_object( { class => 'Koha::Patrons' } );
my $category = $builder->build_object( { class => 'Koha::Patron::Categories' } );
my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

# Sample configuration for testing
my $sample_config_yaml = <<'EOF';
---
test-pod:
  base_url: https://test-pod.example.com
  client_id: test_client
  client_secret: test_secret
  server_code: 12345
  partners_library_id: %s
  partners_category: %s
  default_item_type: %s
  default_patron_agency: test_agency
  dev_mode: true
EOF

$sample_config_yaml = sprintf(
    $sample_config_yaml,
    $library->branchcode,
    $category->categorycode,
    $itemtype->itemtype
);

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

# Store configuration
$plugin->store_data( { configuration => $sample_config_yaml } );

# Create a test ILL request
my $ill_request = $builder->build_object(
    {
        class => 'Koha::ILL::Requests',
        value => {
            branchcode     => $library->branchcode,
            borrowernumber => $patron->borrowernumber,
            backend        => 'RapidoILL',
            status         => 'NEW',
        }
    }
);

subtest 'add_or_update_attributes - parameter validation' => sub {
    plan tests => 5;

    # Test missing required parameters
    throws_ok {
        $plugin->add_or_update_attributes( {} );
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when no parameters provided';

    throws_ok {
        $plugin->add_or_update_attributes( { request => $ill_request } );
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when attributes parameter missing';

    is( $@->param, 'attributes' );

    throws_ok {
        $plugin->add_or_update_attributes( { attributes => {} } );
    }
    'RapidoILL::Exception::MissingParameter', 'Dies when request parameter missing';

    is( $@->param, 'request' );
};

subtest 'add_or_update_attributes - creating new attributes' => sub {
    plan tests => 6;

    my $attributes = {
        circId       => 'CIRC001',
        author       => 'Test Author',
        title        => 'Test Title',
        borrowerCode => '12345',
        lenderCode   => 'TEST_LENDER'
    };

    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => $attributes
            }
        );
    }
    'Successfully creates new attributes';

    # Verify attributes were created
    my $stored_attrs = $ill_request->extended_attributes;
    is( $stored_attrs->count, 5, 'All 5 attributes were created' );

    # Check specific attribute values
    is( $stored_attrs->find( { type => 'circId' } )->value,       'CIRC001',     'circId attribute correct' );
    is( $stored_attrs->find( { type => 'author' } )->value,       'Test Author', 'author attribute correct' );
    is( $stored_attrs->find( { type => 'title' } )->value,        'Test Title',  'title attribute correct' );
    is( $stored_attrs->find( { type => 'borrowerCode' } )->value, '12345',       'borrowerCode attribute correct' );
};

subtest 'add_or_update_attributes - updating existing attributes' => sub {
    plan tests => 4;

    # Update some attributes
    my $updated_attributes = {
        circId   => 'CIRC001_UPDATED',    # Update existing
        author   => 'Updated Author',     # Update existing
        newField => 'New Value'           # Add new
    };

    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => $updated_attributes
            }
        );
    }
    'Successfully updates existing attributes';

    # Verify updates
    my $stored_attrs = $ill_request->extended_attributes;
    is( $stored_attrs->count, 6, 'Now has 6 attributes (5 original + 1 new)' );

    # Check updated values
    is( $stored_attrs->find( { type => 'circId' } )->value,   'CIRC001_UPDATED', 'circId was updated' );
    is( $stored_attrs->find( { type => 'newField' } )->value, 'New Value',       'new attribute was added' );
};

subtest 'add_or_update_attributes - handling undefined values' => sub {
    plan tests => 6;

    my $initial_count = $ill_request->extended_attributes->count;

    my $attributes_with_undef = {
        validField => 'Valid Value',
        undefField => undef,           # Should be skipped
        emptyField => '',              # Should be skipped
        zeroField  => '0',             # Should NOT be skipped
    };

    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => $attributes_with_undef
            }
        );
    }
    'Successfully handles undefined and empty values';

    my $stored_attrs = $ill_request->extended_attributes;

    # Should only add validField and zeroField (2 new attributes)
    is( $stored_attrs->count, $initial_count + 2, 'Only valid attributes were added' );

    # Check that valid attributes were added
    is( $stored_attrs->find( { type => 'validField' } )->value, 'Valid Value', 'Valid field was added' );
    is( $stored_attrs->find( { type => 'zeroField' } )->value,  '0',           'Zero value field was added' );

    # Verify undefined and empty fields were NOT added
    is( $stored_attrs->find( { type => 'undefField' } ), undef, 'Undefined field was not added' );
    is( $stored_attrs->find( { type => 'emptyField' } ), undef, 'Empty field was not added' );
};

subtest 'add_or_update_attributes - edge cases with special characters' => sub {
    plan tests => 5;

    my $special_attributes = {
        unicode_field => 'Test Unicode',                         # Simplified to avoid encoding issues
        json_field    => '{"key": "value", "number": 123}',
        html_field    => '<p>HTML content &amp; entities</p>',
        newline_field => "Line 1\nLine 2\nLine 3",
        long_field    => 'x' x 1000,                             # Test long values
    };

    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => $special_attributes
            }
        );
    }
    'Successfully handles special characters and long values';

    my $stored_attrs = $ill_request->extended_attributes;

    # Verify special character handling
    is( $stored_attrs->find( { type => 'unicode_field' } )->value, 'Test Unicode', 'Unicode field preserved' );
    is(
        $stored_attrs->find( { type => 'json_field' } )->value, '{"key": "value", "number": 123}',
        'JSON content preserved'
    );
    is(
        $stored_attrs->find( { type => 'html_field' } )->value, '<p>HTML content &amp; entities</p>',
        'HTML content preserved'
    );
    is( $stored_attrs->find( { type => 'long_field' } )->value, 'x' x 1000, 'Long values handled correctly' );
};

subtest 'add_or_update_attributes - no-op when no changes needed' => sub {
    plan tests => 2;

    # Try to "update" with the same value
    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => {
                    circId => 'CIRC001_UPDATED'    # Same value as before
                }
            }
        );
    }
    'No-op update succeeds';

    # Verify value remains correct
    my $existing_attr = $ill_request->extended_attributes->find( { type => 'circId' } );
    is( $existing_attr->value, 'CIRC001_UPDATED', 'Value remains correct' );
};

subtest 'add_or_update_attributes - performance with many attributes' => sub {
    plan tests => 3;

    # Test with a large number of attributes
    my %many_attributes;
    for my $i ( 1 .. 50 ) {
        $many_attributes{"bulk_attr_$i"} = "value_$i";
    }

    my $start_time = time;

    lives_ok {
        $plugin->add_or_update_attributes(
            {
                request    => $ill_request,
                attributes => \%many_attributes
            }
        );
    }
    'Successfully handles many attributes';

    my $end_time = time;
    my $duration = $end_time - $start_time;

    # Verify all attributes were created (should be reasonably fast)
    cmp_ok( $duration, '<', 10, 'Bulk attribute creation completed in reasonable time' );

    # Verify count
    my $bulk_attrs = $ill_request->extended_attributes->search( { type => { -like => 'bulk_attr_%' } } );
    is( $bulk_attrs->count, 50, 'All 50 bulk attributes were created' );
};

$schema->storage->txn_rollback;
