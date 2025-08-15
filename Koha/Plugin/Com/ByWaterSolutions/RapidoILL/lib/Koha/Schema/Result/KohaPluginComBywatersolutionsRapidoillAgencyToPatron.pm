use utf8;
package Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillAgencyToPatron;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillAgencyToPatron

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<koha_plugin_com_bywatersolutions_rapidoill_agency_to_patron>

=cut

__PACKAGE__->table("koha_plugin_com_bywatersolutions_rapidoill_agency_to_patron");

=head1 ACCESSORS

=head2 pod

  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 local_server

  data_type: 'varchar'
  is_nullable: 1
  size: 191

=head2 agency_id

  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 patron_id

  data_type: 'integer'
  is_nullable: 0

=head2 description

  data_type: 'varchar'
  is_nullable: 0
  size: 191

=head2 requires_passcode

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 visiting_checkout_allowed

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "pod",
  { data_type => "varchar", is_nullable => 0, size => 191 },
  "local_server",
  { data_type => "varchar", is_nullable => 1, size => 191 },
  "agency_id",
  { data_type => "varchar", is_nullable => 0, size => 191 },
  "patron_id",
  { data_type => "integer", is_nullable => 0 },
  "description",
  { data_type => "varchar", is_nullable => 0, size => 191 },
  "requires_passcode",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "visiting_checkout_allowed",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
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

=item * L</pod>

=item * L</agency_id>

=back

=cut

__PACKAGE__->set_primary_key("pod", "agency_id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-08-15 13:33:16
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:qi05vtIIBILaidhp6hQg6w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
