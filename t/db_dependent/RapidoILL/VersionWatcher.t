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

use Modern::Perl;

use Test::More tests => 7;
use Test::NoWarnings;
use Test::Exception;
use Test::MockModule;

use C4::Context;
use Koha::Database;

use Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

BEGIN {
    use_ok('RapidoILL::VersionWatcher');
}

my $schema = Koha::Database->schema;
my $dbh    = C4::Context->dbh;

my $plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::RapidoILL';

sub set_db_koha_version {
    my ($version) = @_;
    $dbh->do( q{UPDATE systempreferences SET value = ? WHERE variable = 'Version'}, undef, $version );
}

sub set_installed_plugin_version {
    my ($version) = @_;
    $dbh->do(
        q{DELETE FROM plugin_data WHERE plugin_class = ? AND plugin_key = '__INSTALLED_VERSION__'},
        undef, $plugin_class
    );
    $dbh->do(
        q{INSERT INTO plugin_data (plugin_class, plugin_key, plugin_value) VALUES (?, '__INSTALLED_VERSION__', ?)},
        undef, $plugin_class, $version
    ) if defined $version;
}

subtest '_koha_version_to_num() tests' => sub {

    plan tests => 3;

    is( RapidoILL::VersionWatcher::_koha_version_to_num('26.05.04.000'), '26.0504000', 'Stable version converted' );
    is( RapidoILL::VersionWatcher::_koha_version_to_num('25.11.00.042'), '25.1100042', 'Dev version converted' );
    is( RapidoILL::VersionWatcher::_koha_version_to_num('26.05.00.XXX'), '26.0500999', 'XXX dbrev converted' );
};

subtest 'new() tests' => sub {

    plan tests => 1;

    throws_ok { RapidoILL::VersionWatcher->new( {} ) }
    'RapidoILL::Exception::MissingParameter',
        'Exception thrown when plugin is missing';
};

subtest 'check() Koha version tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $koha = Test::MockModule->new('Koha');
    $koha->mock( 'version', sub { return '26.05.04.000'; } );

    my $plugin = $plugin_class->new;
    set_installed_plugin_version( $plugin->get_metadata->{version} );

    my $watcher = RapidoILL::VersionWatcher->new( { plugin => $plugin, check_interval => 0 } );

    set_db_koha_version('26.0504000');
    my $result = $watcher->check;
    is( $result->{status},  'ok',  'Same Koha version is ok' );
    is( $result->{message}, undef, 'No message when ok' );

    set_db_koha_version('26.0504001');
    $result = $watcher->check;
    is( $result->{status}, 'reload', 'Newer database Koha version requires a reload' );
    like( $result->{message}, qr/loaded: 26\.0504000, database: 26\.0504001/, 'Message has both versions' );

    set_db_koha_version('26.0503999');
    $result = $watcher->check;
    is( $result->{status}, 'wait', 'Older database Koha version (pending update) means wait' );
    like( $result->{message}, qr/code: 26\.0504000, database: 26\.0503999/, 'Message has both versions' );

    $schema->storage->txn_rollback;
};

subtest 'check() plugin version tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $plugin = $plugin_class->new;
    my $loaded = $plugin->get_metadata->{version};

    my $watcher = RapidoILL::VersionWatcher->new( { plugin => $plugin, check_interval => 0 } );

    set_installed_plugin_version($loaded);
    is( $watcher->check->{status}, 'ok', 'Same plugin version is ok' );

    set_installed_plugin_version('999.0.0');
    my $result = $watcher->check;
    is( $result->{status}, 'reload', 'Different installed plugin version requires a reload' );
    like( $result->{message}, qr/loaded: \Q$loaded\E, installed: 999\.0\.0/, 'Message has both versions' );

    set_installed_plugin_version(undef);
    is( $watcher->check->{status}, 'ok', 'Missing installed version is ok' );

    $schema->storage->txn_rollback;
};

subtest 'check() interval tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    my $plugin = $plugin_class->new;
    set_installed_plugin_version( $plugin->get_metadata->{version} );

    my $watcher = RapidoILL::VersionWatcher->new( { plugin => $plugin, check_interval => 3600 } );

    is( $watcher->check->{status}, 'ok', 'First check queries the database' );

    set_installed_plugin_version('999.0.0');
    is( $watcher->check->{status}, 'ok', 'Checks within the interval return the previous result' );

    $watcher->{last_check_time} -= 3600;
    is( $watcher->check->{status}, 'reload', 'Checks after the interval query the database again' );

    $schema->storage->txn_rollback;
};
