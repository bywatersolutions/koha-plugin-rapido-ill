#!/usr/bin/env perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Getopt::Long;
use YAML::XS;
use Try::Tiny qw(catch try);

use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $dump;
my $load;
my $file;
my $force;
my $help;

my $result = GetOptions(
    'dump'   => \$dump,
    'load'   => \$load,
    'file=s' => \$file,
    'force'  => \$force,
    'help'   => \$help,
);

unless ($result) {
    print_usage();
    say STDERR "Invalid options provided";
    exit 1;
}

if ($help) {
    print_usage();
    exit 0;
}

unless ( $dump || $load ) {
    print_usage();
    say STDERR "Either --dump or --load must be specified";
    exit 1;
}

if ( $dump && $load ) {
    print_usage();
    say STDERR "--dump and --load are mutually exclusive";
    exit 1;
}

my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new;

if ($dump) {
    dump_configuration( $plugin, $file );
} elsif ($load) {
    load_configuration( $plugin, $file, $force );
}

sub dump_configuration {
    my ( $plugin, $file ) = @_;

    my $config_yaml = $plugin->retrieve_data('configuration') || '';

    if ($file) {
        open my $fh, '>', $file or die "Cannot open file '$file' for writing: $!";
        print $fh $config_yaml;
        close $fh;
        say "Configuration dumped to '$file'";
    } else {
        print $config_yaml;
    }
}

sub load_configuration {
    my ( $plugin, $file, $force ) = @_;

    my $yaml_content;

    if ($file) {
        open my $fh, '<', $file or die "Cannot open file '$file' for reading: $!";
        local $/;
        $yaml_content = <$fh>;
        close $fh;
    } else {
        local $/;
        $yaml_content = <STDIN>;
    }

    # Validate YAML syntax
    try {
        YAML::XS::Load($yaml_content);
    } catch {
        die "Invalid YAML syntax: $_";
    };

    # Store configuration temporarily for validation
    my $original_config = $plugin->retrieve_data('configuration');
    $plugin->store_data( { configuration => $yaml_content } );

    # Clear cached configuration to force reload
    $plugin->store_data( { cached_configuration => undef } );

    # Validate configuration structure
    my $errors = $plugin->check_configuration();

    if ( @$errors && !$force ) {

        # Restore original configuration
        $plugin->store_data( { configuration        => $original_config } );
        $plugin->store_data( { cached_configuration => undef } );

        say STDERR "Configuration validation failed:";
        for my $error (@$errors) {
            say STDERR "  - $error";
        }
        say STDERR "\nUse --force to override validation errors.";
        exit 1;
    }

    if ( @$errors && $force ) {
        say STDERR "Configuration validation warnings (forced):";
        for my $error (@$errors) {
            say STDERR "  - $error";
        }
    }

    say $file ? "Configuration loaded from '$file'" : "Configuration loaded from STDIN";

    if ( @$errors && $force ) {
        say STDERR "Configuration stored despite validation errors.";
    }
}

sub print_usage {
    print <<_USAGE_;

This script manages the YAML configuration for the Rapido ILL plugin.

Usage:
    config.pl --dump [--file filename]           # Dump current configuration
    config.pl --load [--file filename] [--force] # Load configuration

Options:
    --dump                 Dump current plugin configuration to STDOUT or file
    --load                 Load configuration from STDIN or file
    --file filename        File to read from or write to (optional)
    --force                Override configuration validation errors
    --help                 Show this help message

Examples:
    # Dump configuration to console
    config.pl --dump

    # Dump configuration to file
    config.pl --dump --file config.yaml

    # Load configuration from file
    config.pl --load --file config.yaml

    # Load configuration from STDIN
    cat config.yaml | config.pl --load

    # Force load configuration despite validation errors
    config.pl --load --file config.yaml --force

_USAGE_
}

1;
