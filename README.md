# Koha Plugin: Rapido ILL

[![CI](https://github.com/bywatersolutions/koha-plugin-rapido-ill/actions/workflows/main.yml/badge.svg)](https://github.com/bywatersolutions/koha-plugin-rapido-ill/actions/workflows/main.yml)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/bywatersolutions/koha-plugin-rapido-ill)](https://github.com/bywatersolutions/koha-plugin-rapido-ill/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Introduction

The Rapido ILL plugin integrates Koha with the Rapido resource sharing network, enabling seamless interlibrary loan (ILL) operations. This plugin facilitates both borrowing and lending workflows, automatically synchronizing circulation data between your Koha instance and Rapido pods.

**Key Features:**
- **Automated ILL workflows** for borrowing and lending
- **Real-time synchronization** with Rapido pods
- **Configurable automation** for circulation actions
- **Patron validation** and restriction handling
- **Task queue system** for asynchronous processing
- **Logging** and debugging capabilities

## Installation

1. **Download the plugin** from the releases page or build from source
2. **Install via Koha's plugin system**:
   - Go to Administration → Plugins
   - Upload the `.kpz` file
   - Enable the plugin
3. **Configure the plugin** (see Configuration section below)
4. **Set up system services** (task queue daemon and cron jobs)

## Configuration

### Plugin Configuration

The plugin configuration is an HTML text area in which a *YAML* structure is pasted. The available options are maintained in this document.

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
  # Development mode
  dev_mode: false
  default_retry_delay: 120
```

### Task Queue Daemon

The task queue daemon processes asynchronous tasks, typically circulation updates to be notified to the pod.

**Setup:**
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

### Cron Jobs

The plugin provides scripts that need to be run regularly via cron to synchronize data with Rapido pods.

#### Setting up sync_requests.pl

The `sync_requests.pl` script synchronizes request data between Koha and the Rapido pod. It should be run every 5 minutes for each configured pod.

**Crontab Setup:**

1. **Edit the crontab for your Koha instance user**:
   ```bash
   sudo -u <instance>-koha crontab -e
   ```

2. **Add entries for each pod** (replace variables as needed):
   ```bash
   # Rapido ILL sync - runs every 5 minutes for each pod
   */5 * * * * cd /var/lib/koha/<instance>/plugins; PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod <pod_name>
   ```

**Variables to Replace:**
- `<instance>`: Your Koha instance name (e.g., `kohadev`, `library`, `production`)
- `<pod_name>`: The pod identifier from your configuration (e.g., `dev03-na`, `prod-eu`)

**Complete Example:**

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

**Optional Parameters:**
- `--start_time <timestamp>`: Start synchronization from a specific Unix timestamp
- `--pod <pod_name>`: Specify which pod to synchronize (required)

**Monitoring:**
```bash
tail -f /var/log/koha/<instance>/plack-intranet-error.log | grep -i rapido
```

### Logging Configuration

The plugin uses Koha::Logger for logging. Debug logging is controlled entirely through Koha's log4perl configuration.

#### Koha log4perl.conf Configuration

Add the following to your Koha instance's `log4perl.conf` file (usually located at `/etc/koha/sites/<instance>/log4perl.conf`):

```perl
# RapidoILL Plugin Logging - Three Separate Log Files

# 1. General Plugin Logging
log4perl.logger.rapidoill = INFO, RAPIDOILL
log4perl.logger.opac.rapidoill = INFO, RAPIDOILL
log4perl.logger.intranet.rapidoill = INFO, RAPIDOILL
log4perl.logger.commandline.rapidoill = INFO, RAPIDOILL
log4perl.logger.cron.rapidoill = INFO, RAPIDOILL
log4perl.additivity.rapidoill = 0
log4perl.additivity.opac.rapidoill = 0
log4perl.additivity.intranet.rapidoill = 0
log4perl.additivity.commandline.rapidoill = 0
log4perl.additivity.cron.rapidoill = 0

log4perl.appender.RAPIDOILL = Log::Log4perl::Appender::File
log4perl.appender.RAPIDOILL.filename = /var/log/koha/<instance>/rapidoill.log
log4perl.appender.RAPIDOILL.mode = append
log4perl.appender.RAPIDOILL.layout = PatternLayout
log4perl.appender.RAPIDOILL.layout.ConversionPattern = [%d] [%p] %m %l%n
log4perl.appender.RAPIDOILL.utf8 = 1

# 2. External API Calls (Koha -> Rapido ILL)
log4perl.logger.rapidoill_api = DEBUG, RAPIDOILL_API
log4perl.logger.opac.rapidoill_api = DEBUG, RAPIDOILL_API
log4perl.logger.intranet.rapidoill_api = DEBUG, RAPIDOILL_API
log4perl.logger.commandline.rapidoill_api = DEBUG, RAPIDOILL_API
log4perl.logger.cron.rapidoill_api = DEBUG, RAPIDOILL_API
log4perl.additivity.rapidoill_api = 0
log4perl.additivity.opac.rapidoill_api = 0
log4perl.additivity.intranet.rapidoill_api = 0
log4perl.additivity.commandline.rapidoill_api = 0
log4perl.additivity.cron.rapidoill_api = 0

log4perl.appender.RAPIDOILL_API = Log::Log4perl::Appender::File
log4perl.appender.RAPIDOILL_API.filename = /var/log/koha/<instance>/rapidoill-api.log
log4perl.appender.RAPIDOILL_API.mode = append
log4perl.appender.RAPIDOILL_API.layout = PatternLayout
log4perl.appender.RAPIDOILL_API.layout.ConversionPattern = [%d] [%p] %m %l%n
log4perl.appender.RAPIDOILL_API.utf8 = 1

# 3. Task Queue Daemon Logging
log4perl.logger.rapidoill_daemon = INFO, RAPIDOILL_DAEMON
log4perl.logger.opac.rapidoill_daemon = INFO, RAPIDOILL_DAEMON
log4perl.logger.intranet.rapidoill_daemon = INFO, RAPIDOILL_DAEMON
log4perl.logger.commandline.rapidoill_daemon = INFO, RAPIDOILL_DAEMON
log4perl.logger.cron.rapidoill_daemon = INFO, RAPIDOILL_DAEMON
log4perl.additivity.rapidoill_daemon = 0
log4perl.additivity.opac.rapidoill_daemon = 0
log4perl.additivity.intranet.rapidoill_daemon = 0
log4perl.additivity.commandline.rapidoill_daemon = 0
log4perl.additivity.cron.rapidoill_daemon = 0

log4perl.appender.RAPIDOILL_DAEMON = Log::Log4perl::Appender::File
log4perl.appender.RAPIDOILL_DAEMON.filename = /var/log/koha/<instance>/rapidoill-daemon.log
log4perl.appender.RAPIDOILL_DAEMON.mode = append
log4perl.appender.RAPIDOILL_DAEMON.layout = PatternLayout
log4perl.appender.RAPIDOILL_DAEMON.layout.ConversionPattern = [%d] [%p] %m %l%n
log4perl.appender.RAPIDOILL_DAEMON.utf8 = 1
```

Replace `<instance>` with your actual Koha instance name.

**Important**: The configuration includes multiple logger categories for each log type:
- **Base categories** (`rapidoill`, `rapidoill_api`, `rapidoill_daemon`): For direct Log4perl usage
- **Interface-prefixed categories** (`opac.rapidoill`, `intranet.rapidoill`, `commandline.rapidoill`, `cron.rapidoill`, etc.): For Koha::Logger usage

Koha::Logger automatically prefixes categories with the current interface (`opac`, `intranet`, `commandline`, or `cron`), so all sets of categories are required for complete coverage across web interfaces, command-line scripts, and scheduled tasks.

**Important:** After modifying `log4perl.conf`, restart your Koha services:

```bash
# For systemd-based installations
sudo systemctl restart koha-common

# Or restart specific services
sudo systemctl restart apache2
sudo systemctl restart koha-indexer
```

#### Log Levels

You can adjust the log level as needed for each category:

**General Plugin Logging (`rapidoill`):**
- Web interface operations, business logic, and general plugin activities
- `INFO` - General operations (recommended for production)
- `DEBUG` - Detailed plugin operations
- `WARN` - Warning messages
- `ERROR` - Error messages only

**External API Calls (`rapidoill.api`):**
- HTTP requests/responses between Koha and Rapido ILL servers
- `DEBUG` - Detailed HTTP request/response logging (recommended for troubleshooting)
- `INFO` - Brief API operation logs
- `WARN` - API warnings
- `ERROR` - API failures only

**Task Queue Daemon (`rapidoill.daemon`):**
- Background task processing and daemon lifecycle events
- `INFO` - Task batch processing and completion status (recommended)
- `DEBUG` - Detailed task processing information
- `WARN` - Task retry warnings
- `ERROR` - Task failures and daemon errors

#### Troubleshooting Logging

**No messages appearing in log files?**

1. **Check interface prefixing**: Koha::Logger automatically prefixes categories with the interface name (`opac`, `intranet`, `commandline`, or `cron`). Ensure you have both base and prefixed categories configured for all interfaces.

2. **Verify configuration syntax**: Check that your log4perl.conf has no syntax errors:
   ```bash
   perl -c /etc/koha/sites/<instance>/log4perl.conf
   ```

3. **Test direct logging**: Verify the configuration works with direct Log4perl:
   ```perl
   use Log::Log4perl;
   Log::Log4perl->init('/etc/koha/sites/<instance>/log4perl.conf');
   my $logger = Log::Log4perl->get_logger('rapidoill');
   $logger->info('Test message');
   ```

4. **Check file permissions**: Ensure the Koha user can write to the log files:
   ```bash
   sudo chown <koha-user>:<koha-group> /var/log/koha/<instance>/rapidoill*.log
   sudo chmod 644 /var/log/koha/<instance>/rapidoill*.log
   ```

5. **Restart services**: After configuration changes, restart Koha services:
   ```bash
   sudo systemctl restart apache2
   sudo koha-plack --restart <instance>
   ```

#### Log File Rotation

Consider setting up log rotation for the RapidoILL log file:

```bash
# Add to /etc/logrotate.d/koha-rapidoill
/var/log/koha/*/rapidoill.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 <instance>-koha <instance>-koha
    postrotate
        systemctl reload apache2 > /dev/null 2>&1 || true
    endscript
}
```

#### Viewing Logs

Monitor RapidoILL activity:

```bash
# Follow RapidoILL logs
tail -f /var/log/koha/<instance>/rapidoill.log

# Search for specific activity
grep "POST request" /var/log/koha/<instance>/rapidoill.log
grep "sync_requests" /var/log/koha/<instance>/rapidoill.log
```

**Sample Cron File:**
A sample cron configuration file (`cron.sample`) is available in the plugin source code for reference. This file contains examples and detailed comments but is not included in the packaged plugin.

## Notices

The plugin implements the `notices_content` hook to make ILL-related information available to notices.

### `HOLD_SLIP`

On this letter, the plugin makes these attributes available:

```
plugin_content.rapidoill.ill_request # The ILL request object, if available
plugin_content.rapidoill.author
plugin_content.rapidoill.borrowerCode
plugin_content.rapidoill.callNumber
plugin_content.rapidoill.circ_action_id
plugin_content.rapidoill.circId
plugin_content.rapidoill.circStatus
plugin_content.rapidoill.dateCreated
plugin_content.rapidoill.dueDateTime
plugin_content.rapidoill.itemAgencyCode
plugin_content.rapidoill.itemBarcode
plugin_content.rapidoill.itemId
plugin_content.rapidoill.lastCircState
plugin_content.rapidoill.lastUpdated
plugin_content.rapidoill.lenderCode
plugin_content.rapidoill.needBefore
plugin_content.rapidoill.patronAgencyCode
plugin_content.rapidoill.patronId
plugin_content.rapidoill.patronName
plugin_content.rapidoill.pickupLocation
plugin_content.rapidoill.pod
plugin_content.rapidoill.puaLocalServerCode
plugin_content.rapidoill.title
```

The `ill_request` attribute will only be available if the plugin finds the hold is linked to a valid Rapido ILL request. It should be used to detect the ILL context for displaying ILL specific messages.

**Example:**
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

**For developers, contributors, and advanced users**: See [DEVELOPMENT.md](DEVELOPMENT.md) for development documentation including:

- **KTD setup and testing environment**
- **Mock Rapido API for development**
- **Architecture overview and code structure**
- **Testing commands and debugging**
- **Database schema and object patterns**

### Quick Development Start

For rapid development and testing without connecting to real Rapido services:

```bash
# 1. Start KTD environment
ktd --name rapido --plugins up -d
ktd --name rapido --shell

# 2. Navigate to plugin directory
cd /kohadevbox/plugins/rapido-ill/scripts

# 3. Bootstrap testing environment
./bootstrap_rapido_testing.pl

# 4. Start mock Rapido API
./mock_rapido_api.pl --port=3001 --scenario=borrowing

# 5. Test all endpoints
./test_all_endpoints.sh
```

**Mock API Features:**
- **Spec-compliant**: Matches official Rapido API specification exactly
- **Configurable scenarios**: borrowing, lending, mixed workflows  
- **Dynamic timestamps**: Uses DateTime for realistic data
- **Complete endpoints**: Authentication, circulation requests, actions
- **Workflow progression**: Simulates real ILL state transitions

**Testing Documentation:**
- [CURL_TESTING_GUIDE.md](CURL_TESTING_GUIDE.md) - Complete curl-based testing guide
- `scripts/test_all_endpoints.sh` - Automated test script
- `scripts/bootstrap_rapido_testing.pl` - Environment setup

The mock API allows full plugin development and testing without requiring access to Rapido services.
