package t::lib::Mocks::Rapido;

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

use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

use constant POD => 'test-pod';

=head1 NAME

t::lib::Mocks::Rapido - Mock RapidoILL plugin for testing

=head1 SYNOPSIS

    use t::lib::Mocks::Rapido;

    my $plugin = t::lib::Mocks::Rapido->new({
        library  => $library,
        category => $category,
        itemtype => $itemtype
    });

=head1 DESCRIPTION

Provides a standardized way to create RapidoILL plugin instances with
test configuration, following Koha's t::lib::Mocks pattern.

=head1 METHODS

=head2 new

    my $plugin = t::lib::Mocks::Rapido->new({
        library  => $library,   # Koha::Library object
        category => $category,  # Koha::Patron::Category object
        itemtype => $itemtype   # Koha::ItemType object
    });

Creates a new RapidoILL plugin instance with test configuration.

=cut

sub new {
    my ( $class, $params ) = @_;

    my $library         = $params->{library}                  || die "library parameter required";
    my $category        = $params->{category}                 || die "category parameter required";
    my $itemtype        = $params->{itemtype}                 || die "itemtype parameter required";
    my $pickup_strategy = $params->{pickup_location_strategy} || 'partners_library';
    my $dev_mode        = $params->{dev_mode} // 1;    # Default to true for testing

    # Sample configuration template
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
  default_patron_agency: TEST_AGENCY
  renewal_accepted_note: Renewal accepted
  renewal_request_note: Renewal requested
  due_date_buffer_days: 7
  renewal_buffer_days: 7
  central_item_type_mapping:
    200: BOOK
    500: DVD
  lending:
    automatic_final_checkin: false
    automatic_item_shipped: false
    pickup_location_strategy: %s
  dev_mode: %s
EOF

    # Fill in the template with actual values
    my $config_yaml = sprintf(
        $sample_config_yaml,
        $library->branchcode,
        $category->categorycode,
        $itemtype->itemtype,
        $pickup_strategy,
        $dev_mode ? 'true' : 'false'
    );

    # Create plugin and store configuration
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
    $plugin->store_data( { configuration => $config_yaml } );

    return $plugin;
}

1;
