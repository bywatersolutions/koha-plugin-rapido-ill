package Koha::Plugin::Com::ByWaterSolutions::RapidoILL;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use DDP;
use Encode;
use List::MoreUtils qw(any);
use Module::Metadata;
use Mojo::JSON qw(decode_json encode_json);
use Try::Tiny;
use YAML::XS;

use C4::Context;
use C4::Biblio      qw(AddBiblio);
use C4::Circulation qw(AddIssue AddReturn);
use C4::Reserves    qw(AddReserve CanItemBeReserved);

use Koha::Biblios;
use Koha::Database;
use Koha::ILL::Requests;
use Koha::ILL::Request::Attributes;
use Koha::Items;
use Koha::ItemTypes;
use Koha::Libraries;
use Koha::Logger;
use Koha::Patron::Categories;
use Koha::Patrons;
use Koha::Schema;

require RapidoILL::CircActions;
require RapidoILL::Exceptions;

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;

    require Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillAgencyToPatron;
    require Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillCircAction;
    require Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillTaskQueue;

    # register the additional schema classes
    Koha::Schema->register_class( KohaPluginComBywatersolutionsRapidoillAgencyToPatron =>
            'Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillAgencyToPatron' );
    Koha::Schema->register_class( KohaPluginComBywatersolutionsRapidoillCircAction =>
            'Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillCircAction' );
    Koha::Schema->register_class( KohaPluginComBywatersolutionsRapidoillTaskQueue =>
            'Koha::Schema::Result::KohaPluginComBywatersolutionsRapidoillTaskQueue' );

    # force a refresh of the database handle so that it includes the new classes
    Koha::Database->schema( { new => 1 } );
}

our $VERSION = "1.0.13";

our $metadata = {
    name            => 'RapidoILL',
    author          => 'ByWater Solutions',
    date_authored   => '2025-01-29',
    date_updated    => "1970-01-01",
    minimum_version => '24.05',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Rapido ILL integration plugin',
    namespace       => 'rapidoill',
};

=head1 Koha::Plugin::Com::ByWaterSolutions::RapidoILL

Rapido ILL integration plugin

=head2 Plugin methods

=head3 new

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();

Constructor method for the plugin.

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 logger

Global logger instance for the plugin and its components

=cut

