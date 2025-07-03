use utf8;
package Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillTaskQueue;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillTaskQueue

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<koha_plugin_com_bywatersolutions_rapidoill_task_queue>

=cut

__PACKAGE__->table("koha_plugin_com_bywatersolutions_rapidoill_task_queue");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 object_type

  data_type: 'enum'
  extra: {list => ["ill","circulation","holds"]}
  is_nullable: 0

=head2 object_id

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 illrequest_id

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 payload

  data_type: 'text'
  is_nullable: 1

=head2 action

  data_type: 'enum'
  extra: {list => ["renewal","checkin","checkout","fill","cancel","b_item_in_transit","b_item_received","o_cancel_request","o_final_checkin","o_item_shipped"]}
  is_nullable: 0

=head2 status

  data_type: 'enum'
  default_value: 'queued'
  extra: {list => ["queued","retry","success","error","skipped"]}
  is_nullable: 0

=head2 attempts

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 last_error

  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=head2 pod

  data_type: 'varchar'
  is_nullable: 0
  size: 10

=head2 run_after

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "object_type",
  {
    data_type => "enum",
    extra => { list => ["ill", "circulation", "holds"] },
    is_nullable => 0,
  },
  "object_id",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "illrequest_id",
  { data_type => "bigint", extra => { unsigned => 1 }, is_nullable => 1 },
  "payload",
  { data_type => "text", is_nullable => 1 },
  "action",
  {
    data_type => "enum",
    extra => {
      list => [
        "renewal",
        "checkin",
        "checkout",
        "fill",
        "cancel",
        "b_item_in_transit",
        "b_item_received",
        "o_cancel_request",
        "o_final_checkin",
        "o_item_shipped",
      ],
    },
    is_nullable => 0,
  },
  "status",
  {
    data_type => "enum",
    default_value => "queued",
    extra => { list => ["queued", "retry", "success", "error", "skipped"] },
    is_nullable => 0,
  },
  "attempts",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "last_error",
  { data_type => "varchar", is_nullable => 1, size => 191 },
  "timestamp",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "pod",
  { data_type => "varchar", is_nullable => 0, size => 10 },
  "run_after",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-07-03 20:44:16
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jKQ2EVufU/vzHNpxs5sEWA


sub koha_objects_class {
    'RapidoILL::QueuedTasks';
}

sub koha_object_class {
    'RapidoILL::QueuedTask';
}

1;
