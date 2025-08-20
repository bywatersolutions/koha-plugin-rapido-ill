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

use Test::More tests => 3;
use Test::MockObject;
use Test::Exception;
use JSON::PP;

use_ok('RapidoILL::Backend::BorrowerActions');

subtest 'borrowing workflow with mock API data structure' => sub {
    plan tests => 10;

    # Load mock data structure similar to our mock API
    my $mock_borrowing_workflow = {
        borrowing_initial => {
            circStatus => "CREATED",
            lastCircState => "PATRON_HOLD",
            lenderCode => "famaf",
            borrowerCode => "11747"
        },
        borrowing_shipped => {
            circStatus => "ACTIVE", 
            lastCircState => "ITEM_SHIPPED",
            lenderCode => "famaf",
            borrowerCode => "11747"
        },
        borrowing_received => {
            circStatus => "ACTIVE",
            lastCircState => "ITEM_RECEIVED", 
            lenderCode => "famaf",
            borrowerCode => "11747"
        },
        borrowing_in_transit => {
            circStatus => "ACTIVE",
            lastCircState => "ITEM_IN_TRANSIT",
            lenderCode => "famaf", 
            borrowerCode => "11747"
        },
        borrowing_final_checkin => {
            circStatus => "COMPLETED",
            lastCircState => "FINAL_CHECKIN",
            lenderCode => "famaf",
            borrowerCode => "11747"
        }
    };

    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new();
    my $server_code = "11747";  # We are the borrower

    # Test each step of the workflow
    my @workflow_steps = qw(borrowing_initial borrowing_shipped borrowing_received borrowing_in_transit borrowing_final_checkin);
    my @expected_behaviors = (
        { should_throw => 1, reason => "PATRON_HOLD not handled by borrower" },
        { should_throw => 0, sets_status => 0 },
        { should_throw => 0, sets_status => 0 },
        { should_throw => 0, sets_status => 0 },
        { should_throw => 0, sets_status => 2, status => "COMP", paper_trail => "B_ITEM_CHECKED_IN" }
    );

    for my $i (0 .. $#workflow_steps) {
        my $step = $workflow_steps[$i];
        my $data = $mock_borrowing_workflow->{$step};
        my $expected = $expected_behaviors[$i];

        # Create mock action from API data
        my $mock_action = Test::MockObject->new();
        my $mock_ill_request = Test::MockObject->new();
        
        $mock_action->set_always('ill_request', $mock_ill_request);
        $mock_action->set_always('lastCircState', $data->{lastCircState});
        $mock_action->set_always('lenderCode', $data->{lenderCode});
        $mock_action->set_always('borrowerCode', $data->{borrowerCode});

        my @status_calls = ();
        $mock_ill_request->mock('status', sub {
            my ($self, $status) = @_;
            push @status_calls, $status if defined $status;
            return $self;
        });
        $mock_ill_request->set_always('store', $mock_ill_request);

        # Verify we are the borrower for this data
        is($data->{borrowerCode}, $server_code, 
           "Step $step: We should be the borrower (borrowerCode matches server_code)");

        if ($expected->{should_throw}) {
            throws_ok { $borrower_actions->handle_from_action($mock_action) } 
                'RapidoILL::Exception::UnhandledException',
                "Step $step: Should throw exception for unhandled state";
        } else {
            lives_ok { $borrower_actions->handle_from_action($mock_action) } 
                "Step $step: Should handle $data->{lastCircState} without exception";

            if ($expected->{sets_status}) {
                is(scalar @status_calls, $expected->{sets_status}, 
                   "Step $step: Should make $expected->{sets_status} status calls");
                
                if ($expected->{sets_status} > 0) {
                    is($status_calls[-1], $expected->{status}, 
                       "Step $step: Should end with status $expected->{status}");
                    
                    # Check for paper trail if expected
                    if ($expected->{paper_trail}) {
                        is($status_calls[0], $expected->{paper_trail}, 
                           "Step $step: Should first set $expected->{paper_trail} for paper trail");
                    }
                }
            } else {
                is(scalar @status_calls, 0, 
                   "Step $step: Should not set status");
            }
        }
    }
};

subtest 'FINAL_CHECKIN real data structure validation' => sub {
    plan tests => 8;

    # Test with real data structure from our mock API
    my $real_final_checkin_data = {
        "author" => "Heylin, Clinton",
        "circId" => "CIRC001", 
        "circStatus" => "COMPLETED",
        "lastCircState" => "FINAL_CHECKIN",
        "dateCreated" => "2025-08-15T09:43:56Z",
        "itemBarcode" => "3999900000001",
        "itemId" => "3999900000001",
        "lastUpdated" => "2025-08-15T15:43:56Z",
        "lenderCode" => "famaf",
        "needBefore" => "2025-09-14T11:43:56Z",
        "patronAgencyCode" => "11747",
        "borrowerCode" => "11747",
        "patronId" => "23529000445172",
        "patronName" => "Tanya Daniels",
        "pickupLocation" => "MPL",
        "requestId" => "REQ001",
        "title" => "E Street shuffle"
    };

    my $borrower_actions = RapidoILL::Backend::BorrowerActions->new();
    
    # Create mock action from real API data structure
    my $mock_action = Test::MockObject->new();
    my $mock_ill_request = Test::MockObject->new();
    
    $mock_action->set_always('ill_request', $mock_ill_request);
    $mock_action->set_always('lastCircState', $real_final_checkin_data->{lastCircState});
    $mock_action->set_always('circStatus', $real_final_checkin_data->{circStatus});
    $mock_action->set_always('lenderCode', $real_final_checkin_data->{lenderCode});
    $mock_action->set_always('borrowerCode', $real_final_checkin_data->{borrowerCode});

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

    # Validate data structure
    is($real_final_checkin_data->{lastCircState}, 'FINAL_CHECKIN', 
       'Real data should have FINAL_CHECKIN as lastCircState');
    is($real_final_checkin_data->{circStatus}, 'COMPLETED', 
       'Real data should have COMPLETED as circStatus');
    is($real_final_checkin_data->{borrowerCode}, '11747', 
       'Real data should show us as borrower');

    # Test processing with paper trail
    lives_ok { $borrower_actions->handle_from_action($mock_action) } 
        'Real FINAL_CHECKIN data should be processed without exception';

    is(scalar @status_calls, 2, 
       'Real FINAL_CHECKIN should create paper trail with two status calls');
    is($status_calls[0], 'B_ITEM_CHECKED_IN', 
       'Real FINAL_CHECKIN should first set B_ITEM_CHECKED_IN for paper trail');
    is($status_calls[1], 'COMP', 
       'Real FINAL_CHECKIN should finally set ILL request status to COMP');
    is(scalar @store_calls, 1, 
       'Real FINAL_CHECKIN should call store once to persist both status changes');
};

done_testing();
