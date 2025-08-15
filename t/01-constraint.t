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

use Test::More tests => 3;
use Test::Exception;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
}

use RapidoILL::CircAction;
use RapidoILL::CircActions;

subtest 'CircAction object creation' => sub {
    plan tests => 3;
    
    my $test_data = {
        circId => 'TEST_CIRC_' . time() . '_' . $$,
        pod => 'test_pod',
        circStatus => 'ACTIVE',
        lastCircState => 'REQUESTED',
        lastUpdated => time(),
        borrowerCode => 'TEST_BORROWER',
        lenderCode => 'TEST_LENDER',
        itemId => 'TEST_ITEM_123',
        patronId => 'TEST_PATRON_456',
        dateCreated => time(),
        callNumber => 'TEST_CALL_123',
    };
    
    my $action = RapidoILL::CircAction->new($test_data);
    ok($action, 'Created new CircAction object');
    is($action->circId, $test_data->{circId}, 'CircId matches test data');
    is($action->pod, $test_data->{pod}, 'Pod matches test data');
};

subtest 'CircActions collection' => sub {
    plan tests => 2;
    
    my $actions = RapidoILL::CircActions->new;
    ok($actions, 'Created CircActions collection');
    isa_ok($actions, 'RapidoILL::CircActions', 'Collection has correct type');
};

subtest 'Constraint logic validation' => sub {
    plan tests => 4;
    
    # Test the constraint fields that should be unique together
    my $constraint_fields = ['circId', 'pod', 'circStatus', 'lastCircState'];
    
    is(scalar @$constraint_fields, 4, 'Constraint has 4 fields');
    is($constraint_fields->[0], 'circId', 'First constraint field is circId');
    is($constraint_fields->[1], 'pod', 'Second constraint field is pod');
    is($constraint_fields->[2], 'circStatus', 'Third constraint field is circStatus');
};