sub logger {
    my ( $self, $category ) = @_;

    # Default to main plugin category if no category specified
    $category //= 'rapidoill';

    # Initialize loggers hashref if it doesn't exist
    $self->{_loggers} //= {};

    unless ( $self->{_loggers}->{$category} ) {

        # Use standard Koha::Logger approach
        $self->{_loggers}->{$category} =
            Koha::Logger->get( { category => $category } );
    }

    return $self->{_loggers}->{$category};
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'templates/configure.tt' } );

    if ( scalar $cgi->param('op') && scalar $cgi->param('op') eq 'cud-save' ) {

        $self->store_data(
            {
                configuration => scalar $cgi->param('configuration'),
            }
        );
    }

    my $errors = $self->check_configuration;

    $template->param(
        errors        => $errors,
        configuration => $self->retrieve_data('configuration'),
    );

    $self->output_html( $template->output() );
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ( $self, $args ) = @_;

    if ( !$self->{_configuration} || $args->{recreate} ) {
        my $configuration;
        eval { $configuration = YAML::XS::Load( Encode::encode_utf8( $self->retrieve_data('configuration') // '' ) ); };
        die($@) if $@;

        foreach my $pod ( keys %{$configuration} ) {

            # Reverse the library_to_location key
            my $library_to_location = $configuration->{$pod}->{library_to_location};
            if ($library_to_location) {
                $configuration->{$pod}->{location_to_library} = {
                    map { $library_to_location->{$_}->{location} => $_ }
                        keys %{$library_to_location}
                };
            }

            $configuration->{$pod}->{debt_blocks_holds}        //= 1;
            $configuration->{$pod}->{max_debt_blocks_holds}    //= 100;
            $configuration->{$pod}->{expiration_blocks_holds}  //= 1;
            $configuration->{$pod}->{restriction_blocks_holds} //= 1;
        }

        $self->{_configuration} = $configuration;
    }

    return $self->{_configuration};
}

=head3 install

Install method. Takes care of table creation and initialization if required

=cut

sub install {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;

    my $task_queue = $self->get_qualified_table_name('task_queue');

    unless ( $self->_table_exists($task_queue) ) {
        $dbh->do(
            qq{
            CREATE TABLE $task_queue (
                `id`            INT(11) NOT NULL AUTO_INCREMENT,
                `object_type`   ENUM('ill', 'circulation', 'holds') NOT NULL,
                `object_id`     INT(11) NOT NULL DEFAULT 0,
                `illrequest_id` BIGINT(20) UNSIGNED NULL DEFAULT NULL,
                `payload`       TEXT DEFAULT NULL,
                `action`        ENUM('checkin','checkout','fill','cancel','b_item_in_transit','b_item_received','b_item_renewal','o_cancel_request','o_final_checkin','o_item_shipped') NOT NULL,
                `status`        ENUM('queued','retry','success','error','skipped') NOT NULL DEFAULT 'queued',
                `attempts`      INT(11) NOT NULL DEFAULT 0,
                `last_error`    VARCHAR(191) DEFAULT NULL,
                `timestamp`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `pod`           VARCHAR(10) NOT NULL,
                `run_after`     TIMESTAMP NULL DEFAULT NULL,
                `context`       TEXT DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `status` (`status`),
                KEY `pod` (`pod`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        }
        );
    }

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    unless ( $self->_table_exists($agency_to_patron) ) {
        $dbh->do(
            qq{
            CREATE TABLE $agency_to_patron (
                `pod`                       VARCHAR(191) NOT NULL,
                `local_server`              VARCHAR(191) NULL DEFAULT NULL,
                `agency_id`                 VARCHAR(191) NOT NULL,
                `patron_id`                 INT(11) NOT NULL,
                `description`               VARCHAR(191) NOT NULL,
                `requires_passcode`         TINYINT(1) NOT NULL DEFAULT 0,
                `visiting_checkout_allowed` TINYINT(1) NOT NULL DEFAULT 0,
                `timestamp`                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`pod`,`agency_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        }
        );
    }

    my $circ_actions = $self->get_qualified_table_name('circ_actions');

    unless ( $self->_table_exists($circ_actions) ) {
        $dbh->do(
            qq{
            CREATE TABLE $circ_actions (
                `circ_action_id`       INT(11) NOT NULL AUTO_INCREMENT,
                `pod`                  VARCHAR(191) NOT NULL,
                `author`               LONGTEXT DEFAULT NULL,
                `borrowerCode`         VARCHAR(191) NOT NULL,
                `callNumber`           VARCHAR(191) NOT NULL,
                `circId`               VARCHAR(191) NOT NULL,
                `circStatus`           VARCHAR(191) NULL DEFAULT NULL,
                `itemAgencyCode`       VARCHAR(191) NULL DEFAULT NULL,
                `itemBarcode`          VARCHAR(191) NULL DEFAULT NULL,
                `itemId`               VARCHAR(191) NULL DEFAULT NULL,
                `lastCircState`        VARCHAR(191) NOT NULL DEFAULT "",
                `lenderCode`           VARCHAR(191) NULL DEFAULT NULL,
                `patronAgencyCode`     VARCHAR(191) NULL DEFAULT NULL,
                `patronId`             VARCHAR(191) NULL DEFAULT NULL,
                `patronName`           VARCHAR(191) NULL DEFAULT NULL,
                `pickupLocation`       VARCHAR(191) NULL DEFAULT NULL,
                `puaAgencyCode`        VARCHAR(191) NULL DEFAULT NULL,
                `puaLocalServerCode`   VARCHAR(191) NULL DEFAULT NULL,
                `title`                LONGTEXT DEFAULT NULL,
                `dateCreated`          INT UNSIGNED NOT NULL,
                `dueDateTime`          INT UNSIGNED NULL,
                `lastUpdated`          INT UNSIGNED NULL DEFAULT NULL,
                `needBefore`           INT UNSIGNED NULL DEFAULT NULL,
                `illrequest_id`        BIGINT(20) UNSIGNED NULL DEFAULT NULL,
                `timestamp`            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`circ_action_id`),
                KEY `circId` (`circId`),
                UNIQUE KEY `unique_circ_status_state` (`circId`, `pod`, `circStatus`, `lastCircState`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        }
        );
    }

    return 1;
}

=head3 upgrade

Takes care of upgrading whatever is needed (table structure, new tables, information on those)

=cut

sub upgrade {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');
    my $task_queue       = $self->get_qualified_table_name('task_queue');
    my $circ_actions     = $self->get_qualified_table_name('circ_actions');

    my $new_version = "0.3.12";
    if ( Koha::Plugins::Base::_version_compare( $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1 ) {

        # Add puaAgencyCode column if it doesn't exist (for existing installations)
        unless ( $self->_column_exists( $circ_actions, 'puaAgencyCode' ) ) {
            $dbh->do(
                "ALTER TABLE $circ_actions
                ADD COLUMN `puaAgencyCode` VARCHAR(191) NULL DEFAULT NULL
                AFTER `pickupLocation`"
            );
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "0.8.0";
    if ( Koha::Plugins::Base::_version_compare( $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1 ) {

        # First, add 'b_item_renewal' to the ENUM (keeping 'renewal' temporarily)
        $dbh->do(
            "ALTER TABLE $task_queue
            MODIFY COLUMN `action` ENUM(
                'checkin',
                'checkout',
                'fill',
                'cancel',
                'b_item_in_transit',
                'b_item_received',
                'renewal',
                'b_item_renewal',
                'o_cancel_request',
                'o_final_checkin',
                'o_item_shipped'
            ) NOT NULL"
        );

        # Then migrate any existing 'renewal' actions to 'b_item_renewal'
        $dbh->do("UPDATE $task_queue SET action = 'b_item_renewal' WHERE action = 'renewal'");

        # Finally, remove 'renewal' from the ENUM
        $dbh->do(
            "ALTER TABLE $task_queue
            MODIFY COLUMN `action` ENUM(
                'checkin',
                'checkout',
                'fill',
                'cancel',
                'b_item_in_transit',
                'b_item_received',
                'b_item_renewal',
                'o_cancel_request',
                'o_final_checkin',
                'o_item_shipped'
            ) NOT NULL"
        );

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    $new_version = "0.9.8";
    if ( Koha::Plugins::Base::_version_compare( $self->retrieve_data('__INSTALLED_VERSION__'), $new_version ) == -1 ) {

        unless ( $self->_column_exists( $task_queue, 'context' ) ) {
            $dbh->do(
                qq{
                ALTER TABLE $task_queue
                ADD COLUMN `context` TEXT DEFAULT NULL
                AFTER `payload`
                }
            );
        }

        $self->store_data( { '__INSTALLED_VERSION__' => $new_version } );
    }

    return 1;
}

=head3 ill_backend

    print $plugin->ill_backend();

Returns a string representing the backend name.

=cut

sub ill_backend {
    my ( $class, $args ) = @_;
    return 'RapidoILL';
}

=head3 new_ill_backend

Required method utilized by I<Koha::ILL::Request> load_backend

=cut

sub new_ill_backend {
    my ( $self, $params ) = @_;

    require RapidoILL::Backend;

    my $args = {
        config => $params->{config},
        logger => $params->{logger},
        plugin => $self,
    };

    return RapidoILL::Backend->new($args);
}

=head3 after_circ_action

Hook that is caled on circulation actions

=cut

sub after_circ_action {
    my ( $self, $params ) = @_;

    my $action   = $params->{action};
    my $checkout = $params->{payload}->{checkout};

    # my $type     = $params->{payload}->{type};

    my $req;

    if ( $action eq 'checkout' )
    {    # we don't have a checkout_id yet. the item has been created by itemshipped so query using the barcode
         # this only applies to the borrowing side. On the lending side all the workflow is handled
         # within the hold cancel/fill actions, which trigger plain cancellation or setting the status as
         # O_ITEM_SHIPPED and generating the checkout right after, inside the same transaction.
        $req = $self->get_ill_requests_from_attribute(
            {
                type  => 'itemBarcode',
                value => $checkout->item->barcode,
            }
        )->search(
            { 'me.status' => [ 'B_ITEM_RECEIVED', 'B_ITEM_RECALLED' ] },
            { order_by    => { '-desc' => 'updated' }, rows => 1, }
        )->single;
    } else {
        $req = $self->get_ill_request_from_attribute(
            {
                type  => 'checkout_id',
                value => $checkout->id,
            }
        );
    }

    return
        unless $req;

    # skip if checkout for another patron.
    return
        if $req->borrowernumber != $checkout->borrowernumber;

    my $pod    = $self->get_req_pod($req);
    my $config = $self->pod_config($pod);

    if ( $action eq 'checkout' ) {

        # FIXME: Should be handled through CirculateILL
        if ( any { $req->status eq $_ } qw{B_ITEM_RECEIVED} ) {
            $self->add_or_update_attributes(
                {
                    request    => $req,
                    attributes => { checkout_id => $checkout->id }
                }
            );
        }
    } elsif ( $action eq 'renewal' ) {

        # Notify renewal
        $self->get_queued_tasks->enqueue(
            {
                object_type   => 'circulation',
                object_id     => $checkout->id,
                action        => 'b_item_renewal',
                pod           => $pod,
                illrequest_id => $req->id,
                payload       => {
                    due_date => $checkout->date_due,
                }
            }
        );

    } elsif ( $action eq 'checkin' ) {

        if (
            any { $req->status eq $_ }
            qw(O_ITEM_CANCELLED
            O_ITEM_CANCELLED_BY_US
            O_ITEM_IN_TRANSIT
            O_ITEM_RETURN_UNCIRCULATED
            O_ITEM_RECEIVED_DESTINATION)
            )
        {
            $self->get_queued_tasks->enqueue(
                {
                    object_type   => 'ill',
                    object_id     => $req->id,
                    action        => 'o_final_checkin',
                    pod           => $pod,
                    illrequest_id => $req->id,
                }
            ) if $config->{lending}->{automatic_final_checkin};
        } elsif ( any { $req->status eq $_ } qw{B_ITEM_RECEIVED B_ITEM_RECALLED} ) {
            $self->get_queued_tasks->enqueue(
                {
                    object_type   => 'ill',
                    object_id     => $req->id,
                    action        => 'b_item_in_transit',
                    pod           => $pod,
                    illrequest_id => $req->id,
                }
            ) if $config->{borrowing}->{automatic_item_in_transit};
        }
    }

    return;
}

=head3 after_hold_action

Hook that is caled on holds-related actions

=cut

sub after_hold_action {
    my ( $self, $params ) = @_;

    my $action = $params->{action};

    my $payload = $params->{payload};
    my $hold    = $payload->{hold};

    my $req = $self->get_ill_request_from_attribute(
        {
            type  => 'hold_id',
            value => $hold->id,
        }
    );

    # skip actions if this is not an ILL request
    return
        unless $req;

    my $pod    = $self->get_req_pod($req);
    my $config = $self->pod_config($pod);

    if ( $self->is_lending_req($req) ) {
        if ( $action eq 'waiting' ) {

            # NOTE: o_item_shipped will trigger a checkout, which will implicitly
            #       fill the hold. We don't want that action on the hold to trigger a
            #       duplicated o_item_shipped.
            #       The 'waiting' case is not picked either, to allow Koha to process
            #       the transfer in a kosher way.
            if ( $req->status eq 'O_ITEM_REQUESTED' ) {

                $self->get_queued_tasks->enqueue(
                    {
                        object_type   => 'ill',
                        object_id     => $req->id,
                        action        => 'o_item_shipped',
                        pod           => $pod,
                        illrequest_id => $req->id,
                    }
                ) if $config->{lending}->{automatic_item_shipped};
            }
        } elsif ( $action eq 'cancel' ) {

            if ( $req->status eq 'O_ITEM_REQUESTED' ) {

                $self->get_queued_tasks->enqueue(
                    {
                        object_type   => 'ill',
                        object_id     => $req->id,
                        action        => 'o_cancel_request',
                        pod           => $pod,
                        illrequest_id => $req->id,
                    }
                );
            }
        }
    } else {
        if (   $action eq 'fill'
            || $action eq 'waiting'
            || $action eq 'transfer' )
        {
            if ( $req->status eq 'B_ITEM_SHIPPED' ) {

                $self->get_queued_tasks->enqueue(
                    {
                        object_type   => 'ill',
                        object_id     => $req->id,
                        action        => 'b_item_received',
                        pod           => $pod,
                        illrequest_id => $req->id,
                    }
                ) if $config->{borrowing}->{automatic_item_receive};
            }
        }
    }
}

=head3 notices_content

Hook that adds data for using in notices.

=cut

sub notices_content {
    my ( $self, $params ) = @_;
    my $result = {};

    if ( $params->{letter_code} =~ m/^HOLD/ ) {

        my $ill_request = $self->get_ill_request_from_attribute(
            {
                type  => 'hold_id',
                value => $params->{tables}->{reserves}->{reserve_id},
            }
        );

        if ($ill_request) {
            $result->{ill_request} = $ill_request;
            my $extended_attributes = $ill_request->extended_attributes->search(
                {
                    type => [
                        qw{
                            author borrowerCode callNumber circ_action_id
                            circId circStatus dateCreated dueDateTime
                            itemAgencyCode itemBarcode itemId lastCircState
                            lastUpdated lenderCode needBefore patronAgencyCode
                            patronId patronName pickupLocation pod
                            puaLocalServerCode title
                        }
                    ]
                }
            );

            while ( my $attr = $extended_attributes->next ) {
                $result->{ $attr->type } = $attr->value
                    if $attr;
            }
        }
    }

    return $result;
}

=head2 Internal methods

=head3 _table_exists (helper)

Method to check if a table exists in Koha.

FIXME: Should be made available to plugins in core

=cut

sub _table_exists {
    my ( $self, $table ) = @_;
    eval {
        C4::Context->dbh->{PrintError} = 0;
        C4::Context->dbh->{RaiseError} = 1;
        C4::Context->dbh->do(qq{SELECT * FROM $table WHERE 1 = 0 });
    };
    return 1 unless $@;
    return 0;
}

=head3 _column_exists (helper)

Method to check if a column exists in a table in Koha.

=cut

sub _column_exists {
    my ( $self, $table, $column ) = @_;
    eval {
        C4::Context->dbh->{PrintError} = 0;
        C4::Context->dbh->{RaiseError} = 1;
        C4::Context->dbh->do(qq{SELECT $column FROM $table WHERE 1 = 0 });
    };
    return 1 unless $@;
    return 0;
}

=head3 api_routes

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_routes_v3

Method that returns the API routes to be merged into Koha's

=cut

sub api_routes_v3 {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapiv3.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 api_namespace

Method that returns the namespace for the plugin API to be put on

=cut

sub api_namespace {
    my ($self) = @_;

    return 'rapidoill';
}

=head3 template_include_paths

Plugin hook used to register paths to find templates

=cut

sub template_include_paths {
    my ($self) = @_;

    return [ $self->mbf_path('templates'), ];
}

=head3 cronjob_nightly

Plugin hook for running nightly tasks

=cut

# sub cronjob_nightly {
#     my ($self) = @_;

#     foreach my $pod ( @{ $self->pods } ) {
#         $self->sync_agencies($pod);
#     }
# }

=head2 Business methods

=head3 add_virtual_record_and_item

    my $item = add_virtual_record_and_item(
        {
            barcode      => $barcode,
            call_number  => $call_number,
            central_code => $central_code,
            req          => $req,
        }
    );

This method is used for adding a virtual (hidden for end-users) MARC record
with an item, so a hold is placed for it. It returns the generated I<Koha::Item> object.

=cut

sub add_virtual_record_and_item {
    my ( $self, $args ) = @_;

    my $barcode     = $args->{barcode};
    my $call_number = $args->{call_number};
    my $config      = $args->{config};
    my $req         = $args->{req};

    # values from configuration
    my $marc_flavour   = C4::Context->preference('marcflavour');      # FIXME: do we need this?
    my $framework_code = $config->{default_marc_framework} || 'FA';
    my $ccode          = $config->{default_item_ccode};
    my $location       = $config->{default_location};
    my $notforloan     = $config->{default_notforloan} // -1;
    my $checkin_note   = $config->{default_checkin_note} || 'Additional processing required (ILL)';
    my $item_type      = $config->{default_item_type} // 'ILL';

    my $materials;

    if ( $config->{materials_specified} ) {
        $materials =
            ( defined $config->{default_materials_specified} )
            ? $config->{default_materials_specified}
            : 'Additional processing required (ILL)';
    }

    my $attributes = $req->extended_attributes;

    my $default_normalizers = $config->{default_barcode_normalizers} // [];
    if ( scalar @{$default_normalizers} ) {
        my $normalizer = $self->get_normalizer($default_normalizers);
        $barcode = $normalizer->process($barcode);
    }

    my $author_attr = $attributes->search( { type => 'author' } )->next;
    my $author      = ($author_attr) ? $author_attr->value : '';
    my $title_attr  = $attributes->search( { type => 'title' } )->next;
    my $title       = ($title_attr) ? $title_attr->value : '';

    RapidoILL::Exception::BadConfig->throw(
        entry => 'marcflavour',
        value => $marc_flavour
    ) unless $marc_flavour eq 'MARC21';

    my $record = MARC::Record->new();
    $record->leader('     nac a22     1u 4500');
    $record->insert_fields_ordered(
        MARC::Field->new( '100', '1', '0', 'a' => $author ),
        MARC::Field->new( '245', '1', '0', 'a' => $title ),
        MARC::Field->new(
            '942', '1', '0',
            'n' => 1,
            'c' => $item_type
        )
    );

    my $item;
    my $schema = Koha::Database->new->schema;
    $schema->txn_do(
        sub {
            my ( $biblio_id, $biblioitemnumber ) = AddBiblio( $record, $framework_code );

            my $item_data = {
                barcode             => $barcode,
                biblioitemnumber    => $biblioitemnumber,
                biblionumber        => $biblio_id,
                ccode               => $ccode,
                holdingbranch       => $req->branchcode,
                homebranch          => $req->branchcode,
                itemcallnumber      => $call_number,
                itemnotes_nonpublic => $checkin_note,
                itype               => $item_type,
                location            => $location,
                materials           => $materials,
                notforloan          => $notforloan,
            };

            $item = Koha::Item->new($item_data)->store;
        }
    );

    return $item;
}

=head3 generate_patron_for_agency

    my $patron = $plugin->generate_patron_for_agency(
        {
            pod          => $pod,
            local_server => $local_server,
            agency_id    => $agency_id,
            description  => $description
        }
    );

Generates a patron representing a library in the consortia that might make
material requests (borrowing site). It is used on the circulation workflow to
place a hold on the requested items.

=cut

sub generate_patron_for_agency {
    my ( $self, $params ) = @_;

    $self->validate_params(
        {
            required => [qw(pod local_server description agency_id requires_passcode visiting_checkout_allowed)],
            params   => $params,
        }
    );

    my $pod                       = $params->{pod};
    my $local_server              = $params->{local_server};
    my $description               = $params->{description};
    my $agency_id                 = $params->{agency_id};
    my $requires_passcode         = $params->{requires_passcode};
    my $visiting_checkout_allowed = $params->{visiting_checkout_allowed};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    my $library_id    = $self->configuration->{$pod}->{partners_library_id};
    my $category_code = $self->configuration->{$pod}->{partners_category};

    my $patron;

    Koha::Database->schema->txn_do(
        sub {
            my $cardnumber = $self->gen_cardnumber(
                {
                    pod          => $pod,
                    local_server => $local_server,
                    description  => $description,
                    agency_id    => $agency_id
                }
            );
            $patron = Koha::Patron->new(
                {
                    branchcode   => $library_id,
                    categorycode => $category_code,
                    surname      => $self->gen_patron_description(
                        {
                            pod          => $pod,
                            local_server => $local_server,
                            description  => $description,
                            agency_id    => $agency_id
                        }
                    ),
                    cardnumber => $cardnumber,
                    userid     => $cardnumber
                }
            )->store;

            my $patron_id = $patron->borrowernumber;

            my $dbh = C4::Context->dbh;
            my $sth = $dbh->prepare(
                qq{
            INSERT INTO $agency_to_patron
              ( pod, local_server, agency_id, patron_id, description, requires_passcode, visiting_checkout_allowed )
            VALUES
              ( '$pod', '$local_server', '$agency_id', '$patron_id', '$description', '$requires_passcode', '$visiting_checkout_allowed' );
        }
            );

            $sth->execute();
        }
    );

    return $patron;
}

=head3 update_patron_for_agency

    my $patron = $plugin->update_patron_for_agency(
        {
            pod          => $pod,
            local_server => $local_server,
            agency_id    => $agency_id,
            description  => $description
        }
    );

Updates a patron representing a library in the consortia that might make
material requests (borrowing site). It is used by cronjobs to keep things up
to date if there are changes on the central server info.

See: scripts/sync_agencies.pl

=cut

sub update_patron_for_agency {
    my ( $self, $params ) = @_;

    $self->validate_params(
        {
            required => [qw(pod local_server description agency_id requires_passcode visiting_checkout_allowed)],
            params   => $params
        }
    );

    my $pod                       = $params->{pod};
    my $local_server              = $params->{local_server};
    my $description               = $params->{description};
    my $agency_id                 = $params->{agency_id};
    my $requires_passcode         = $params->{requires_passcode};
    my $visiting_checkout_allowed = $params->{visiting_checkout_allowed};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

    my $library_id    = $self->configuration->{$pod}->{partners_library_id};
    my $category_code = C4::Context->config("interlibrary_loans")->{partner_code};

    my $patron;

    Koha::Database->schema->txn_do(
        sub {

            my $patron_id = $self->get_patron_id_from_agency(
                {
                    pod       => $pod,
                    agency_id => $agency_id
                }
            );

            $patron = Koha::Patrons->find($patron_id);
            my $cardnumber = $self->gen_cardnumber(
                {
                    pod          => $pod,
                    local_server => $local_server,
                    description  => $description,
                    agency_id    => $agency_id
                }
            );
            $patron->set(
                {
                    surname => $self->gen_patron_description(
                        {
                            pod          => $pod,
                            local_server => $local_server,
                            description  => $description,
                            agency_id    => $agency_id
                        }
                    ),
                    cardnumber => $cardnumber,
                    userid     => $cardnumber,
                }
            )->store;

            my $dbh = C4::Context->dbh;
            my $sth = $dbh->prepare(
                qq{
            UPDATE $agency_to_patron
            SET
              description='$description',
              requires_passcode='$requires_passcode',
              visiting_checkout_allowed='$visiting_checkout_allowed'
            WHERE
                  pod='$pod'
              AND local_server='$local_server'
              AND agency_id='$agency_id'
              }
            );

            $sth->execute();
        }
    );

    return $patron;
}

=head3 get_patron_id_from_agency

    my $patron_id = $plugin->get_patron_id_from_agency(
        {
            pod       => $pod,
            agency_id => $agency_id
        }
    );

Given an agency_id (which usually comes in the patronAgencyCode attribute on the itemhold request)
and a pod code, it returns Koha's patron id so the hold request can be correctly assigned.

=cut

sub get_patron_id_from_agency {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(agency_id pod)], params => $params } );

    my $pod       = $params->{pod};
    my $agency_id = $params->{agency_id};

    my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');
    my $dbh              = C4::Context->dbh;
    my $sth              = $dbh->prepare(
        qq{
        SELECT patron_id
        FROM   $agency_to_patron
        WHERE  agency_id='$agency_id' AND pod='$pod'
    }
    );

    $sth->execute();
    my $result = $sth->fetchrow_hashref;

    unless ($result) {
        return;
    }

    return $result->{patron_id};
}

=head3 gen_patron_description

    my $patron_description = $plugin->gen_patron_description(
        {
            pod          => $pod,
            local_server => $local_server,
            description  => $description,
            agency_id    => $agency_id
        }
    );

This method encapsulates patron description generation based on the provided information.
The idea is that any change on this regard should happen on a single place.

=cut

sub gen_patron_description {
    my ( $self, $args ) = @_;

    my $pod          = $args->{pod};
    my $local_server = $args->{local_server};
    my $description  = $args->{description};
    my $agency_id    = $args->{agency_id};

    return "$description ($agency_id)";
}

=head3 gen_cardnumber

    my $cardnumber = $plugin->gen_cardnumber(
        {
            pod          => $pod,
            local_server => $local_server,
            description  => $description,
            agency_id    => $agency_id
        }
    );

This method encapsulates patron description generation based on the provided information.
The idea is that any change on this regard should happen on a single place.

=cut

sub gen_cardnumber {
    my ( $self, $args ) = @_;

    my $pod          = $args->{pod};
    my $local_server = $args->{local_server};
    my $description  = $args->{description};
    my $agency_id    = $args->{agency_id};

    return 'ILL_' . $pod . '_' . $agency_id;
}

=head3 pods

    my $pods = $self->pods;

=cut

sub pods {
    my ($self) = @_;

    my $configuration = $self->configuration;
    my @pods          = keys %{$configuration};

    return \@pods;
}

=head3 pod_config

    my $config = $plugin->pod_config($pod);

Helper to get the I<$pod> config.

=cut

sub pod_config {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    return $self->configuration->{$pod};
}

=head3 get_ill_request_from_biblio_id

This method retrieves the ILL request using a biblio_id.

=cut

sub get_ill_request_from_biblio_id {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(biblio_id)], params => $params } );

    my $reqs =
        Koha::ILL::Requests->search( { biblio_id => $params->{biblio_id} } );

    if ( $reqs->count > 1 ) {
        $self->logger->warn(
            sprintf(
                "More than one ILL request for the biblio_id (%s). Beware!",
                $params->{biblio_id}
            )
        );
    }

    return unless $reqs->count > 0;

    my $req = $reqs->next;

    return $req;
}

=head3 get_ill_request

This method retrieves the ILL request using the I<circId> and
I<pod> attributes.

=cut

sub get_ill_request {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(circId pod)], params => $params } );

    my $circId = $params->{circId};
    my $pod    = $params->{pod};

    # Get/validate the request
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
        qq{
        SELECT * FROM illrequestattributes AS ra_a
        INNER JOIN    illrequestattributes AS ra_b
        ON ra_a.illrequest_id=ra_b.illrequest_id AND
          (ra_a.type='circId'  AND ra_a.value='$circId') AND
          (ra_b.type='pod' AND ra_b.value='$pod');
    }
    );

    $sth->execute();
    my $result = $sth->fetchrow_hashref;

    my $req;

    $req = Koha::ILL::Requests->find( $result->{illrequest_id} )
        if $result->{illrequest_id};

    return $req;
}

=head3 get_http_client

    my $client = $plugin->get_http_client($pod);

Returns an authenticated HTTP client for the specified pod. The client handles
OAuth2 authentication and provides methods for making HTTP requests to the
Rapido ILL API.

=cut

sub get_http_client {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::APIHttpClient;

    my $configuration = $self->configuration->{$pod};

    unless ( $self->{_http_clients}->{$pod} ) {
        $self->{_http_clients}->{$pod} = RapidoILL::APIHttpClient->new(
            {
                client_id     => $configuration->{client_id},
                client_secret => $configuration->{client_secret},
                base_url      => $configuration->{base_url},
                plugin        => $self,
                pod           => $pod,
            }
        );
    }

    return $self->{_http_clients}->{$pod};
}

=head3 get_ua

    my $client = $plugin->get_ua($pod);

Deprecated method. Use get_http_client() instead.

=cut

sub get_ua {
    my ( $self, $pod ) = @_;
    return $self->get_http_client($pod);
}

=head3 get_client

    my $client = $plugin->get_client($pod);

This method retrieves an API client to contact a I<$pod>.

=cut

sub get_client {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::Client;

    my $configuration = $self->configuration->{$pod};

    unless ( $self->{client}->{$pod} ) {
        $self->{client}->{$pod} = RapidoILL::Client->new(
            {
                pod    => $pod,
                plugin => $self,
            }
        );
    }

    return $self->{client}->{$pod};
}

=head3 get_borrower_actions

    my $borrower_actions = $plugin->get_borrower_actions( $pod );

This method instantiates an action handler for the borrower site.

=cut

sub get_borrower_actions {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::Backend::BorrowerActions;

    unless ( $self->{borrower_actions}->{$pod} ) {
        $self->{borrower_actions}->{$pod} = RapidoILL::Backend::BorrowerActions->new(
            {
                pod    => $pod,
                plugin => $self,
            }
        );
    }

    return $self->{borrower_actions}->{$pod};
}

=head3 get_lender_actions

    my $lender_actions = $plugin->get_lender_actions( $pod );

This method instantiates an action handler for the lender site.

=cut

sub get_lender_actions {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::Backend::LenderActions;

    unless ( $self->{lender_actions}->{$pod} ) {
        $self->{lender_actions}->{$pod} = RapidoILL::Backend::LenderActions->new(
            {
                pod    => $pod,
                plugin => $self,
            }
        );
    }

    return $self->{lender_actions}->{$pod};
}

=head3 get_queued_tasks

    my $queued_tasks = $plugin->get_queued_tasks();

Returns a I<RapidoILL::QueuedTasks> resultset.

=cut

sub get_queued_tasks {
    my ($self) = @_;

    require RapidoILL::QueuedTasks;

    return RapidoILL::QueuedTasks->new;
}

=head3 get_normalizer

=cut

sub get_normalizer {
    my ( $self, $args ) = @_;
    require RapidoILL::StringNormalizer;
    return RapidoILL::StringNormalizer->new($args);
}

=head3 is_lending_req

    if ( $plugin->is_lending_req($req) ) { ... }

Returns true if the passed request is a lending one.

=cut

sub is_lending_req {
    my ( $self, $req ) = @_;

    return ( $req->status =~ /^B_/ ) ? 0 : 1;
}

=head3 get_req_pod

    my $pod = $plugin->get_req_pod( $req );

This method returns the pod code a Koha::ILL::Request is linked to.

=cut

sub get_req_pod {
    my ( $self, $req ) = @_;

    my $attr = $req->extended_attributes->find( { type => 'pod' } );

    return $attr->value
        if $attr;

    return;
}

=head3 get_req_circ_id

    my $circId = $plugin->get_req_circ_id( $req );

This method returns the I<circId> code a Koha::ILL::Request is linked to.

=cut

sub get_req_circ_id {
    my ( $self, $req ) = @_;

    my $attr = $req->extended_attributes->find( { type => 'circId' } );

    return $attr->value
        if $attr;

    return;
}

=head2 Wrappers for Koha functions

This methods deal with changes to the ABI of the underlying methods
across different Koha versions.

=head3 add_issue

    my $checkout = $plugin->add_issue(
        {
            patron  => $patron,
            barcode => $barcode
        }
    );

Wrapper for I<C4::Circulation::AddIssue>.

Parameters:

=over

=item B<patron>: a I<Koha::Patron> object.

=item B<barcode>: a I<string> containing an item barcode.

=back

=cut

sub add_issue {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(barcode patron)], params => $params } );

    return AddIssue( $params->{patron}, $params->{barcode} );
}

=head3 add_return

    $plugin->add_return( { barcode => $barcode } );

Wrapper for I<C4::Circulation::AddReturn>. The return value is the
same as C4::Circulation::AddReturn.

Parameters:

=over

=item B<barcode>: a I<string> containing an item barcode.

=back

=cut

sub add_return {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(barcode)], params => $params } );

    return AddReturn( $params->{barcode} );
}

=head3 add_hold

    my $hold_id = $plugin->add_hold(
        {
            library_id => $library_id,
            patron_id  => $patron_id,
            biblio_id  => $biblio_id,
            notes      => $notes,
            item_id    => $item_id,
        }
    );

Wrapper for I<C4::Reserves::AddReserve>.

Parameters: all AddReserve parameters

=cut

sub add_hold {
    my ( $self, $params ) = @_;

    $self->validate_params(
        {
            required => [qw(library_id patron_id biblio_id item_id)],
            params   => $params
        }
    );

    return AddReserve(
        {
            branchcode       => $params->{library_id},
            borrowernumber   => $params->{patron_id},
            biblionumber     => $params->{biblio_id},
            priority         => 1,
            reservation_date => undef,
            expiration_date  => undef,
            notes            => $params->{notes} // 'Placed by ILL',
            title            => '',
            itemnumber       => $params->{item_id},
            found            => undef,
            itemtype         => undef
        }
    );
}

=head3 check_configuration

    my $errors = $self->check_configuration;

Returns a reference to a list of errors found in configuration.

=cut

sub check_configuration {
    my ($self) = @_;

    my @errors;

    push @errors, { code => 'ILLModule_disabled' }
        unless C4::Context->preference('ILLModule');

    push @errors, { code => 'CirculateILL_enabled' }
        if C4::Context->preference('CirculateILL');

    my $configuration = $self->configuration;
    my @pods          = keys %{$configuration};

    foreach my $pod (@pods) {

        if ( !defined $configuration->{$pod}->{server_code} ) {
            push @errors,
                {
                code  => 'missing_entry',
                value => 'server_code',
                pod   => $pod,
                };
        }

        # partners_library_id
        if ( !exists $configuration->{$pod}->{partners_library_id} ) {
            push @errors,
                {
                code  => 'missing_entry',
                value => 'partners_library_id',
                pod   => $pod,
                };
        } else {
            push @errors,
                {
                code  => 'undefined_partners_library_id',
                value => $configuration->{$pod}->{partners_library_id},
                pod   => $pod
                }
                unless Koha::Libraries->find( $configuration->{$pod}->{partners_library_id} );
        }

        # default_item_type
        if ( !exists $configuration->{$pod}->{default_item_type} ) {
            push @errors,
                {
                code  => 'missing_entry',
                value => 'default_item_type',
                pod   => $pod,
                };
        } else {
            push @errors,
                {
                code  => 'undefined_default_item_type',
                value => $configuration->{$pod}->{default_item_type},
                pod   => $pod
                }
                unless Koha::ItemTypes->find( $configuration->{$pod}->{default_item_type} );
        }

        # partners_category
        if ( !exists $configuration->{$pod}->{partners_category} ) {
            push @errors,
                {
                code  => 'missing_entry',
                value => 'partners_category',
                pod   => $pod,
                };
        } else {
            push @errors,
                {
                code  => 'undefined_partners_category',
                value => $configuration->{$pod}->{partners_category},
                pod   => $pod,
                }
                unless Koha::Patron::Categories->find( $configuration->{$pod}->{partners_category} );
        }
    }

    return \@errors;
}

=head3 get_agencies_list

    my $res = $plugin->get_agencies_list( $pod );

Retrieves defined agencies from a I<pod>.

=cut

sub get_agencies_list {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    return $self->get_client($pod)->locals();
}

=head3 sync_agencies

    my $result = $self->sync_agencies;

Syncs server agencies with the current patron's database. Returns a hashref
with the following structure:

    {
        localCode_1 => {
            agencyCode_1 => {
                description    => "The agency name",
                current_status => no_entry|entry_exists|invalid_entry,
                status         => created|updated
            },
            ...
        },
        ...
    }

=cut

sub sync_agencies {
    my ( $self, $pod ) = @_;

    my $response = $self->get_agencies_list($pod);

    my $result = {};

    foreach my $server ( @{$response} ) {
        my $local_server = $server->{localCode};
        my $agency_list  = $server->{agencyList};

        foreach my $agency ( @{$agency_list} ) {

            my $agency_id                 = $agency->{agencyCode};
            my $description               = $agency->{description};
            my $requires_passcode         = $agency->{requiresPasscode}        ? 1 : 0;
            my $visiting_checkout_allowed = $agency->{visitingCheckoutAllowed} ? 1 : 0;

            $result->{$local_server}->{$agency_id}->{description} =
                $description;

            my $patron_id = $self->get_patron_id_from_agency(
                {
                    pod       => $pod,
                    agency_id => $agency_id,
                }
            );

            my $patron;

            $result->{$local_server}->{$agency_id}->{current_status} =
                'no_entry';

            if ($patron_id) {
                $result->{$local_server}->{$agency_id}->{current_status} =
                    'entry_exists';
                $patron = Koha::Patrons->find($patron_id);
            }

            if ( $patron_id && !$patron ) {

                # cleanup needed!
                $self->logger->warn(
                    "There is a 'agency_to_patron' entry for '$agency_id', but the patron is not present on the DB!");
                my $agency_to_patron = $self->get_qualified_table_name('agency_to_patron');

                my $sth = C4::Context->dbh->prepare(
                    qq{
                    DELETE FROM $agency_to_patron
                    WHERE patron_id='$patron_id';
                }
                );

                $sth->execute();
                $result->{$local_server}->{$agency_id}->{current_status} =
                    'invalid_entry';
            }

            if ($patron) {

                # Update description
                $self->update_patron_for_agency(
                    {
                        agency_id                 => $agency_id,
                        description               => $description,
                        local_server              => $local_server,
                        pod                       => $pod,
                        requires_passcode         => $requires_passcode,
                        visiting_checkout_allowed => $visiting_checkout_allowed,
                    }
                );
                $result->{$local_server}->{$agency_id}->{status} = 'updated';
            } else {

                # Create it
                $self->generate_patron_for_agency(
                    {
                        agency_id                 => $agency_id,
                        description               => $description,
                        local_server              => $local_server,
                        pod                       => $pod,
                        requires_passcode         => $requires_passcode,
                        visiting_checkout_allowed => $visiting_checkout_allowed,
                    }
                );
                $result->{$local_server}->{$agency_id}->{status} = 'created';
            }
        }
    }

    return $result;
}

=head3 sync_circ_requests

    my $results = $self->sync_circ_requests(
        {
            pod       => $pod,
          [ startTime => $startTime,
            endTime   => $endTime,
            state     => $state_array,
            circId    => $circId, ]
        }
    );

Syncs circulation requests from the specified I<pod> and returns processing results.

Optional parameters:
- startTime: Unix timestamp for filtering requests (default: 1700000000)
- endTime: Unix timestamp for filtering requests (default: current time)
- state: Array reference of states to sync (default: ['ACTIVE', 'COMPLETED', 'CANCELED', 'CREATED'])

Returns a hashref with the following structure:

    {
        processed => 5,           # Total requests processed
        created   => 2,           # New ILL requests created
        updated   => 2,           # Existing requests updated
        skipped   => 1,           # Duplicate requests skipped
        errors    => 0,           # Processing errors
        messages  => [            # Detailed processing messages
            {
                type    => 'created',
                circId  => 'CIRC001',
                message => 'Created ILL request 123',
                ill_request_id => 123
            },
            # ... more messages
        ]
    }

=cut

sub sync_circ_requests {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(pod)], params => $params } );

    my $startTime = $params->{startTime} // "1700000000";
    my $endTime   = $params->{endTime}   // time();
    my $state     = $params->{state}     // [ 'ACTIVE', 'COMPLETED', 'CANCELED', 'CREATED' ];

    my $results = {
        processed => 0,
        created   => 0,
        updated   => 0,
        skipped   => 0,
        errors    => 0,
        messages  => [],
    };

    my $reqs = $self->get_client( $params->{pod} )->circulation_requests(
        {
            startTime => $startTime,
            endTime   => $endTime,
            content   => 'verbose',
            state     => $state,
        }
    );

    # Filter by circId if specified
    if ( $params->{circId} ) {
        $reqs = [ grep { $_->{circId} && $_->{circId} eq $params->{circId} } @{$reqs} ];
    }

    $results->{processed} = scalar @{$reqs};

    foreach my $data ( @{$reqs} ) {

        $data->{pod} = $params->{pod};
        my $action = RapidoILL::CircAction->new($data);

        try {

            if ( $self->is_exact_duplicate($action) ) {
                $results->{skipped}++;
                push @{ $results->{messages} }, {
                    type    => 'skipped',
                    circId  => $data->{circId},
                    message => "Duplicate ID"
                };
            } elsif ( $self->is_circ_action_new($action) ) {

                # deal with creation
                my $schema = Koha::Database->new->schema;
                $schema->txn_do(
                    sub {
                        if (   $data->{circStatus} eq 'CANCELED'
                            || $data->{circStatus} eq 'COMPLETED' )
                        {
                            my $msg = sprintf(
                                "A finished request with circStatus='%s' lastCircState='%s' was found with no recorded ILL request.",
                                $data->{circStatus}, $data->{lastCircState}
                            );
                            $self->logger->warn($msg);
                            push @{ $results->{messages} },
                                {
                                type    => 'warning',
                                circId  => $data->{circId},
                                message => $msg
                                };
                        } else {
                            my $req = $self->add_ill_request($action);
                            $action->illrequest_id( $req->id );
                            $action->store();
                            my $msg = sprintf(
                                "New ILL request created: circId=%s, circStatus='%s', lastCircState='%s', ill_request_id=%s",
                                $data->{circId},        $data->{circStatus},
                                $data->{lastCircState}, $req->id
                            );
                            $self->logger->info($msg);
                            $results->{created}++;
                            my $req_id = $req->id;
                            push @{ $results->{messages} },
                                {
                                type           => 'created',
                                circId         => $data->{circId},
                                message        => "Created ILL request $req_id",
                                ill_request_id => $req_id
                                };
                        }
                    }
                );
            } elsif ( my $prev_action = $self->is_circ_action_update($action) ) {

                # this is an update
                my $schema = Koha::Database->new->schema;
                $schema->txn_do(
                    sub {
                        $action->set( { illrequest_id => $prev_action->illrequest_id } )->store();
                        $self->update_ill_request($action);
                        my $msg = sprintf(
                            "ILL request updated: circId=%s, circStatus='%s', lastCircState='%s', ill_request_id=%s",
                            $data->{circId}, $data->{circStatus},
                            $data->{lastCircState},
                            $prev_action->illrequest_id
                        );
                        $self->logger->info($msg);
                        $results->{updated}++;
                        my $prev_req_id = $prev_action->illrequest_id;
                        push @{ $results->{messages} },
                            {
                            type           => 'updated',
                            circId         => $data->{circId},
                            message        => "Updated ILL request $prev_req_id",
                            ill_request_id => $prev_req_id
                            };
                    }
                );
            }    # else / no action required
        } catch {
            my $error = $_;

            # Check if this is a duplicate entry error
            if ( $error =~ /Duplicate entry.*for key|already exists/ ) {
                my $msg = sprintf(
                    "Skipping duplicate circId=%s (already processed)",
                    $data->{circId}
                );
                $self->logger->debug($msg);
                $results->{skipped}++;
                push @{ $results->{messages} },
                    {
                    type    => 'skipped',
                    circId  => $data->{circId},
                    message => "Already processed (duplicate)"
                    };
            } else {
                my $msg = sprintf(
                    "Error processing circId=%s: %s",
                    $data->{circId}, $error
                );
                $self->logger->error($msg);
                $results->{errors}++;
                push @{ $results->{messages} },
                    {
                    type    => 'error',
                    circId  => $data->{circId},
                    message => $error
                    };
            }
        };
    }

    return $results;
}

=head3 add_ill_request

=cut

sub add_ill_request {
    my ( $self, $action ) = @_;

    my $req = $self->get_ill_request( { circId => $action->circId, pod => $action->pod } );
    RapidoILL::Exception->throw(
        sprintf(
            "A request with circId=%s and pod=%s already exists!",
            $action->circId, $action->pod
        )
    ) if $req;

    my $server_code = $self->configuration->{ $action->pod }->{server_code};

    # identify our role
    if ( $self->are_we_lender($action) ) {
        $req = $self->create_item_hold($action);
    } elsif ( $self->are_we_borrower($action) ) {
        $req = $self->create_patron_hold($action);
    } else {
        RapidoILL::Exception::BadAgencyCode->throw(
            borrowerCode => $action->borrowerCode,
            lenderCode   => $action->lenderCode,
        );
    }

    return $req;
}

=head3 are_we_lender

=cut

sub are_we_lender {
    my ( $self, $action ) = @_;
    my $server_code = $self->configuration->{ $action->pod }->{server_code};
    return $action->lenderCode eq $server_code;
}

=head3 are_we_borrower

=cut

sub are_we_borrower {
    my ( $self, $action ) = @_;
    my $server_code = $self->configuration->{ $action->pod }->{server_code};
    return $action->borrowerCode eq $server_code;
}

=head3 create_item_hold

=cut

sub create_item_hold {
    my ( $self, $action ) = @_;

    my $item = $action->item;

    RapidoILL::Exception::UnknownItemId->throw( item_id => $action->itemId )
        unless $item;

    my $attributes = {
        author             => $action->author,
        borrowerCode       => $action->borrowerCode,
        callNumber         => $action->callNumber,
        circ_action_id     => $action->circ_action_id,
        circId             => $action->circId,
        circStatus         => $action->circStatus,
        dateCreated        => $action->dateCreated,
        dueDateTime        => $action->dueDateTime,
        itemAgencyCode     => $action->itemAgencyCode,
        itemBarcode        => $action->itemBarcode,
        itemId             => $action->itemId,
        lastCircState      => $action->lastCircState,
        lastUpdated        => $action->lastUpdated,
        lenderCode         => $action->lenderCode,
        needBefore         => $action->needBefore,
        patronAgencyCode   => $action->patronAgencyCode,
        patronId           => $action->patronId,
        patronName         => $action->patronName,
        pickupLocation     => $action->pickupLocation,
        pod                => $action->pod,
        puaLocalServerCode => $action->puaLocalServerCode,
        title              => $action->title,
    };

    return try {

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                my $agency_id = $action->patronAgencyCode;
                my $config    = $self->configuration->{ $action->pod };

                # Determine pickup location based on strategy
                my $pickup_strategy = $config->{lending}->{pickup_location_strategy} || 'partners_library';
                my $library_id;

                if ( $pickup_strategy eq 'homebranch' ) {
                    $library_id = $item->homebranch;
                } elsif ( $pickup_strategy eq 'holdingbranch' ) {
                    $library_id = $item->holdingbranch;
                } else {

                    # Default to partners_library
                    $library_id = $config->{partners_library_id};
                }

                my $patron_id = $self->get_patron_id_from_agency(
                    {
                        agency_id => $agency_id,
                        pod       => $action->pod,
                    }
                );

                if ( !$patron_id ) {

                    # FIXME: Should we just try to sync?
                    RapidoILL::Exceptions->throw(
                        sprintf(
                            "No patron_id for the request agency code (%s)",
                            $agency_id
                        )
                    );
                }

                # Create the request
                my $req = Koha::ILL::Request->new(
                    {
                        branchcode     => $library_id,
                        borrowernumber => $patron_id,
                        biblio_id      => $item->biblionumber,
                        status         => 'O_ITEM_REQUESTED',
                        backend        => $self->ill_backend(),
                        placed         => \'NOW()',
                    }
                );

                $req->store;

                $action->illrequest_id( $req->id )->store();

                # Add attributes
                $self->add_or_update_attributes(
                    {
                        attributes => $attributes,
                        request    => $req,
                    }
                );

                my $patron               = Koha::Patrons->find($patron_id);
                my $can_item_be_reserved = CanItemBeReserved( $patron, $item, $library_id )->{status};

                if ( $can_item_be_reserved ne 'OK' ) {
                    $self->logger->warn(
                              "Placing the hold, but rules woul've prevented it. FIXME! (patron_id=$patron_id, item_id="
                            . $item->itemnumber
                            . ", library_id=$library_id, status=$can_item_be_reserved)" );
                }

                my $hold_id = $self->add_hold(
                    {
                        biblio_id  => $item->biblionumber,
                        item_id    => $item->id,
                        library_id => $req->branchcode,
                        patron_id  => $patron_id,
                        notes      => exists $config->{default_hold_note}
                        ? $config->{default_hold_note}
                        : 'Placed by ILL',
                    }
                );

                Koha::ILL::Request::Attribute->new(
                    {
                        illrequest_id => $req->illrequest_id,
                        type          => 'hold_id',
                        value         => $hold_id,
                        readonly      => 1
                    }
                )->store;

                return $req;
            }
        );
    } catch {
        return $_->rethrow;
    };
}

=head3 create_patron_hold

=cut

sub create_patron_hold {
    my ( $self, $action ) = @_;

    my $patron = Koha::Patrons->find( { cardnumber => $action->patronId } );

    RapidoILL::Exception::UnknownPatronId->throw( patron_id => $action->patronId )
        unless $patron;

    my $attributes = {
        author             => $action->author,
        borrowerCode       => $action->borrowerCode,
        callNumber         => $action->callNumber,
        circ_action_id     => $action->circ_action_id,
        circId             => $action->circId,
        circStatus         => $action->circStatus,
        dateCreated        => $action->dateCreated,
        dueDateTime        => $action->dueDateTime,
        prevDueDateTime    => $action->dueDateTime,
        itemAgencyCode     => $action->itemAgencyCode,
        itemBarcode        => $action->itemBarcode,
        itemId             => $action->itemId,
        lastCircState      => $action->lastCircState,
        lastUpdated        => $action->lastUpdated,
        lenderCode         => $action->lenderCode,
        needBefore         => $action->needBefore,
        patronAgencyCode   => $action->patronAgencyCode,
        patronId           => $action->patronId,
        patronName         => $action->patronName,
        pickupLocation     => $action->pickupLocation,
        pod                => $action->pod,
        puaLocalServerCode => $action->puaLocalServerCode,
        title              => $action->title,
    };

    return try {

        my $schema = Koha::Database->new->schema;
        $schema->txn_do(
            sub {
                my $pickup_location = $self->pickup_location_to_library_id(
                    {
                        pickupLocation => $attributes->{pickupLocation},
                        pod            => $action->pod,
                    }
                );

                my $status = 'B_ITEM_REQUESTED';

                if ( $action->lastCircState eq 'ITEM_SHIPPED' ) {
                    $status = 'B_ITEM_SHIPPED';
                }    # FIXME: What about other out of sync statuses?

                # Create the request
                my $req = Koha::ILL::Request->new(
                    {
                        branchcode     => $pickup_location,
                        borrowernumber => $patron->id,
                        biblio_id      => undef,
                        status         => $status,
                        backend        => $self->ill_backend(),
                        placed         => \'NOW()',
                    }
                )->store;

                $action->illrequest_id( $req->id )->store();

                # Add attributes
                $self->add_or_update_attributes(
                    {
                        attributes => $attributes,
                        request    => $req,
                    }
                );

                return $req;
            }
        );
    } catch {
        return $_->rethrow;
    };
}

=head3 update_ill_request

    $plugin->update_ill_request($action);

Updates an existing ILL request based on the circulation action received
from the Rapido API. Determines the appropriate perspective (borrower or lender)
and delegates processing to the corresponding ActionHandler.

Parameters:
- action: RapidoILL::CircAction object containing circulation state information

=cut

sub update_ill_request {
    my ( $self, $action ) = @_;

    my $perspective =
          $self->are_we_lender($action)   ? 'lender'
        : $self->are_we_borrower($action) ? 'borrower'
        :                                   undef;

    if ( !$perspective ) {
        RapidoILL::Exception::BadAgencyCode->throw(
            borrowerCode => $action->borrowerCode,
            lenderCode   => $action->lenderCode,
        );
    }

    $self->get_action_handler(
        {
            pod         => $action->pod,
            perspective => $perspective
        }
    )->handle_from_action($action);

    return;
}

=head3 is_exact_duplicate

    if ( $self->is_exact_duplicate($action) ) { ... }

Method that checks if an action is an exact duplicate based on the unique
constraint fields (circId, pod, circStatus, lastCircState).

=cut

sub is_exact_duplicate {
    my ( $self, $action ) = @_;

    my $existing = RapidoILL::CircActions->search(
        {
            circId        => $action->circId,
            pod           => $action->pod,
            circStatus    => $action->circStatus,
            lastCircState => $action->lastCircState,
        }
    )->next;

    return $existing ? 1 : 0;
}

=head3 is_circ_action_update

    if ( $self->is_circ_action_update($action) ) { ... }
    my $prev_action = $self->is_circ_action_update($action);
    if ( $prev_action ) { ... }

Method that returns a the I<RapidoILL::CircAction> the passed one is updating.
It returns I<undef> otherwise.

=cut

sub is_circ_action_update {
    my ( $self, $action ) = @_;

    my $stored_actions = RapidoILL::CircActions->search(
        { circId   => $action->circId },
        { order_by => { -desc => 'lastUpdated' } }
    );

    if ( $stored_actions->count > 0 ) {

        # pick the newest
        my $last_update = $stored_actions->next;
        if ( $last_update->lastUpdated < $action->lastUpdated ) {
            return $last_update;
        }
    }

    return;
}

=head3 is_circ_action_new

    if ( $self->is_circ_action_new($action) ) { ... }

Method that returns a boolean telling if the action is new to the DB.

=cut

sub is_circ_action_new {
    my ( $self, $action ) = @_;

    my $stored_actions = RapidoILL::CircActions->search(
        { circId   => $action->circId, pod => $action->pod, },
        { order_by => { -desc => 'lastUpdated' } }
    );

    return $stored_actions->count == 0;
}

=head3 get_ill_request_from_attribute

    my $req = $plugin->get_ill_request_from_attribute(
        {
            type  => $type,
            value => $value
        }
    );

Retrieve an ILL request using some attribute.

=cut

sub get_ill_request_from_attribute {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(type value)], params => $params } );

    my $type  = $params->{type};
    my $value = $params->{value};

    my $requests_rs = Koha::ILL::Requests->search(
        {
            'illrequestattributes.type'  => $type,
            'illrequestattributes.value' => $value,
            'me.backend'                 => $self->ill_backend(),
        },
        { join => ['illrequestattributes'] }
    );

    my $count = $requests_rs->count;

    $self->logger->warn("more than one result searching requests with type='$type' value='$value'") if $count > 1;

    return $requests_rs->next
        if $count > 0;
}

=head3 get_ill_requests_from_attribute

    my $reqs = $plugin->get_ill_requests_from_attribute(
        {
            type  => $type,
            value => $value
        }
    );

Retrieve all ILL requests for the I<RapidoILL> backend with extended attributes
matching the passed parameters.

=cut

sub get_ill_requests_from_attribute {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(type value)], params => $params } );

    my $type  = $params->{type};
    my $value = $params->{value};

    return Koha::ILL::Requests->search(
        {
            'illrequestattributes.type'  => $type,
            'illrequestattributes.value' => $value,
            'me.backend'                 => $self->ill_backend(),
        },
        { join => ['illrequestattributes'] }
    );
}

=head3 get_checkout

    my $checkout = $plugin->get_checkout($ill_request);

Given an ILL request, returns the linked Koha::Checkout object if any, or undef.
Uses the checkout_id attribute to find the associated checkout.

=cut

sub get_checkout {
    my ( $self, $ill_request ) = @_;

    return unless $ill_request;

    my $checkout_id_attr = $ill_request->extended_attributes->search( { type => 'checkout_id' } )->next;
    return unless $checkout_id_attr;

    return Koha::Checkouts->find( $checkout_id_attr->value );
}

=head3 add_or_update_attributes

    $plugin->add_or_update_attributes(
        {
            request    => $request,
            attributes => {
                $type_1 => $value_1,
                $type_2 => $value_2,
                ...
            },
        }
    );

Takes care of updating or adding attributes if they don't already exist.

=cut

sub add_or_update_attributes {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(attributes request)], params => $params } );

    my $request    = $params->{request};
    my $attributes = $params->{attributes};

    Koha::Database->new->schema->txn_do(
        sub {
            while ( my ( $type, $value ) = each %{$attributes} ) {

                # Skip undefined or empty values to avoid database constraint errors
                next unless defined $value && $value ne '';

                my $attr = $request->extended_attributes->find( { type => $type } );

                if ($attr) {    # update
                    if ( $attr->value ne $value ) {
                        $attr->update( { value => $value, } );
                    }
                } else {        # new
                    $attr = Koha::ILL::Request::Attribute->new(
                        {
                            illrequest_id => $request->id,
                            type          => $type,
                            value         => $value,
                        }
                    )->store;
                }
            }
        }
    );

    return;
}

=head3 pickup_location_to_library_id

    my $library_id = $plugin->pickup_location_to_library_id(
        {
            pickupLocation => $pickupLocation,
            pod            => $pod,
        }
    );

Given a I<pickupLocation> code as found on an incoming request
this method returns the local library_id that is mapped to the passed value

=cut

sub pickup_location_to_library_id {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(pickupLocation pod)], params => $params } );

    my $configuration = $self->configuration->{ $params->{pod} };

    my $pickup_location;
    my $library_id;

    if ( $params->{pickupLocation} =~ m/^(?<pickup_location>.*):.*$/ ) {
        $pickup_location = $+{pickup_location};
    } else {
        RapidoILL::Exception::BadPickupLocation->throw( value => $params->{pickupLocation} );
    }

    RapidoILL::Exception::MissingMapping->throw(
        section => 'location_to_library',
        key     => $pickup_location
    ) unless exists $configuration->{location_to_library}->{$pickup_location};

    return $configuration->{location_to_library}->{$pickup_location};
}

=head3 validate_params

    $self->validate_params( { required => $required, params => $params } );

Reusable method for validating the passed parameters with a list of
required params.

=cut

sub validate_params {
    my ( $self, $args ) = @_;

    foreach my $param ( @{ $args->{required} } ) {
        RapidoILL::Exception::MissingParameter->throw( param => $param )
            unless exists $args->{params}->{$param};
    }

    return;
}

=head3 get_action_handler

    my $action_handler = $plugin->get_action_handler({
        pod => $pod,
        perspective => $perspective
    });

This method instantiates an action handler for the specified perspective.
These handlers are designed for use by the task_queue_daemon.pl script
to process actions from the sync operations.

Parameters:
- pod: The pod identifier
- perspective: 'borrower' or 'lender'

=cut

sub get_action_handler {
    my ( $self, $params ) = @_;

    $self->validate_params( { required => [qw(pod perspective)], params => $params } );

    my $pod         = $params->{pod};
    my $perspective = $params->{perspective};

    if ( $perspective eq 'borrower' ) {
        return $self->get_borrower_action_handler($pod);
    } elsif ( $perspective eq 'lender' ) {
        return $self->get_lender_action_handler($pod);
    } else {
        RapidoILL::Exception::BadParameter->throw("Invalid perspective: $perspective. Must be 'borrower' or 'lender'");
    }
}

=head3 get_borrower_action_handler

    my $borrower_handler = $plugin->get_borrower_action_handler( $pod );

This method instantiates a borrower action handler for task queue operations.
These handlers process actions from the borrower perspective when triggered
by the task_queue_daemon.pl script.

=cut

sub get_borrower_action_handler {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::ActionHandler::Borrower;

    unless ( $self->{borrower_action_handler}->{$pod} ) {
        $self->{borrower_action_handler}->{$pod} = RapidoILL::ActionHandler::Borrower->new(
            {
                pod    => $pod,
                plugin => $self,
            }
        );
    }

    return $self->{borrower_action_handler}->{$pod};
}

=head3 get_lender_action_handler

    my $lender_handler = $plugin->get_lender_action_handler( $pod );

This method instantiates a lender action handler for task queue operations.
These handlers process actions from the lender perspective when triggered
by the task_queue_daemon.pl script.

=cut

sub get_lender_action_handler {
    my ( $self, $pod ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;

    require RapidoILL::ActionHandler::Lender;

    unless ( $self->{lender_action_handler}->{$pod} ) {
        $self->{lender_action_handler}->{$pod} = RapidoILL::ActionHandler::Lender->new(
            {
                pod    => $pod,
                plugin => $self,
            }
        );
    }

    return $self->{lender_action_handler}->{$pod};
}

=head3 epoch_to_end_of_day

    my $datetime = $plugin->epoch_to_end_of_day($epoch_timestamp);

Convert an epoch timestamp to a DateTime object with time set to 23:59:59.
This ensures consistency with Koha's end-of-day date handling.

=cut

sub epoch_to_end_of_day {
    my ( $self, $epoch ) = @_;

    RapidoILL::Exception::MissingParameter->throw( param => 'epoch' )
        unless defined $epoch;

    my $dt = DateTime->from_epoch( epoch => $epoch );
    $dt->set_hour(23)->set_minute(59)->set_second(59);

    return $dt;
}

1;
