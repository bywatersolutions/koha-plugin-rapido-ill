package RapidoILL::StringNormalizer;

# Copyright 2025 ByWater Solutions
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

use List::MoreUtils qw(none);
use RapidoILL::Exceptions;

=head1 RapidoILL::StringNormalizer

String normalizer class.

=head2 Synopsis

    use RapidoILL::StringNormalizer;

    my $n = RapidoILL::StringNormalizer->new( [ 'ltrim', 'trim', 'rtrim', 'remove_all_spaces' ] );
    $string = $n->process($string);
    $string = $n->trim($string);
    $string = $n->ltrim($string);
    $string = $n->rtrim($string);
    $string = $n->remove_all_spaces($string);

=head2 Class methods

=head3 new

Constructor.

=cut

sub new {
    my ( $class, $args ) = @_;

    my $valid_normalizers = available_normalizers();

    foreach my $normalizer ( @{$args} ) {
        RapidoILL::Exception::InvalidStringNormalizer->throw( normalizer => $normalizer )
            if none { $normalizer eq $_ } @{$valid_normalizers};
    }

    my $self = bless( { default_normalizers => $args }, $class );

    return $self;
}

=head3 process

Process the passed string. The default normalizers used when instantiating the
I<RapidoILL::StringNormalizer> class will be used.

=cut

sub process {
    my ( $self, $string ) = @_;

    foreach my $normalizer ( @{ $self->{default_normalizers} } ) {
        $string = $self->$normalizer($string);
    }

    return $string;
}

=head3 ltrim

Trim leading spaces

=cut

sub ltrim {
    my ( $self, $string ) = @_;

    $string =~ s/^\s*//;

    return $string;
}

=head3 rtrim

Trim trailing spaces

=cut

sub rtrim {
    my ( $self, $string ) = @_;

    $string =~ s/\s*$//;

    return $string;
}

=head3 trim

Trim leading and trailing spaces

=cut

sub trim {
    my ( $self, $string ) = @_;

    return $self->ltrim( $self->rtrim($string) );
}

=head3 remove_all_spaces

Remove all spaces.

=cut

sub remove_all_spaces {
    my ( $self, $string ) = @_;

    $string =~ s/\s//g;

    return $string;
}

=head3 available_normalizers

Returns an arrayref of the valid normalizer names. To be used
to validate configuration.

=cut

sub available_normalizers {
    return [
        'ltrim',
        'rtrim',
        'trim',
        'remove_all_spaces',
    ];
}

1;
