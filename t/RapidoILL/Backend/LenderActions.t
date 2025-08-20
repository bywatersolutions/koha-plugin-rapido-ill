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
use Test::MockObject;
use Test::Exception;

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::Backend::LenderActions');
}

subtest 'handle_from_action method mapping for FINAL_CHECKIN' => sub {
    plan tests => 3;

    # Create LenderActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $lender_actions = RapidoILL::Backend::LenderActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Mock action object with basic required methods
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    $mock_ill_request->set_always('status', $mock_ill_request);
    $mock_ill_request->set_always('store', $mock_ill_request);

    # Test FINAL_CHECKIN mapping (our main focus)
    $mock_action->set_always('lastCircState', 'FINAL_CHECKIN');
    lives_ok { $lender_actions->handle_from_action($mock_action) } 
        'FINAL_CHECKIN should not throw exception';

    # Test unknown state falls back to DEFAULT handler
    $mock_action->set_always('lastCircState', 'UNKNOWN_STATE');
    throws_ok { $lender_actions->handle_from_action($mock_action) } 
        'RapidoILL::Exception::UnhandledException',
        'Unknown state should throw UnhandledException';

    # Verify the exception message
    $mock_action->set_always('lastCircState', 'UNKNOWN_STATE');
    eval { $lender_actions->handle_from_action($mock_action) };
    like($@, qr/No method implemented for handling a UNKNOWN_STATE status/, 
         'Exception should mention the unhandled status');
};

subtest 'lender_final_checkin method' => sub {
    plan tests => 4;

    # Create LenderActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $lender_actions = RapidoILL::Backend::LenderActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Mock action and ILL request objects
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    
    # Track method calls
    my @status_calls = ();
    my @store_calls = ();
    
    $mock_ill_request->mock('status', sub {
        my ($self, $status) = @_;
        push @status_calls, $status if defined $status;
        return $self;
    });
    
    $mock_ill_request->mock('store', sub {
        my ($self) = @_;
        push @store_calls, 1;
        return $self;
    });

    # Test lender_final_checkin method
    lives_ok { $lender_actions->lender_final_checkin($mock_action) } 
        'lender_final_checkin should not throw exception';

    is(scalar @status_calls, 1, 'status method should be called once');
    is($status_calls[0], 'COMP', 'status should be set to COMP (completed)');
    is(scalar @store_calls, 1, 'store method should be called once');
};

done_testing();
