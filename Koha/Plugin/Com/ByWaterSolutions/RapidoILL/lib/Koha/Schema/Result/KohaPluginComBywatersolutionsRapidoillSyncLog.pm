use utf8;
package Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillSyncLog;

=head1 NAME

Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillSyncLog

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table("koha_plugin_com_bywatersolutions_rapidoill_sync_logs");

__PACKAGE__->add_columns(
    "id",
    { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
    "pod",
    { data_type => "varchar", is_nullable => 0, size => 191 },
    "started_at",
    {
        data_type                 => "timestamp",
        datetime_undef_if_invalid => 1,
        is_nullable               => 0,
    },
    "finished_at",
    {
        data_type                 => "timestamp",
        datetime_undef_if_invalid => 1,
        is_nullable               => 1,
    },
    "processed",
    { data_type => "integer", default_value => 0, is_nullable => 0 },
    "created",
    { data_type => "integer", default_value => 0, is_nullable => 0 },
    "updated",
    { data_type => "integer", default_value => 0, is_nullable => 0 },
    "skipped",
    { data_type => "integer", default_value => 0, is_nullable => 0 },
    "errors",
    { data_type => "integer", default_value => 0, is_nullable => 0 },
    "error_details",
    { data_type => "json", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("id");

{
    no warnings 'redefine';

    sub koha_objects_class {
        'RapidoILL::SyncLogs';
    }

    sub koha_object_class {
        'RapidoILL::SyncLog';
    }
}

1;
