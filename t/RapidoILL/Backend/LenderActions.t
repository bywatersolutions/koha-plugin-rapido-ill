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

use Test::More tests => 4;
use Test::MockObject;
use Test::Exception;

use_ok('RapidoILL::Backend::LenderActions');

subtest 'handle_from_action method mapping' => sub {
    plan tests => 6;

    my $lender_actions = RapidoILL::Backend::LenderActions->new();
    
    # Mock action object
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    $mock_ill_request->set_always('status', $mock_ill_request);
    $mock_ill_request->set_always('store', $mock_ill_request);

    # Test FINAL_CHECKIN mapping
    $mock_action->set_always('lastCircState', 'FINAL_CHECKIN');
    lives_ok { $lender_actions->handle_from_action($mock_action) } 
        'FINAL_CHECKIN should not throw exception';

    # Test ITEM_RECEIVED mapping
    $mock_action->set_always('lastCircState', 'ITEM_RECEIVED');
    lives_ok { $lender_actions->handle_from_action($mock_action) } 
        'ITEM_RECEIVED should not throw exception';

    # Test ITEM_IN_TRANSIT mapping
    $mock_action->set_always('lastCircState', 'ITEM_IN_TRANSIT');
    lives_ok { $lender_actions->handle_from_action($mock_action) } 
        'ITEM_IN_TRANSIT should not throw exception';

    # Test ITEM_SHIPPED mapping
    $mock_action->set_always('lastCircState', 'ITEM_SHIPPED');
    lives_ok { $lender_actions->handle_from_action($mock_action) } 
        'ITEM_SHIPPED should not throw exception';

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

    my $lender_actions = RapidoILL::Backend::LenderActions->new();
    
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

subtest 'FINAL_CHECKIN consistency between borrower and lender' => sub {
    plan tests => 6;

    # Test that both borrower and lender handle FINAL_CHECKIN the same way
    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new();
    my $lender_actions = RapidoILL::Backend::LenderActions->new();
    
    # Mock action and ILL request objects for borrower
    my $mock_borrower_action = Test::MockObject->new();
    my $mock_borrower_ill_request = Test::MockObject->new();
    
    $mock_borrower_action->set_always('ill_request', $mock_borrower_ill_request);
    $mock_borrower_action->set_always('lastCircState', 'FINAL_CHECKIN');
    
    my @borrower_status_calls = ();
    $mock_borrower_ill_request->mock('status', sub {
        my ($self, $status) = @_;
        push @borrower_status_calls, $status if defined $status;
        return $self;
    });
    $mock_borrower_ill_request->set_always('store', $mock_borrower_ill_request);

    # Mock action and ILL request objects for lender
    my $mock_lender_action = Test::MockObject->new();
    my $mock_lender_ill_request = Test::MockObject->new();
    
    $mock_lender_action->set_always('ill_request', $mock_lender_ill_request);
    $mock_lender_action->set_always('lastCircState', 'FINAL_CHECKIN');
    
    my @lender_status_calls = ();
    $mock_lender_ill_request->mock('status', sub {
        my ($self, $status) = @_;
        push @lender_status_calls, $status if defined $status;
        return $self;
    });
    $mock_lender_ill_request->set_always('store', $mock_lender_ill_request);

    # Test both handle FINAL_CHECKIN without exceptions
    lives_ok { $borrower_actions->handle_from_action($mock_borrower_action) } 
        'Borrower should handle FINAL_CHECKIN without exception';
    
    lives_ok { $lender_actions->handle_from_action($mock_lender_action) } 
        'Lender should handle FINAL_CHECKIN without exception';

    # Test both set the same status
    is($borrower_status_calls[0], 'COMP', 'Borrower should set status to COMP');
    is($lender_status_calls[0], 'COMP', 'Lender should set status to COMP');
    
    # Test consistency
    is($borrower_status_calls[0], $lender_status_calls[0], 
       'Both borrower and lender should set the same status for FINAL_CHECKIN');
    
    # Test both call store
    ok(scalar(@borrower_status_calls) > 0 && scalar(@lender_status_calls) > 0,
       'Both borrower and lender should call status and store methods');
};

done_testing();
