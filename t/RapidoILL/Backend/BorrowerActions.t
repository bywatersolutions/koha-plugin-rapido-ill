#!/usr/bin/perl

# Copyright 2025 ByWater Solutions
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 7;
use Test::MockObject;
use Test::Exception;

use_ok('RapidoILL::Backend::BorrowerActions');

subtest 'handle_from_action method mapping' => sub {
    plan tests => 5;

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
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
    lives_ok { $borrower_actions->handle_from_action($mock_action) } 
        'FINAL_CHECKIN should not throw exception';

    # Test ITEM_RECEIVED mapping
    $mock_action->set_always('lastCircState', 'ITEM_RECEIVED');
    lives_ok { $borrower_actions->handle_from_action($mock_action) } 
        'ITEM_RECEIVED should not throw exception';

    # Test ITEM_IN_TRANSIT mapping
    $mock_action->set_always('lastCircState', 'ITEM_IN_TRANSIT');
    lives_ok { $borrower_actions->handle_from_action($mock_action) } 
        'ITEM_IN_TRANSIT should not throw exception';

    # Skip ITEM_SHIPPED test as it requires complex database mocking
    # Test unknown state falls back to DEFAULT handler
    $mock_action->set_always('lastCircState', 'UNKNOWN_STATE');
    throws_ok { $borrower_actions->handle_from_action($mock_action) } 
        'RapidoILL::Exception::UnhandledException',
        'Unknown state should throw UnhandledException';

    # Verify the exception message
    $mock_action->set_always('lastCircState', 'UNKNOWN_STATE');
    eval { $borrower_actions->handle_from_action($mock_action) };
    like($@, qr/No method implemented for handling a UNKNOWN_STATE status/, 
         'Exception should mention the unhandled status');
};

subtest 'borrower_final_checkin method' => sub {
    plan tests => 6;

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Mock action and ILL request objects
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    
    # Track method calls for paper trail verification
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

    # Test borrower_final_checkin method
    lives_ok { $borrower_actions->borrower_final_checkin($mock_action) } 
        'borrower_final_checkin should not throw exception';

    is(scalar @status_calls, 2, 'status method should be called twice for paper trail');
    is($status_calls[0], 'B_ITEM_CHECKED_IN', 'first status should be B_ITEM_CHECKED_IN for paper trail');
    is($status_calls[1], 'COMP', 'final status should be COMP (completed)');
    is(scalar @store_calls, 1, 'store method should be called once at the end');
    
    # Verify paper trail sequence
    ok($status_calls[0] ne $status_calls[1], 'paper trail should create two different status entries');
};

subtest 'borrower_final_checkin integration with handle_from_action' => sub {
    plan tests => 5;

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Mock action and ILL request objects
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    $mock_action->set_always('lastCircState', 'FINAL_CHECKIN');
    
    # Track method calls for paper trail verification
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

    # Test that FINAL_CHECKIN calls borrower_final_checkin with paper trail
    lives_ok { $borrower_actions->handle_from_action($mock_action) } 
        'handle_from_action with FINAL_CHECKIN should not throw exception';

    is(scalar @status_calls, 2, 'FINAL_CHECKIN should create paper trail with two status calls');
    is($status_calls[0], 'B_ITEM_CHECKED_IN', 'FINAL_CHECKIN should first set B_ITEM_CHECKED_IN status');
    is($status_calls[1], 'COMP', 'FINAL_CHECKIN should finally set COMP status');
    is(scalar @store_calls, 1, 'FINAL_CHECKIN should call store once at the end');
};

