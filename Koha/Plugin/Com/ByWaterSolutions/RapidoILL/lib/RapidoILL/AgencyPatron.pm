package RapidoILL::AgencyPatron;

use Modern::Perl;

no warnings 'redefine';

use base qw(Koha::Object);

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillAgencyToPatron';
}

1;
