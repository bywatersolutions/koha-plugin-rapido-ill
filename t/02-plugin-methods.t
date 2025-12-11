#!/usr/bin/env perl

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

use Test::More tests => 3;
use Test::NoWarnings;
use Test::Exception;

BEGIN {
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
}

subtest 'Plugin metadata and methods' => sub {
    plan tests => 9;

    # Test plugin metadata
    my $plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL';

    # Core plugin methods
    can_ok( $plugin_class, 'new' );
    can_ok( $plugin_class, 'install' );
    can_ok( $plugin_class, 'upgrade' );

    # Plugin-specific methods
    can_ok( $plugin_class, 'get_queued_tasks' );
    can_ok( $plugin_class, 'get_client' );
    can_ok( $plugin_class, 'get_borrower_actions' );
    can_ok( $plugin_class, 'get_lender_actions' );
    can_ok( $plugin_class, 'get_normalizer' );
    can_ok( $plugin_class, 'validate_pod' );
};
