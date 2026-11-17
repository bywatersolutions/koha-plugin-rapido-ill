#!/usr/bin/env perl

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
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

# The configuration GUI (templates/admin_gui.tt) reads and writes the YAML in
# the browser, with Koha's js-yaml. These tests run its YAML helpers with node
# and check they agree with YAML::XS, which the plugin uses to read the
# configuration.

use Modern::Perl;

use Test::More tests => 2;
use Test::NoWarnings;

use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use YAML::XS;

my $root     = File::Spec->catdir( dirname(__FILE__), '..' );
my $template = File::Spec->catfile( $root, qw(Koha Plugin Com ByWaterSolutions RapidoILL templates admin_gui.tt) );
my $jsyaml   = File::Spec->catfile(
    $ENV{KOHA_HOME} // '/kohadevbox/koha',
    qw(koha-tmpl intranet-tmpl lib linters js-yaml.min.js)
);
my ($node) = grep { -x $_ } map { File::Spec->catfile( $_, 'node' ) } File::Spec->path;

subtest 'admin GUI YAML helpers agree with YAML::XS' => sub {

    plan skip_all => 'node not found'               unless $node;
    plan skip_all => "js-yaml not found at $jsyaml" unless -f $jsyaml;

    plan tests => 11;

    my $source = <<'EOF';
---
dev03-na:
  base_url: https://dev03-na.alma.exlibrisgroup.com
  server_code: 11747
  default_location:
  default_hold_note: ~
  dev_mode: true
  materials_specified: false
  default_patron_agency: 'NO'
  default_checkin_note: "true"
  max_debt_blocks_holds: 1.50
  task_queue_5xx_delay_minutes: !!int 20
  default_barcode_normalizers:
    - remove_all_spaces
    - upcase
  central_item_type_mapping:
    500: DVD
    200: BOOK
559409814110000041:
  server_code: 559409814110000041
  default_notforloan: -1
01234:
  server_code: 007
12345:
  partners_library_id: CPL
EOF

    my $result = run_helpers($source);

    my $expected = load_xs($source);
    is_deeply( $result->{loaded}, $expected, 'GUI reads the YAML like YAML::XS' );
    is( $result->{loaded}->{559409814110000041}->{server_code}, '559409814110000041', 'Big numbers are not rounded' );
    ok( exists $result->{loaded}->{'01234'}, 'Leading zeros are not read as octal' );
    is_deeply(
        $result->{keys}, [ 'dev03-na', '559409814110000041', '01234', '12345' ],
        'Pods are listed in the source order'
    );

    my $yaml = $result->{yaml};
    is_deeply( load_xs($yaml), $expected, 'YAML::XS reads the GUI output back unchanged' );
    like( $yaml, qr/^559409814110000041:$/m,            'Big numeric pod name is not quoted' );
    like( $yaml, qr/^01234:$/m,                         'Pod name with leading zeros is not quoted' );
    like( $yaml, qr/^  server_code: 007$/m,             'Leading zeros kept in values' );
    like( $yaml, qr/^  default_patron_agency: NO$/m,    'Strings YAML 1.1 reads as booleans are not quoted' );
    like( $yaml, qr/^  default_checkin_note: "true"$/m, 'String "true" stays quoted' );
    is_deeply(
        [ $yaml =~ /^([^\s:][^:\n]*):$/mg ], [ 'dev03-na', '559409814110000041', '01234', '12345' ],
        'Pods are written in the source order'
    );
};

sub load_xs {
    my ($yaml) = @_;
    local $YAML::XS::Boolean = 'JSON::PP';
    return YAML::XS::Load($yaml);
}

sub run_helpers {
    my ($source) = @_;

    open my $tt_fh, '<:encoding(UTF-8)', $template or die "Cannot read $template: $!";
    my $tt = do { local $/; <$tt_fh> };
    close $tt_fh;

    my ($helpers) = $tt =~ m{// BEGIN yaml helpers[^\n]*\n(.*?)// END yaml helpers}s
        or die "YAML helpers block not found in $template";

    my $dir = tempdir( CLEANUP => 1 );
    my %file;
    for my $name (qw(helpers.js source.yml runner.js)) {
        $file{$name} = File::Spec->catfile( $dir, $name );
    }

    write_file( $file{'helpers.js'}, $helpers );
    write_file( $file{'source.yml'}, $source );
    write_file( $file{'runner.js'},  <<'EOF' );
const fs = require('fs');
const [ jsyaml_path, helpers_path, source_path ] = process.argv.slice(2);
global.jsyaml = require(jsyaml_path);
const helpers = new Function(
    fs.readFileSync(helpers_path, 'utf8') + '; return { load_yaml, top_level_keys, to_yaml };'
)();
const source = fs.readFileSync(source_path, 'utf8');
const loaded = helpers.load_yaml(source);
const keys   = helpers.top_level_keys(source, loaded);
process.stdout.write( JSON.stringify({ loaded: loaded, keys: keys, yaml: helpers.to_yaml(loaded, keys) }) );
EOF

    open my $out_fh, '-|', $node, $file{'runner.js'}, File::Spec->rel2abs($jsyaml), $file{'helpers.js'},
        $file{'source.yml'}
        or die "Cannot run node: $!";
    my $output = do { local $/; <$out_fh> };
    close $out_fh or die "node failed (exit status $?)";

    return JSON::PP->new->utf8->decode($output);
}

sub write_file {
    my ( $path, $content ) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} $content;
    close $fh;
    return;
}
