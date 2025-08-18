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
use Test::Exception;
use Try::Tiny qw( catch try );

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::Exceptions');
}

subtest 'RapidoILL::Exceptions tests' => sub {
    plan tests => 17;
    
    subtest 'RapidoILL::Exception base class' => sub {
        plan tests => 3;
        
        # Test that the exception can be thrown and caught
        throws_ok { 
            RapidoILL::Exception->throw("Test exception message") 
        } 'RapidoILL::Exception', 'Base exception can be thrown';
        
        # Test inheritance
        my $exception;
        try {
            RapidoILL::Exception->throw("Test message");
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception', 'Exception has correct class');
        isa_ok($exception, 'Koha::Exception', 'Exception inherits from Koha::Exception');
    };
    
    subtest 'RapidoILL::Exception::BadAgencyCode' => sub {
        plan tests => 5;
        
        # Test that the exception can be thrown and caught
        throws_ok { 
            RapidoILL::Exception::BadAgencyCode->throw(
                lenderCode => 'INVALID_LENDER',
                borrowerCode => 'INVALID_BORROWER'
            ) 
        } 'RapidoILL::Exception::BadAgencyCode', 'BadAgencyCode exception can be thrown';
        
        # Test exception properties
        my $exception;
        try {
            RapidoILL::Exception::BadAgencyCode->throw(
                lenderCode => 'INVALID_LENDER',
                borrowerCode => 'INVALID_BORROWER'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::BadAgencyCode', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->lenderCode, 'INVALID_LENDER', 'lenderCode field is set correctly');
        is($exception->borrowerCode, 'INVALID_BORROWER', 'borrowerCode field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::BadConfig' => sub {
        plan tests => 5;
        
        throws_ok { 
            RapidoILL::Exception::BadConfig->throw(
                entry => 'timeout',
                value => 'invalid_timeout'
            ) 
        } 'RapidoILL::Exception::BadConfig', 'BadConfig exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::BadConfig->throw(
                entry => 'timeout',
                value => 'invalid_timeout'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::BadConfig', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->entry, 'timeout', 'entry field is set correctly');
        is($exception->value, 'invalid_timeout', 'value field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::BadParameter' => sub {
        plan tests => 3;
        
        throws_ok { 
            RapidoILL::Exception::BadParameter->throw("Invalid parameters provided") 
        } 'RapidoILL::Exception::BadParameter', 'BadParameter exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::BadParameter->throw("Invalid parameters provided");
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::BadParameter', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
    };
    
    subtest 'RapidoILL::Exception::BadPickupLocation' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::BadPickupLocation->throw(
                value => { invalid => 'structure' }
            ) 
        } 'RapidoILL::Exception::BadPickupLocation', 'BadPickupLocation exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::BadPickupLocation->throw(
                value => { invalid => 'structure' }
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::BadPickupLocation', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is_deeply($exception->value, { invalid => 'structure' }, 'value field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::InconsistentStatus' => sub {
        plan tests => 5;
        
        throws_ok { 
            RapidoILL::Exception::InconsistentStatus->throw(
                expected => 'SHIPPED',
                got => 'PENDING'
            ) 
        } 'RapidoILL::Exception::InconsistentStatus', 'InconsistentStatus exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::InconsistentStatus->throw(
                expected => 'SHIPPED',
                got => 'PENDING'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::InconsistentStatus', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->expected, 'SHIPPED', 'expected field is set correctly');
        is($exception->got, 'PENDING', 'got field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::InvalidPod' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::InvalidPod->throw(
                pod => 'nonexistent-pod'
            ) 
        } 'RapidoILL::Exception::InvalidPod', 'InvalidPod exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::InvalidPod->throw(
                pod => 'nonexistent-pod'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::InvalidPod', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->pod, 'nonexistent-pod', 'pod field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::InvalidStringNormalizer' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::InvalidStringNormalizer->throw(
                normalizer => 'invalid_method'
            ) 
        } 'RapidoILL::Exception::InvalidStringNormalizer', 'InvalidStringNormalizer exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::InvalidStringNormalizer->throw(
                normalizer => 'invalid_method'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::InvalidStringNormalizer', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->normalizer, 'invalid_method', 'normalizer field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::MissingConfigEntry' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::MissingConfigEntry->throw(
                entry => 'base_url'
            ) 
        } 'RapidoILL::Exception::MissingConfigEntry', 'MissingConfigEntry exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::MissingConfigEntry->throw(
                entry => 'base_url'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::MissingConfigEntry', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->entry, 'base_url', 'entry field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::MissingMapping' => sub {
        plan tests => 5;
        
        throws_ok { 
            RapidoILL::Exception::MissingMapping->throw(
                section => 'location_to_library',
                key => 'UNKNOWN_LOCATION'
            ) 
        } 'RapidoILL::Exception::MissingMapping', 'MissingMapping exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::MissingMapping->throw(
                section => 'location_to_library',
                key => 'UNKNOWN_LOCATION'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::MissingMapping', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->section, 'location_to_library', 'section field is set correctly');
        is($exception->key, 'UNKNOWN_LOCATION', 'key field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::MissingParameter' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::MissingParameter->throw(
                param => 'patron_id'
            ) 
        } 'RapidoILL::Exception::MissingParameter', 'MissingParameter exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::MissingParameter->throw(
                param => 'patron_id'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::MissingParameter', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->param, 'patron_id', 'param field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::UnknownItemId' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::UnknownItemId->throw(
                item_id => 12345
            ) 
        } 'RapidoILL::Exception::UnknownItemId', 'UnknownItemId exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::UnknownItemId->throw(
                item_id => 12345
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::UnknownItemId', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->item_id, 12345, 'item_id field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::UnknownBiblioId' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::UnknownBiblioId->throw(
                biblio_id => 67890
            ) 
        } 'RapidoILL::Exception::UnknownBiblioId', 'UnknownBiblioId exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::UnknownBiblioId->throw(
                biblio_id => 67890
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::UnknownBiblioId', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->biblio_id, 67890, 'biblio_id field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::UnknownPatronId' => sub {
        plan tests => 4;
        
        throws_ok { 
            RapidoILL::Exception::UnknownPatronId->throw(
                patron_id => 'UNKNOWN123'
            ) 
        } 'RapidoILL::Exception::UnknownPatronId', 'UnknownPatronId exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::UnknownPatronId->throw(
                patron_id => 'UNKNOWN123'
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::UnknownPatronId', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->patron_id, 'UNKNOWN123', 'patron_id field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::UnhandledException' => sub {
        plan tests => 3;
        
        throws_ok { 
            RapidoILL::Exception::UnhandledException->throw("Unexpected error occurred") 
        } 'RapidoILL::Exception::UnhandledException', 'UnhandledException exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::UnhandledException->throw("Unexpected error occurred");
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::UnhandledException', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
    };
    
    subtest 'RapidoILL::Exception::RequestFailed' => sub {
        plan tests => 5;
        
        my $mock_response = { status => 500, content => 'Internal Server Error' };
        throws_ok { 
            RapidoILL::Exception::RequestFailed->throw(
                method => 'POST',
                response => $mock_response
            ) 
        } 'RapidoILL::Exception::RequestFailed', 'RequestFailed exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::RequestFailed->throw(
                method => 'POST',
                response => $mock_response
            );
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::RequestFailed', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
        is($exception->method, 'POST', 'method field is set correctly');
        is_deeply($exception->response, $mock_response, 'response field is set correctly');
    };
    
    subtest 'RapidoILL::Exception::OAuth2::AuthError' => sub {
        plan tests => 3;
        
        throws_ok { 
            RapidoILL::Exception::OAuth2::AuthError->throw("Authentication failed") 
        } 'RapidoILL::Exception::OAuth2::AuthError', 'OAuth2::AuthError exception can be thrown';
        
        my $exception;
        try {
            RapidoILL::Exception::OAuth2::AuthError->throw("Authentication failed");
        }
        catch {
            $exception = $_;
        };
        isa_ok($exception, 'RapidoILL::Exception::OAuth2::AuthError', 'Exception has correct class');
        isa_ok($exception, 'RapidoILL::Exception', 'Exception inherits from base RapidoILL::Exception');
    };
};

done_testing();
