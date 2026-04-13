package RapidoILL::AgencyPatrons;

use Modern::Perl;

no warnings 'redefine';

use RapidoILL::AgencyPatron;

use base qw(Koha::Objects);

sub _type {
    return 'KohaPluginComBywatersolutionsRapidoillAgencyToPatron';
}

sub object_class {
    return 'RapidoILL::AgencyPatron';
}

1;