subtest 'borrowing workflow completion scenario' => sub {
    plan tests => 9;  # 1 exception test + 2 simple tests + 6 FINAL_CHECKIN tests

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Focus on states that don't require complex database operations
    my @workflow_states = ('PATRON_HOLD', 'ITEM_RECEIVED', 'ITEM_IN_TRANSIT', 'FINAL_CHECKIN');
    my @expected_status_calls = (undef, 0, 0, 2);  # Only FINAL_CHECKIN sets status (twice for paper trail)
    my @expected_final_status = (undef, undef, undef, 'COMP');  # Only FINAL_CHECKIN sets final status
    
    for my $i (0 .. $#workflow_states) {
        my $state = $workflow_states[$i];
        my $expected_calls = $expected_status_calls[$i];
        my $expected_status = $expected_final_status[$i];
        
        # Mock action and ILL request objects for each step
        my $mock_action = Test::MockObject->new();
        my $mock_ill_request = Test::MockObject->new();
        
        $mock_action->set_always('ill_request', $mock_ill_request);
        $mock_action->set_always('lastCircState', $state);
        
        my @status_calls = ();
        $mock_ill_request->mock('status', sub {
            my ($self, $status) = @_;
            push @status_calls, $status if defined $status;
            return $self;
        });
        $mock_ill_request->set_always('store', $mock_ill_request);

        if ($state eq 'PATRON_HOLD') {
            # PATRON_HOLD is not in the mapping, should throw exception
            throws_ok { $borrower_actions->handle_from_action($mock_action) } 
                'RapidoILL::Exception::UnhandledException',
                "Step $i ($state) should throw exception (not handled by borrower)";
        } else {
            # Other states should be handled
            lives_ok { $borrower_actions->handle_from_action($mock_action) } 
                "Step $i ($state) should not throw exception";
            
            if (defined $expected_calls) {
                is(scalar @status_calls, $expected_calls, 
                   "Step $i ($state) should make $expected_calls status calls");
                
                if ($expected_calls > 0 && defined $expected_status) {
                    is($status_calls[-1], $expected_status, 
                       "Step $i ($state) should end with status $expected_status");
                    
                    # For FINAL_CHECKIN, verify paper trail
                    if ($state eq 'FINAL_CHECKIN') {
                        is($status_calls[0], 'B_ITEM_CHECKED_IN', 
                           "Step $i ($state) should first set B_ITEM_CHECKED_IN for paper trail");
                    }
                }
            } else {
                is(scalar @status_calls, 0, 
                   "Step $i ($state) should not set status");
            }
        }
    }
};

subtest 'method existence and documentation' => sub {
    plan tests => 6;

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Test that all expected methods exist
    can_ok($borrower_actions, 'handle_from_action');
    can_ok($borrower_actions, 'borrower_final_checkin');
    can_ok($borrower_actions, 'borrower_item_received');
    can_ok($borrower_actions, 'borrower_item_in_transit');
    can_ok($borrower_actions, 'lender_item_shipped');
    can_ok($borrower_actions, 'default_handler');
};

subtest 'paper trail functionality' => sub {
    plan tests => 8;

    # Create BorrowerActions with required parameters
    my $mock_plugin = Test::MockObject->new();
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new({
        pod => 'test_pod',
        plugin => $mock_plugin
    });
    
    # Mock action and ILL request objects
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    
    # Track all method calls in order
    my @all_calls = ();
    
    $mock_ill_request->mock('status', sub {
        my ($self, $status) = @_;
        push @all_calls, { method => 'status', arg => $status } if defined $status;
        return $self;
    });
    
    $mock_ill_request->mock('store', sub {
        my ($self) = @_;
        push @all_calls, { method => 'store', arg => undef };
        return $self;
    });

    # Test paper trail creation
    lives_ok { $borrower_actions->borrower_final_checkin($mock_action) } 
        'borrower_final_checkin should create paper trail without exception';

    # Verify call sequence
    is(scalar @all_calls, 3, 'Should make exactly 3 method calls for paper trail');
    
    # Verify first status call (paper trail)
    is($all_calls[0]->{method}, 'status', 'First call should be status method');
    is($all_calls[0]->{arg}, 'B_ITEM_CHECKED_IN', 'First status should be B_ITEM_CHECKED_IN');
    
    # Verify second status call (final status)
    is($all_calls[1]->{method}, 'status', 'Second call should be status method');
    is($all_calls[1]->{arg}, 'COMP', 'Second status should be COMP');
    
    # Verify store call (persistence)
    is($all_calls[2]->{method}, 'store', 'Third call should be store method');
    is($all_calls[2]->{arg}, undef, 'Store call should have no arguments');
};

done_testing();
