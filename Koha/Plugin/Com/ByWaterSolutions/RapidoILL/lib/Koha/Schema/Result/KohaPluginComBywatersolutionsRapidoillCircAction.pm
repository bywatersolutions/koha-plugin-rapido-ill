use utf8;
package Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillCircAction;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillCircAction

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<koha_plugin_com_bywatersolutions_rapidoill_circ_actions>

=cut

__PACKAGE__->table("koha_plugin_com_bywatersolutions_rapidoill_circ_actions");

=head1 ACCESSORS

=head2 circ_action_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 pod

  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 author

  data_type: 'longtext'
  is_nullable: 1

=head2 borrowerCode

  accessor: 'borrower_code'
  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 callNumber

  accessor: 'call_number'
  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 circId

  accessor: 'circ_id'
  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 circStatus

  accessor: 'circ_status'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 itemAgencyCode

  accessor: 'item_agency_code'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 itemBarcode

  accessor: 'item_barcode'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 itemId

  accessor: 'item_id'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 lastCircState

  accessor: 'last_circ_state'
  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 191

=head2 lenderCode

  accessor: 'lender_code'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 patronAgencyCode

  accessor: 'patron_agency_code'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 patronId

  accessor: 'patron_id'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 patronName

  accessor: 'patron_name'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 pickupLocation

  accessor: 'pickup_location'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 puaAgencyCode

  accessor: 'pua_agency_code'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 puaLocalServerCode

  accessor: 'pua_local_server_code'
  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 title

  data_type: 'longtext'
  is_nullable: 1

=head2 dateCreated

  accessor: 'date_created'
  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dueDateTime

  accessor: 'due_date_time'
  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 lastUpdated

  accessor: 'last_updated'
  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 needBefore

  accessor: 'need_before'
  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 illrequest_id

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "circ_action_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "pod",
  { data_type => "varchar", is_nullable => 0, size => 191 },
  "author",
  { data_type => "longtext", is_nullable => 1 },
  "borrowerCode",
  {
    accessor => "borrower_code",
    data_type => "varchar",
    is_nullable => 0,
    size => 191,
  },
  "callNumber",
  {
    accessor => "call_number",
    data_type => "varchar",
    is_nullable => 0,
    size => 191,
  },
  "circId",
  {
    accessor => "circ_id",
    data_type => "varchar",
    is_nullable => 0,
    size => 191,
  },
  "circStatus",
  {
    accessor => "circ_status",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "itemAgencyCode",
  {
    accessor => "item_agency_code",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "itemBarcode",
  {
    accessor => "item_barcode",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "itemId",
  {
    accessor => "item_id",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "lastCircState",
  {
    accessor => "last_circ_state",
    data_type => "varchar",
    default_value => "",
    is_nullable => 0,
    size => 191,
  },
  "lenderCode",
  {
    accessor => "lender_code",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "patronAgencyCode",
  {
    accessor => "patron_agency_code",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "patronId",
  {
    accessor => "patron_id",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "patronName",
  {
    accessor => "patron_name",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "pickupLocation",
  {
    accessor => "pickup_location",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "puaAgencyCode",
  {
    accessor => "pua_agency_code",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "puaLocalServerCode",
  {
    accessor => "pua_local_server_code",
    data_type => "varchar",
    is_nullable => 1,
    size => 191,
  },
  "title",
  { data_type => "longtext", is_nullable => 1 },
  "dateCreated",
  {
    accessor    => "date_created",
    data_type   => "integer",
    extra       => { unsigned => 1 },
    is_nullable => 0,
  },
  "dueDateTime",
  {
    accessor    => "due_date_time",
    data_type   => "integer",
    extra       => { unsigned => 1 },
    is_nullable => 1,
  },
  "lastUpdated",
  {
    accessor    => "last_updated",
    data_type   => "integer",
    extra       => { unsigned => 1 },
    is_nullable => 1,
  },
  "needBefore",
  {
    accessor    => "need_before",
    data_type   => "integer",
    extra       => { unsigned => 1 },
    is_nullable => 1,
  },
  "illrequest_id",
  { data_type => "bigint", extra => { unsigned => 1 }, is_nullable => 1 },
  "timestamp",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</circ_action_id>

=back

=cut

__PACKAGE__->set_primary_key("circ_action_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<unique_circ_status_state>

=over 4

=item * L</circId>

=item * L</pod>

=item * L</circStatus>

=item * L</lastCircState>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "unique_circ_status_state",
  ["circId", "pod", "circStatus", "lastCircState"],
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-01 16:17:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7SF6SroO2nsqRDblgPJzkg

{
    no warnings 'redefine';

    sub koha_objects_class {
        'RapidoILL::CircActions';
    }

    sub koha_object_class {
        'RapidoILL::CircAction';
    }
}

1;
