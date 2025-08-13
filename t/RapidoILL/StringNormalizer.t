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

BEGIN {
    # Add the plugin lib to @INC
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::StringNormalizer');
}

subtest 'StringNormalizer tests' => sub {
    plan tests => 8;
    
    subtest 'Constructor and validation' => sub {
        plan tests => 6;
        
        # Test valid normalizers
        my $normalizer;
        lives_ok { $normalizer = RapidoILL::StringNormalizer->new(['trim']) } 
            'Constructor with valid normalizer succeeds';
        isa_ok($normalizer, 'RapidoILL::StringNormalizer', 'Object has correct class');
        
        lives_ok { $normalizer = RapidoILL::StringNormalizer->new(['ltrim', 'rtrim', 'trim', 'remove_all_spaces']) } 
            'Constructor with all valid normalizers succeeds';
        
        # Test invalid normalizers
        throws_ok { RapidoILL::StringNormalizer->new(['invalid_normalizer']) } 
            'RapidoILL::Exception::InvalidStringNormalizer',
            'Constructor throws exception for invalid normalizer';
        
        throws_ok { RapidoILL::StringNormalizer->new(['trim', 'invalid_normalizer']) } 
            'RapidoILL::Exception::InvalidStringNormalizer',
            'Constructor throws exception when one normalizer is invalid';
        
        # Test empty normalizers
        lives_ok { $normalizer = RapidoILL::StringNormalizer->new([]) } 
            'Constructor with empty normalizers array succeeds';
    };
    
    subtest 'available_normalizers method' => sub {
        plan tests => 6;
        
        my $available = RapidoILL::StringNormalizer::available_normalizers();
        
        is(ref $available, 'ARRAY', 'available_normalizers returns arrayref');
        is(scalar @$available, 4, 'Returns 4 normalizers');
        
        # Check all expected normalizers are present
        my %normalizers = map { $_ => 1 } @$available;
        ok(exists $normalizers{'ltrim'}, 'ltrim normalizer available');
        ok(exists $normalizers{'rtrim'}, 'rtrim normalizer available');
        ok(exists $normalizers{'trim'}, 'trim normalizer available');
        ok(exists $normalizers{'remove_all_spaces'}, 'remove_all_spaces normalizer available');
    };
    
    subtest 'ltrim method' => sub {
        plan tests => 6;
        
        my $normalizer = RapidoILL::StringNormalizer->new([]);
        
        is($normalizer->ltrim('   hello world   '), 'hello world   ', 'ltrim removes leading spaces');
        is($normalizer->ltrim("\t\n  hello world"), 'hello world', 'ltrim removes leading whitespace');
        is($normalizer->ltrim('hello world   '), 'hello world   ', 'ltrim preserves trailing spaces');
        is($normalizer->ltrim('hello world'), 'hello world', 'ltrim unchanged when no leading spaces');
        is($normalizer->ltrim('   '), '', 'ltrim removes all spaces when string is only spaces');
        is($normalizer->ltrim(''), '', 'ltrim handles empty string');
    };
    
    subtest 'rtrim method' => sub {
        plan tests => 6;
        
        my $normalizer = RapidoILL::StringNormalizer->new([]);
        
        is($normalizer->rtrim('   hello world   '), '   hello world', 'rtrim removes trailing spaces');
        is($normalizer->rtrim("hello world\t\n  "), 'hello world', 'rtrim removes trailing whitespace');
        is($normalizer->rtrim('   hello world'), '   hello world', 'rtrim preserves leading spaces');
        is($normalizer->rtrim('hello world'), 'hello world', 'rtrim unchanged when no trailing spaces');
        is($normalizer->rtrim('   '), '', 'rtrim removes all spaces when string is only spaces');
        is($normalizer->rtrim(''), '', 'rtrim handles empty string');
    };
    
    subtest 'trim method' => sub {
        plan tests => 6;
        
        my $normalizer = RapidoILL::StringNormalizer->new([]);
        
        is($normalizer->trim('   hello world   '), 'hello world', 'trim removes leading and trailing spaces');
        is($normalizer->trim("\t\n  hello world\t\n  "), 'hello world', 'trim removes leading and trailing whitespace');
        is($normalizer->trim('hello world'), 'hello world', 'trim unchanged when no leading/trailing spaces');
        is($normalizer->trim('   hello   world   '), 'hello   world', 'trim preserves internal spaces');
        is($normalizer->trim('   '), '', 'trim removes all spaces when string is only spaces');
        is($normalizer->trim(''), '', 'trim handles empty string');
    };
    
    subtest 'remove_all_spaces method' => sub {
        plan tests => 6;
        
        my $normalizer = RapidoILL::StringNormalizer->new([]);
        
        is($normalizer->remove_all_spaces('   hello world   '), 'helloworld', 'remove_all_spaces removes all spaces');
        is($normalizer->remove_all_spaces("hello\t\nworld"), 'helloworld', 'remove_all_spaces removes all whitespace');
        is($normalizer->remove_all_spaces('hello world'), 'helloworld', 'remove_all_spaces removes internal spaces');
        is($normalizer->remove_all_spaces('helloworld'), 'helloworld', 'remove_all_spaces unchanged when no spaces');
        is($normalizer->remove_all_spaces('   '), '', 'remove_all_spaces removes all spaces when string is only spaces');
        is($normalizer->remove_all_spaces(''), '', 'remove_all_spaces handles empty string');
    };
    
    subtest 'process method with single normalizer' => sub {
        plan tests => 4;
        
        my $trim_normalizer = RapidoILL::StringNormalizer->new(['trim']);
        is($trim_normalizer->process('   hello world   '), 'hello world', 'process with trim normalizer works');
        
        my $ltrim_normalizer = RapidoILL::StringNormalizer->new(['ltrim']);
        is($ltrim_normalizer->process('   hello world   '), 'hello world   ', 'process with ltrim normalizer works');
        
        my $rtrim_normalizer = RapidoILL::StringNormalizer->new(['rtrim']);
        is($rtrim_normalizer->process('   hello world   '), '   hello world', 'process with rtrim normalizer works');
        
        my $remove_spaces_normalizer = RapidoILL::StringNormalizer->new(['remove_all_spaces']);
        is($remove_spaces_normalizer->process('   hello world   '), 'helloworld', 'process with remove_all_spaces normalizer works');
    };
    
    subtest 'process method with multiple normalizers' => sub {
        plan tests => 5;
        
        # Test chaining: ltrim then rtrim should equal trim
        my $ltrim_rtrim = RapidoILL::StringNormalizer->new(['ltrim', 'rtrim']);
        is($ltrim_rtrim->process('   hello world   '), 'hello world', 'ltrim + rtrim equals trim');
        
        # Test trim then remove_all_spaces
        my $trim_remove = RapidoILL::StringNormalizer->new(['trim', 'remove_all_spaces']);
        is($trim_remove->process('   hello world   '), 'helloworld', 'trim + remove_all_spaces works');
        
        # Test all normalizers in sequence
        my $all_normalizers = RapidoILL::StringNormalizer->new(['ltrim', 'rtrim', 'remove_all_spaces']);
        is($all_normalizers->process('   hello world   '), 'helloworld', 'all normalizers in sequence work');
        
        # Test empty normalizers array
        my $no_normalizers = RapidoILL::StringNormalizer->new([]);
        is($no_normalizers->process('   hello world   '), '   hello world   ', 'empty normalizers array leaves string unchanged');
        
        # Test order matters: remove_all_spaces then trim vs trim then remove_all_spaces
        my $remove_then_trim = RapidoILL::StringNormalizer->new(['remove_all_spaces', 'trim']);
        is($remove_then_trim->process('   hello world   '), 'helloworld', 'remove_all_spaces + trim works (order test)');
    };
};

done_testing();
