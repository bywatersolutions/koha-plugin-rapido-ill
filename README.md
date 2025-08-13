# koha-plugin-rapido-ill

[![CI](https://github.com/bywatersolutions/koha-plugin-rapido-ill/actions/workflows/main.yml/badge.svg)](https://github.com/bywatersolutions/koha-plugin-rapido-ill/actions/workflows/main.yml)

## Plugin configuration

The plugin configuration is an HTML text area in which a *YAML* structure is pasted. The available options
are maintained on this document.

```yaml
---
dev03-na:
  base_url: https://dev03-na.alma.exlibrisgroup.com
  client_id: client_id
  client_secret: client_secret
  server_code: 11747
  partners_library_id: CPL
  partners_category: ILL
  default_item_type: ILL
  default_patron_agency: code1
  default_location:
  default_checkin_note: Additional processing required (ILL)
  default_hold_note: Placed by ILL
  default_marc_framework: FA
  default_item_ccode: RAPIDO
  default_notforloan:
  materials_specified: true
  default_materials_specified: Additional processing required (ILL)
  location_to_library:
    RES_SHARE: CPL
  borrowing:
    automatic_item_in_transit: false
    automatic_item_receive: false
  lending:
    automatic_final_checkin: false
    automatic_item_shipped: false
  # Patron validation restrictions
  debt_blocks_holds: true
  max_debt_blocks_holds: 100
  expiration_blocks_holds: true
  restriction_blocks_holds: true
  # Debugging
  debug_mode: false
  debug_requests: false
  dev_mode: false
  default_retry_delay: 120
```

## Setting the task queue daemon

The task queue daemon will process any asynchronous tasks that are required.
This will usually relate to circulation updates to be notified to the pod.

To run it:

```shell
$ cp /var/lib/koha/<instance>/plugins/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/rapido_task_queue.service \
     /etc/systemd/system/rapido_task_queue.service
# set KOHA_INSTANCE to match what you need (default: kohadev)
$ vim /etc/systemd/system/rapido_task_queue.service
# reload unit files, including the new one
$ systemctl daemon-reload
# enable service
$ systemctl enable rapido_task_queue.service
Created symlink /etc/systemd/system/multi-user.target.wants/rapido_task_queue.service → /etc/systemd/system/rapido_task_queue.service
# check the logs :-D
$ journalctl -u rapido_task_queue.service -f
```

## Cronjobs

The plugin provides scripts that need to be run regularly via cron to synchronize data with Rapido pods.

### Setting up sync_requests.pl

The `sync_requests.pl` script synchronizes request data between Koha and the Rapido pod. It should be run every 5 minutes for each configured pod.

#### Crontab Setup

1. **Edit the crontab for your Koha instance user**:
   ```bash
   sudo -u <instance>-koha crontab -e
   ```

2. **Add entries for each pod** (replace variables as needed):
   ```bash
   # Rapido ILL sync - runs every 5 minutes for each pod
   */5 * * * * cd /var/lib/koha/<instance>/plugins; PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod <pod_name>
   ```

#### Variables to Replace

- `<instance>`: Your Koha instance name (e.g., `kohadev`, `library`, `production`)
- `<pod_name>`: The pod identifier from your configuration (e.g., `dev03-na`, `prod-eu`)

#### Complete Example

For a Koha instance named `library` with two pods (`dev03-na` and `prod-eu`):

```bash
# Edit crontab
sudo -u library-koha crontab -e

# Add these lines:
# Rapido ILL sync for dev03-na pod - every 5 minutes
*/5 * * * * cd /var/lib/koha/library/plugins; PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod dev03-na

# Rapido ILL sync for prod-eu pod - every 5 minutes  
*/5 * * * * cd /var/lib/koha/library/plugins; PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod prod-eu
```

#### Optional Parameters

- `--start_time <timestamp>`: Start synchronization from a specific Unix timestamp
- `--pod <pod_name>`: Specify which pod to synchronize (required)

#### Monitoring

Check the Koha logs for sync activity:
```bash
tail -f /var/log/koha/<instance>/plack-intranet-error.log | grep -i rapido
```

#### Sample Cron File

A sample cron configuration file (`cron.sample`) is available in the plugin source code for reference. This file contains examples and detailed comments but is not included in the packaged plugin.

## Notices

The plugin implements the `notices_content` hook to make ILL-related information available to notices.

### `HOLD_SLIP`

On this letter, the plugin makes this attributes available.

* `[% plugin_content.rapidoill.ill_request %]`
* `[% plugin_content.rapidoill.author | html %]`
* `[% plugin_content.rapidoill.borrowerCode | html %]`
* `[% plugin_content.rapidoill.callNumber | html %]`
* `[% plugin_content.rapidoill.circ_action_id | html %]`
* `[% plugin_content.rapidoill.circId | html %]`
* `[% plugin_content.rapidoill.circStatus | html %]`
* `[% plugin_content.rapidoill.dateCreated | html %]`
* `[% plugin_content.rapidoill.dueDateTime | html %]`
* `[% plugin_content.rapidoill.itemAgencyCode | html %]`
* `[% plugin_content.rapidoill.itemBarcode | html %]`
* `[% plugin_content.rapidoill.itemId | html %]`
* `[% plugin_content.rapidoill.lastCircState | html %]`
* `[% plugin_content.rapidoill.lastUpdated | html %]`
* `[% plugin_content.rapidoill.lenderCode | html %]`
* `[% plugin_content.rapidoill.needBefore | html %]`
* `[% plugin_content.rapidoill.patronAgencyCode | html %]`
* `[% plugin_content.rapidoill.patronId | html %]`
* `[% plugin_content.rapidoill.patronName | html %]`
* `[% plugin_content.rapidoill.pickupLocation | html %]`
* `[% plugin_content.rapidoill.pod | html %]`
* `[% plugin_content.rapidoill.puaLocalServerCode | html %]`
* `[% plugin_content.rapidoill.title | html %]`

The `ill_request` attribute will only be available if the plugin finds the hold is linked to
a valid Rapido ILL request. It should be used to detect the ILL context for displaying
ILL specific messages.

For example:

```
[% IF plugin_content.rapidoill.ill_request  %]
<ul>
    <li>ILL request ID: [% plugin_content.rapidoill.ill_request.id | html %]</li>
    <li>Item ID: [% plugin_content.rapidoill.itemId | html %]</li>
    <li>Pickup location: [% plugin_content.rapidoill.pickupLocation | html %]</li>
    <li>Patron name: [% plugin_content.rapidoill.patronName | html %]</li>
    <li>Call number: [% plugin_content.rapidoill.callNumber | html %]</li>
<ul>
[% END %]
```

## Development

### Architecture Overview

The Rapido ILL plugin follows Koha's standard object-oriented patterns for database interaction and plugin development.

#### Core Components

**API Client**: `RapidoILL::Client`
- Primary interface for communicating with Rapido ILL services
- Handles authentication and API requests to the pod
- Instantiated via `$plugin->get_client($pod)` from the main plugin
- Key methods include:
  - `locals()` - Get local library information
  - `lender_*()` methods - Lending operations (cancel, checkout, checkin, shipped)
  - `borrower_*()` methods - Borrowing operations (received, cancel, renew, returned)
  - `circulation_requests()` - Retrieve circulation request data

**Main Plugin Class**: `Koha/Plugin/Com/ByWaterSolutions/RapidoILL.pm`
- Handles plugin lifecycle, configuration, and schema registration
- Registers custom database tables in the BEGIN block
- Provides helper methods for accessing collections and API client
- Contains `get_client($pod)` method for API client instantiation

**Database Models**:
- `RapidoILL::QueuedTask` - Individual task queue records (inherits from Koha::Object)
- `RapidoILL::CircAction` - Circulation action records (inherits from Koha::Object)
- `RapidoILL::QueuedTasks` - Task queue collection (inherits from Koha::Objects)
- `RapidoILL::CircActions` - Circulation actions collection (inherits from Koha::Objects)

**Schema Classes**: Auto-generated DBIx::Class result classes in `Koha/Schema/Result/`
- Handle database table definitions and relationships
- Generated from actual database structure
- Registered with Koha's schema in the main plugin's BEGIN block

#### Development Environment

**Koha Testing Docker (KTD) Setup**:
Launch a complete Koha environment for the project:
```bash
# Launch KTD with proxy and plugins support
ktd --proxy --name rapido --plugins up -d

# Run commands in the container
ktd --name rapido --shell --run "command_here"

# Access container shell directly
ktd --name rapido --shell
```

**Plugin Development**:
- The `/kohadevbox/plugins` directory is mounted from your PLUGINS_DIR environment variable
- For this project: `~/git/koha-plugins/rapido-ill` is mounted to `/kohadevbox/plugins/rapido-ill`
- Container name: `rapido-koha-1` (or `rapido` when using ktd commands)
- Use ktd commands for container management and testing

**Testing Commands**:
```bash
# Set up Perl library path for testing
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Test object instantiation
perl -MKoha::Plugin::Com::ByWaterSolutions::RapidoILL -MRapidoILL::QueuedTask -e 'my $t = RapidoILL::QueuedTask->new;'

# Test collection operations
perl -MKoha::Plugin::Com::ByWaterSolutions::RapidoILL -MRapidoILL::QueuedTasks -e 'my $tasks = RapidoILL::QueuedTasks->new;'

# Install plugin for testing
cd /kohadevbox/koha && perl misc/devel/install_plugins.pl
```

#### Database Patterns

**Object Creation**: Use the standard Koha pattern
```perl
my $task = RapidoILL::QueuedTask->new($attributes)->store();
```

**Collection Access**: Access through the main plugin
```perl
my $tasks = $self->get_queued_tasks();
my $new_task = $tasks->enqueue($task_data);
```

**Schema Registration**: Happens automatically in the main plugin's BEGIN block
- Loads schema result classes
- Registers them with Koha::Schema
- Refreshes database handle to include new classes

#### Task Queue System

The plugin implements an asynchronous task queue for operations that need to be processed separately:

**Enqueuing Tasks**:
```perl
$self->get_queued_tasks->enqueue({
    object_type   => 'biblio',
    object_id     => $record_id,
    action        => 'o_item_shipped',
    pod           => $pod_identifier,
});
```

**Task Processing**: Handled by the systemd service `rapido_task_queue.service`

#### File Structure

```
Koha/Plugin/Com/ByWaterSolutions/RapidoILL/
├── RapidoILL.pm                    # Main plugin class
├── lib/
│   ├── RapidoILL/
│   │   ├── QueuedTask.pm           # Individual task model
│   │   ├── QueuedTasks.pm          # Task collection
│   │   ├── CircAction.pm           # Individual circulation action
│   │   ├── CircActions.pm          # Circulation action collection
│   │   └── ...                     # Other business logic classes
│   └── Koha/Schema/Result/         # Auto-generated schema classes
└── scripts/                        # System service scripts
```

#### Key Development Practices

**Package Declarations**: Ensure package names match file names exactly
```perl
# In QueuedTask.pm
package RapidoILL::QueuedTask;
```

**Inheritance**: Use Koha's standard inheritance patterns
```perl
use base qw(Koha::Object);    # For individual records
use base qw(Koha::Objects);   # For collections
```

**Schema Updates**: When database structure changes:
1. Update the actual database tables
2. Regenerate schema files using the KTD workflow:
   ```bash
   # Jump into the Koha source directory (mounted from SYNC_REPO)
   cd /kohadevbox/koha
   
   # Install the plugin to register schema changes
   perl misc/devel/install_plugins.pl
   
   # Regenerate all DBIx::Class schema files
   perl misc/devel/update_dbix_class_files.pl --db_host db --db_name koha_kohadev --db_user root --db_passwd password
   
   # Detect and copy Rapido ILL specific schema files to plugin directory
   # Look for files matching: Koha/Schema/Result/*RapidoILL* or *Rapidoill*
   find Koha/Schema/Result/ -name "*apidoill*" -o -name "*apido*" | while read file; do
       cp "$file" "/kohadevbox/plugins/rapido-ill/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib/$file"
   done
   
   # Roll back changes to Koha source to keep it clean
   git checkout -- .
   ```
3. Ensure schema registration in main plugin remains current

**Testing**: Always test both individual object operations and collection operations to ensure proper inheritance and database connectivity.
