use utf8;
package Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillServerStatusLog;

=head1 NAME

Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillServerStatusLog

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<koha_plugin_com_bywatersolutions_rapidoill_server_status_log>

=cut

__PACKAGE__->table("koha_plugin_com_bywatersolutions_rapidoill_server_status_log");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 pod

  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 status_code

  data_type: 'integer'
  is_nullable: 0

=head2 task_id

  data_type: 'integer'
  is_nullable: 1

=head2 action

  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 delay_minutes

  data_type: 'integer'
  is_nullable: 0

=head2 delayed_until

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 affected_task_ids

  data_type: 'text'
  is_nullable: 1

=head2 timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
    "id",
    { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
    "pod",
    { data_type => "varchar", is_nullable => 0, size => 191 },
    "status_code",
    { data_type => "integer", is_nullable => 0 },
    "task_id",
    { data_type => "integer", is_nullable => 1 },
    "action",
    { data_type => "varchar", is_nullable => 1, size => 191 },
    "delay_minutes",
    { data_type => "integer", is_nullable => 0 },
    "delayed_until",
    {
        data_type                 => "timestamp",
        datetime_undef_if_invalid => 1,
        is_nullable               => 0,
    },
    "affected_task_ids",
    { data_type => "text", is_nullable => 1 },
    "timestamp",
    {
        data_type                 => "timestamp",
        datetime_undef_if_invalid => 1,
        default_value             => \"current_timestamp",
        is_nullable               => 0,
    },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

{
    no warnings 'redefine';

    sub koha_objects_class {
        'RapidoILL::ServerStatusLogs';
    }

    sub koha_object_class {
        'RapidoILL::ServerStatusLog';
    }
}

1;
