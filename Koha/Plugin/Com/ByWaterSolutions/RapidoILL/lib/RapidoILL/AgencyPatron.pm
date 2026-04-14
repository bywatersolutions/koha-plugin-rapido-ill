package RapidoILL::AgencyPatron;

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

no warnings 'redefine';

use Koha::Database;
use Koha::Patron;
use Koha::Patrons;

use base qw(Koha::Object);

=head1 NAME

RapidoILL::AgencyPatron - Agency-to-patron mapping Object class

=head2 Class methods

=head3 patron

    my $patron = $agency->patron;

Returns the linked Koha::Patron object.

=cut

sub patron {
    my ($self) = @_;
    return Koha::Patrons->find( $self->patron_id );
}

=head3 create_with_patron

    my $agency = RapidoILL::AgencyPatron->create_with_patron(
        {
            pod           => $pod,
            agency_id     => $agency_id,
            description   => $description,
            local_server  => $local_server,
            library_id    => $library_id,
            category_code => $category_code,
            requires_passcode         => 0,
            visiting_checkout_allowed => 0,
        }
    );

Creates a new agency mapping along with its associated patron in a single
transaction. The patron's cardnumber and surname are derived from the agency
fields.

=cut

sub create_with_patron {
    my ( $class, $params ) = @_;

    my $cardnumber = $class->gen_cardnumber($params);
    my $surname    = $class->gen_patron_description($params);

    my $agency;
    Koha::Database->new->schema->txn_do(
        sub {
            my $patron = Koha::Patron->new(
                {
                    branchcode   => $params->{library_id},
                    categorycode => $params->{category_code},
                    surname      => $surname,
                    cardnumber   => $cardnumber,
                    userid       => $cardnumber,
                }
            )->store;

            $agency = $class->new(
                {
                    pod                       => $params->{pod},
                    agency_id                 => $params->{agency_id},
                    patron_id                 => $patron->borrowernumber,
                    description               => $params->{description},
                    local_server              => $params->{local_server},
                    requires_passcode         => $params->{requires_passcode} // 0,
                    visiting_checkout_allowed => $params->{visiting_checkout_allowed} // 0,
                }
            )->store;
        }
    );

    return $agency;
}

=head3 gen_cardnumber

    my $cardnumber = RapidoILL::AgencyPatron->gen_cardnumber(
        { pod => $pod, agency_id => $agency_id }
    );

Generates a deterministic cardnumber for an agency patron.

=cut

sub gen_cardnumber {
    my ( $class, $params ) = @_;
    return 'ILL_' . $params->{pod} . '_' . $params->{agency_id};
}

=head3 gen_patron_description

    my $description = RapidoILL::AgencyPatron->gen_patron_description(
        { description => $description, agency_id => $agency_id }
    );

Generates a patron surname/description for an agency patron.

=cut

sub gen_patron_description {
    my ( $class, $params ) = @_;
    return $params->{description} . ' (' . $params->{agency_id} . ')';
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillAgencyToPatron';
}

1;
