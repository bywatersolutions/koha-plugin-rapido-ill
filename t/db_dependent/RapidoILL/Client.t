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

use Test::More tests => 2;
use Test::MockModule;
use Test::Exception;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::Client');
}

subtest 'lender_renew method' => sub {
    plan tests => 2;

    # Mock the plugin
    my $mock_plugin = bless {}, 'MockPlugin';
    *MockPlugin::validate_params = sub { return 1; };

    # Create client with mocked plugin
    my $client = bless {
        plugin => $mock_plugin,
        configuration => { dev_mode => 1 }
    }, 'RapidoILL::Client';

    subtest 'dev mode behavior' => sub {
        plan tests => 1;

        my $result;
        lives_ok {
            $result = $client->lender_renew({
                circId => 'CIRC001',
                dueDateTime => 1735689600
            });
        } 'lender_renew succeeds in dev mode';
    };

    subtest 'method exists and callable' => sub {
        plan tests => 1;

        ok($client->can('lender_renew'), 'lender_renew method exists');
    };
};
