package RapidoILL::VersionWatcher;

# Copyright 2026 ByWater Solutions
#
# This file is part of The Rapido ILL plugin.
#
# The Rapido ILL plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The Rapido ILL plugin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Rapido ILL plugin; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use C4::Context;
use Koha;

use RapidoILL::Exceptions;

=head1 RapidoILL::VersionWatcher

Detects when the Koha or plugin code loaded by a long-running process no
longer matches what is installed.

A daemon loads Koha and the plugin once, at startup. After a Koha upgrade the
database schema moves on (e.g. dropped columns) while the daemon keeps running
the old code, so every query on a changed table fails. The same happens after a
plugin upgrade. This class records the versions loaded at construction time and
compares them against the versions recorded in the database.

=head2 Synopsis

    use RapidoILL::VersionWatcher;

    my $watcher = RapidoILL::VersionWatcher->new( { plugin => $plugin } );

    my $result = $watcher->check;
    if ( $result->{status} eq 'reload' ) {
        # the loaded code is outdated: exit and let the supervisor restart us
    } elsif ( $result->{status} eq 'wait' ) {
        # Koha files were upgraded but the database update hasn't run yet
    }

=head2 Class methods

=head3 new

    my $watcher = RapidoILL::VersionWatcher->new(
        {
            plugin         => $plugin,
          [ check_interval => 60, ]
        }
    );

Constructor. Records the Koha and plugin versions loaded in memory.

Parameters:

=over

=item B<plugin>: a I<Koha::Plugin::Com::ByWaterSolutions::RapidoILL> object (mandatory).

=item B<check_interval>: minimum number of seconds between database lookups. Calls
to I<check> made sooner return the previous result. Defaults to 60. Use 0 to
always query.

=back

=cut

sub new {
    my ( $class, $params ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'plugin' )
        unless $params->{plugin};

    my $self = {
        plugin                => $params->{plugin},
        check_interval        => $params->{check_interval} // 60,
        loaded_koha_version   => _koha_version_to_num( Koha::version() ),
        loaded_plugin_version => $params->{plugin}->get_metadata->{version},
        last_check_time       => undef,
        last_result           => undef,
    };

    return bless $self, $class;
}

=head3 check

    my $result = $watcher->check;

Compares the loaded versions against the installed ones. Returns a hashref
with the following keys:

=over

=item B<status>: one of

=over

=item I<ok>: the loaded code matches what is installed.

=item I<reload>: the database Koha version is newer than the loaded Koha code,
or the installed plugin version differs from the loaded plugin code. The
process should exit so it gets restarted with the new code.

=item I<wait>: the loaded Koha code is newer than the database, meaning the Koha
files were upgraded but the database update hasn't run yet. Work that touches
the database should be held off until it does.

=back

=item B<message>: a human-readable explanation, undef when the status is I<ok>.

=back

=cut

sub check {
    my ($self) = @_;

    my $now = time;
    return $self->{last_result}
        if $self->{last_result}
        && defined $self->{last_check_time}
        && $now - $self->{last_check_time} < $self->{check_interval};

    $self->{last_check_time} = $now;
    $self->{last_result}     = $self->_compare_versions;

    return $self->{last_result};
}

=head2 Internal methods

=head3 _compare_versions

Queries the installed versions and builds the I<check> result.

=cut

sub _compare_versions {
    my ($self) = @_;

    my $db_koha_version = $self->_db_koha_version;
    my $loaded_koha     = $self->{loaded_koha_version};

    if ( $db_koha_version > $loaded_koha ) {
        return {
            status  => 'reload',
            message => "Koha has been upgraded (loaded: $loaded_koha, database: $db_koha_version)",
        };
    }

    if ( $db_koha_version < $loaded_koha ) {
        return {
            status  => 'wait',
            message => "Koha database update pending (code: $loaded_koha, database: $db_koha_version)",
        };
    }

    # Koha::Plugins::Base->new rewrites __INSTALLED_VERSION__ with the version of
    # whatever plugin code instantiates it, so any difference means the plugin files
    # changed under us. Our own restart puts it back in sync.
    my $installed_plugin = $self->_installed_plugin_version;
    my $loaded_plugin    = $self->{loaded_plugin_version};

    if ( defined $installed_plugin && $installed_plugin ne $loaded_plugin ) {
        return {
            status  => 'reload',
            message => "RapidoILL plugin version changed (loaded: $loaded_plugin, installed: $installed_plugin)",
        };
    }

    return { status => 'ok', message => undef };
}

=head3 _db_koha_version

Returns the Koha version recorded in the database, in numeric form. Reads the
table directly as I<C4::Context-E<gt>preference> is cached.

=cut

sub _db_koha_version {
    my ($self) = @_;

    my ($version) =
        C4::Context->dbh->selectrow_array(q{SELECT value FROM systempreferences WHERE variable = 'Version'});

    return $version // 0;
}

=head3 _installed_plugin_version

Returns the plugin version recorded in the database, read directly to avoid
any caching.

=cut

sub _installed_plugin_version {
    my ($self) = @_;

    my ($version) = C4::Context->dbh->selectrow_array(
        q{SELECT plugin_value FROM plugin_data WHERE plugin_class = ? AND plugin_key = '__INSTALLED_VERSION__'},
        undef, ref $self->{plugin}
    );

    return $version;
}

=head3 _koha_version_to_num

    my $num = _koha_version_to_num('26.05.04.000');    # 26.0504000

Converts a Koha code version into the numeric form stored in the I<Version>
system preference. Same as I<C4::Installer::TransformToNum>, which isn't
available on every supported Koha version.

=cut

sub _koha_version_to_num {
    my ($version) = @_;

    $version =~ s/(.*\..*)\.(.*)\.(.*)/$1$2$3/;
    $version =~ s/XXX$/999/;

    return $version;
}

1;
