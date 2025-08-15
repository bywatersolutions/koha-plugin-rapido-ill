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

use Test::More tests => 5;
use File::Spec;
use File::Basename;

BEGIN {
    use_ok('RapidoILL::Backend');
}

subtest 'Status graph structure and methods' => sub {
    # Get the status graph from the Backend class
    my $status_graph = RapidoILL::Backend->status_graph();
    
    ok($status_graph, "Status graph exists");
    ok(ref($status_graph) eq 'HASH', "Status graph is a hash reference");
    
    # Find all nodes with assigned methods
    my @nodes_with_methods = ();
    my @all_methods = ();
    
    foreach my $node_id (keys %$status_graph) {
        my $node = $status_graph->{$node_id};
        if ($node->{method} && $node->{method} ne q{}) {
            push @nodes_with_methods, {
                id => $node_id,
                method => $node->{method},
                ui_method_name => $node->{ui_method_name} || '',
            };
            push @all_methods, $node->{method};
        }
    }
    
    ok(scalar(@nodes_with_methods) > 0, "Found nodes with assigned methods");
    
    # Test that we found the expected number of methods
    my @unique_methods = do { my %seen; grep { !$seen{$_}++ } @all_methods };
    cmp_ok(scalar(@unique_methods), '>=', 5, "Found at least 5 unique methods in status graph");
    
    # Store the methods for use in other subtests
    $main::status_graph_methods = \@unique_methods;
    $main::nodes_with_methods = \@nodes_with_methods;
    
    # Display found methods for debugging
    note("Found methods in status graph:");
    foreach my $method (@unique_methods) {
        note("  - $method");
    }
    
    plan tests => 4;
};

subtest 'Backend implements all status graph methods' => sub {
    my @methods = @{$main::status_graph_methods || []};
    
    plan tests => scalar(@methods) + 1;
    
    ok(scalar(@methods) > 0, "Have methods to test from status graph");
    
    # Get the Backend source file to check method definitions
    my $backend_file = File::Spec->catfile(
        dirname(__FILE__), '..', 
        'Koha', 'Plugin', 'Com', 'ByWaterSolutions', 'RapidoILL', 
        'lib', 'RapidoILL', 'Backend.pm'
    );
    
    open my $fh, '<', $backend_file or die "Cannot open Backend.pm: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Test that each method from status graph is implemented
    foreach my $method (@methods) {
        like($content, qr/^sub $method\s*\{/m, "Backend implements $method method (from status graph)");
    }
};

subtest 'Template files exist for UI methods' => sub {
    my @nodes = @{$main::nodes_with_methods || []};
    
    # Get the template directory path
    my $template_dir = File::Spec->catdir(
        dirname(__FILE__), '..', 
        'Koha', 'Plugin', 'Com', 'ByWaterSolutions', 'RapidoILL', 
        'templates', 'intra-includes'
    );
    
    ok(-d $template_dir, "Template directory exists");
    
    # Find methods that have UI method names (indicating they're UI actions)
    my @ui_methods = ();
    foreach my $node (@nodes) {
        if ($node->{ui_method_name} && $node->{ui_method_name} ne q{}) {
            push @ui_methods, $node->{method};
        }
    }
    
    plan tests => scalar(@ui_methods) + 1;
    
    # Test that template files exist for UI methods
    foreach my $method (@ui_methods) {
        my $template_file = File::Spec->catfile($template_dir, "$method.inc");
        
        if (-f $template_file) {
            ok(-f $template_file, "Template file exists for UI method $method: $method.inc");
        } else {
            # Some methods might not need templates (they handle UI internally)
            # Check if the method references a template in the code
            my $backend_file = File::Spec->catfile(
                dirname(__FILE__), '..', 
                'Koha', 'Plugin', 'Com', 'ByWaterSolutions', 'RapidoILL', 
                'lib', 'RapidoILL', 'Backend.pm'
            );
            
            open my $fh, '<', $backend_file or die "Cannot open Backend.pm: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            if ($content =~ /template.*=>.*['"]$method['"]/) {
                fail("Template file missing for UI method $method (referenced in code)");
            } else {
                pass("UI method $method does not require template file (not referenced in code)");
            }
        }
    }
};

subtest 'Template references in Backend code match existing files' => sub {
    # Get the Backend source file
    my $backend_file = File::Spec->catfile(
        dirname(__FILE__), '..', 
        'Koha', 'Plugin', 'Com', 'ByWaterSolutions', 'RapidoILL', 
        'lib', 'RapidoILL', 'Backend.pm'
    );
    
    open my $fh, '<', $backend_file or die "Cannot open Backend.pm: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Find all template references in the code (more precise regex)
    my @template_refs = ();
    while ($content =~ /template\s*=>\s*['"]([^'"]+)['"]/g) {
        push @template_refs, $1;
    }
    
    # Remove duplicates
    my %seen;
    @template_refs = grep { !$seen{$_}++ } @template_refs;
    
    plan tests => scalar(@template_refs) + 1;
    
    ok(scalar(@template_refs) > 0, "Found template references in Backend code");
    
    # Get the template directory path
    my $template_dir = File::Spec->catdir(
        dirname(__FILE__), '..', 
        'Koha', 'Plugin', 'Com', 'ByWaterSolutions', 'RapidoILL', 
        'templates', 'intra-includes'
    );
    
    # Test that each referenced template file exists
    foreach my $template_name (@template_refs) {
        my $template_file = File::Spec->catfile($template_dir, "$template_name.inc");
        if (-f $template_file) {
            ok(-f $template_file, "Template file exists for code reference: $template_name.inc");
        } else {
            fail("Template file missing for code reference: $template_name.inc");
            note("Expected template file: $template_file");
        }
    }
};
