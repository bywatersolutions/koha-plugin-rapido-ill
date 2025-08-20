# Rapido ILL Plugin - Development Guide

Comprehensive development documentation for the Rapido ILL plugin, including setup, testing, and architecture notes.

## Official Rapido Circulation States

Based on the official Rapido API specification (page 15 of "Rapido via APIs.pdf"), the valid circulation states are:

### CircActions Table:
The `CircActions` table serves as a log of status updates pulled from the Rapido central server. The `lastCircState` field contains the circulation control or state that was reported, including both states and controls like `FINAL_CHECKIN`.

### Valid Circulation States:
- `ITEM_HOLD` - Item is on hold
- `PATRON_HOLD` - Item is on hold for a patron  
- `ITEM_IN_TRANSIT` - Item is in transit (borrower → lender return)
- `ITEM_RECEIVED` - Item has been received
- `ITEM_SHIPPED` - Item has been shipped
- `ITEM_LOST` - Item is lost

### Circulation Controls (also stored in lastCircState):
- `FINAL_CHECKIN` - Lender receives returned item (results in `ITEM_RECEIVED` circStatus)
- `ITEM_IN_TRANSIT` - Borrower returns item to lender
- `ITEM_RECEIVED` - Item received at destination
- `ITEM_SHIPPED` - Item shipped to borrower
- And others as defined in the Rapido API specification

### Workflow Understanding:

#### Lending Perspective (We are the lender):
1. `ITEM_HOLD` - We hold the item for lending
2. `ITEM_SHIPPED` - We ship the item to borrower
3. *(Borrower receives it - they report `ITEM_RECEIVED`)*
4. *(Borrower returns it - they report `ITEM_IN_TRANSIT`)*
5. `FINAL_CHECKIN` - We receive the item back from borrower

#### Borrowing Perspective (We are the borrower):
1. `PATRON_HOLD` - Item on hold for our patron
2. *(Lender ships it - they report `ITEM_SHIPPED`)*
3. `ITEM_RECEIVED` - We receive the shipped item
4. `ITEM_IN_TRANSIT` - We send the item back to lender
5. *(Lender receives it back - they report `ITEM_RECEIVED` via FINAL_CHECKIN)*

### Mock API Scenarios:

### Data Structure:
Based on real Rapido API data, the structure uses:
- `circStatus` - High-level circulation status: `CREATED`, `ACTIVE`, `COMPLETED`, `CANCELED`
- `lastCircState` - The specific circulation control/state that triggered this update

### Real Rapido Status Patterns:
- `lastCircState: "ITEM_HOLD"` → `circStatus: "CREATED"` (new request)
- `lastCircState: "ITEM_SHIPPED"` → `circStatus: "ACTIVE"` (in progress)
- `lastCircState: "ITEM_RECEIVED"` → `circStatus: "ACTIVE"` (in progress)
- `lastCircState: "ITEM_IN_TRANSIT"` → `circStatus: "ACTIVE"` (in progress)
- `lastCircState: "FINAL_CHECKIN"` → `circStatus: "COMPLETED"` (finished)
- `lastCircState: "BORROWING_SITE_CANCEL"` → `circStatus: "CANCELED"` (borrower cancelled)
- `lastCircState: "OWNING_SITE_CANCEL"` → `circStatus: "COMPLETED"` (lender cancelled)

### Cancellation Patterns:
- **BORROWING_SITE_CANCEL**: Borrower cancels request → `circStatus: "CANCELED"`
- **OWNING_SITE_CANCEL**: Lender cancels request → `circStatus: "COMPLETED"`

Note: Lender cancellations result in `COMPLETED` status, not `CANCELED`, in the real Rapido system.

#### Borrowing Scenario (Complete Workflow):
- `borrowing_initial`: `circStatus: CREATED, lastCircState: PATRON_HOLD`
- `borrowing_shipped`: `circStatus: ACTIVE, lastCircState: ITEM_SHIPPED`
- `borrowing_received`: `circStatus: ACTIVE, lastCircState: ITEM_RECEIVED`
- `borrowing_in_transit`: `circStatus: ACTIVE, lastCircState: ITEM_IN_TRANSIT`
- `borrowing_final_checkin`: `circStatus: COMPLETED, lastCircState: FINAL_CHECKIN`

#### Lending Workflow (Complete 4 Steps):
1. `CREATED` ← `ITEM_HOLD` - We hold item for lending
2. `ACTIVE` ← `ITEM_SHIPPED` - We ship item to borrower
3. `ACTIVE` ← `ITEM_IN_TRANSIT` - Borrower returns item to us
4. `COMPLETED` ← `FINAL_CHECKIN` - We receive item back

#### Lending Scenario:
- `lending_initial`: `circStatus: CREATED, lastCircState: ITEM_HOLD`
- `lending_shipped`: `circStatus: ACTIVE, lastCircState: ITEM_SHIPPED`
- `lending_in_transit`: `circStatus: ACTIVE, lastCircState: ITEM_IN_TRANSIT`
- `lending_final_checkin`: `circStatus: COMPLETED, lastCircState: FINAL_CHECKIN`

#### Cancellation Scenarios:
- `borrowing_site_cancel`: `circStatus: CANCELED, lastCircState: BORROWING_SITE_CANCEL`
- `owning_site_cancel`: `circStatus: COMPLETED, lastCircState: OWNING_SITE_CANCEL`

**Note**: States like `PENDING_CHECKOUT`, `ITEM_CHECKED_OUT`, and `ITEM_RETURNED` are NOT part of the official Rapido specification and should not be used.

## Quick Start

### KTD Setup
```bash
# Required environment variables
export KTD_HOME=/path/to/koha-testing-docker
export PLUGINS_DIR=/path/to/plugins/parent/dir
export SYNC_REPO=/path/to/kohaclone

# Launch KTD with plugins
ktd --name rapido --plugins up -d
ktd --name rapido --wait-ready 120

# Install plugin
ktd --name rapido --shell --run "cd /kohadevbox/koha && perl misc/devel/install_plugins.pl"
```

### Mock Rapido API for Development

For development and testing without connecting to real Rapido services, use the included mock API that matches the official Rapido specification exactly.

#### Quick Mock API Setup

```bash
# 1. Get into KTD shell
ktd --name rapido --shell

# 2. Navigate to plugin directory
cd /kohadevbox/plugins/rapido-ill/scripts

# 3. Bootstrap testing environment (sets up plugin + sample data)
./bootstrap_rapido_testing.pl

# 4. Start mock Rapido API
./mock_rapido_api.pl --port=3001 --scenario=borrowing

# 5. Test all endpoints
./test_all_endpoints.sh
```

#### Mock API Features

- **Spec-compliant**: Matches official Rapido API specification exactly
- **Configurable scenarios**: borrowing, lending, mixed workflows  
- **Dynamic timestamps**: Uses DateTime for realistic Unix epoch timestamps
- **Complete endpoints**: Authentication, circulation requests, actions
- **Workflow progression**: Simulates real ILL state transitions
- **JSON configuration**: Automatic generation with realistic KTD sample data

#### Mock API Usage Examples

```bash
# Start API with specific scenario
./mock_rapido_api.pl --port=3001 --scenario=borrowing &

# Test authentication
curl -s -X POST http://localhost:3001/view/broker/auth | jq

# Test circulation requests (concise format)
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695" | jq

# Test circulation requests (verbose format)
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&content=verbose" | jq

# Switch scenarios
curl -s -X POST http://localhost:3001/control/scenario/lending | jq

# Test action endpoints
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendercancel | jq
```

#### Testing Documentation

- **[CURL_TESTING_GUIDE.md](CURL_TESTING_GUIDE.md)** - Complete step-by-step testing guide
- **`scripts/test_all_endpoints.sh`** - Automated test script
- **`scripts/bootstrap_rapido_testing.pl`** - Environment setup
- **`scripts/run_sync.sh`** - Integration testing with sync_requests.pl

#### Mock API Configuration

The mock API uses JSON configuration files with automatic generation:

```bash
# Configuration is automatically created on first run
# Located at: scripts/mock_config.json

# View current configuration
cat scripts/mock_config.json | jq

# Reset configuration (will regenerate on next start)
rm scripts/mock_config.json
```

### Testing with Real Plugin Integration

```bash
# Test sync script with mock API
cd /kohadevbox/plugins/rapido-ill/scripts
./mock_rapido_api.pl --port=3001 --scenario=borrowing &

# Run actual sync script against mock API
cd /kohadevbox/plugins/rapido-ill
export PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.
perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod mock-pod
```

## Standard Testing

### Unit and Integration Tests

The plugin includes comprehensive test coverage across multiple areas:

#### Test Suite Overview

**Unit Tests (t/):**
- **`t/00-load.t`** - Basic module loading tests
- **`t/01-constraint.t`** - CircAction and CircActions object tests
- **`t/02-plugin-methods.t`** - Plugin metadata and core method tests
- **`t/03-logger-integration.t`** - Koha::Logger integration and plugin-level logging tests
- **`t/04-backend-templates.t`** - Backend action-template correspondence tests

**Component Tests (t/RapidoILL/):**
- **`t/RapidoILL/APIHttpClient.t`** - APIHttpClient authentication and HTTP request logging tests
- **`t/RapidoILL/StringNormalizer.t`** - String normalization and validation tests

**Database-Dependent Tests (t/db_dependent/):**
- **`t/db_dependent/RapidoILL.t`** - Main plugin database operations and configuration tests
- **`t/db_dependent/RapidoILL/QueuedTask.t`** - Individual queued task object tests
- **`t/db_dependent/RapidoILL/QueuedTasks.t`** - Queued task collection tests

#### Running Tests

```bash
# Get into KTD shell
ktd --name rapido --shell

# Inside KTD, set up environment and run tests
cd /kohadevbox/plugins/rapido-ill
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run all tests
prove -v t/ t/db_dependent/

# Run specific test categories
prove -v t/                    # Unit tests only
prove -v t/db_dependent/       # Database-dependent tests only
prove -v t/RapidoILL/          # Component tests only

# Run individual tests
prove -v t/03-logger-integration.t
prove -v t/RapidoILL/APIHttpClient.t
prove -v t/db_dependent/RapidoILL.t
```

#### Test Coverage Areas

**Logging Integration:**
- Plugin-level Koha::Logger integration
- APIHttpClient HTTP request logging (info, error, debug levels)
- Logger singleton behavior and error handling
- Debug mode configuration testing

**Authentication & HTTP:**
- APIHttpClient token management and refresh
- HTTP request methods (POST, GET, PUT, DELETE)
- Request/response logging and error handling
- Mock API integration testing

**Database Operations:**
- Plugin configuration storage and retrieval
- Queued task management and processing
- Database schema and object relationships
- Transaction isolation and cleanup

**Business Logic:**
- String normalization for ILL data
- CircAction workflow management
- Plugin metadata and method validation
- Configuration parsing and validation

**Backend-Template Correspondence:**
- Dynamic status graph analysis and method extraction
- Backend method implementation verification
- UI action template file existence validation
- Code-template reference consistency checking

## Key Architecture Points

### Configuration System
- YAML config stored in plugin database via `store_data()`/`retrieve_data()`
- `configuration()` method applies defaults and transformations
- **Always set `dev_mode: true` in test configs** to disable external API calls
- Configuration is cached - use `{ recreate => 1 }` to force reload

### Database Models
- Follow Koha patterns: inherit from `Koha::Object`/`Koha::Objects`
- Schema classes auto-generated in `Koha/Schema/Result/`
- Registered in main plugin's BEGIN block
- Use `$plugin->get_queued_tasks()` for collection access

### Testing Patterns
- **Database-dependent tests**: Use transaction isolation (`txn_begin`/`txn_rollback`)
- **Test counting**: Each `subtest` = 1 test (not internal test count)
- **Naming**: Class-based (`RapidoILL.t` for main class) or feature-based (`APIHttpClient.t`)
- **Structure**: Method-based subtests (`configuration() tests`) or feature-based (`Logging tests`)
- **Mocking**: Use `Test::MockObject` for external dependencies (Koha::Logger, HTTP responses)
- **Logger testing**: Mock logger to verify calls are made, don't test Koha::Logger internals
- **HTTP testing**: Mock responses with `is_success()`, `code()`, `message()` methods

## Common Issues & Solutions

### KTD Environment
- **`/.env: No such file or directory`**: Set `KTD_HOME` environment variable
- **Plugin not found**: Check `PLUGINS_DIR` points to parent directory
- **Module loading**: Ensure `PERL5LIB` includes plugin lib directory

### Testing
- **Test plan errors**: Count subtests, not internal tests
- **Database isolation**: Always use transactions in db_dependent tests
- **External API calls**: Set `dev_mode: true` in test configurations
- **Mock warnings**: Use `Test::MockObject` and mock all called methods
- **Logger testing**: Mock logger methods (`debug`, `info`, `error`) to verify calls
- **HTTP response mocking**: Mock `is_success()`, `code()`, `message()` for response objects

### CI/CD
- **GitHub Actions**: No `--proxy` flag needed, separate `up -d` and `--wait-ready`
- **Environment setup**: Use `$GITHUB_PATH` not sudo for PATH modification
- **Multi-version testing**: Uses matrix strategy with dynamic version resolution

## File Structure

```
Koha/Plugin/Com/ByWaterSolutions/RapidoILL/
├── RapidoILL.pm                    # Main plugin class
├── templates/                      # Plugin templates
├── lib/
│   ├── RapidoILL/
│   │   ├── Backend.pm              # ILL backend
│   │   ├── APIHttpClient.pm        # OAuth2-enabled HTTP client with logging
│   │   ├── Client.pm               # API client
│   │   ├── StringNormalizer.pm     # String normalization utilities
│   │   ├── QueuedTask.pm           # Individual task object
│   │   ├── QueuedTasks.pm          # Task collection
│   │   └── ...                     # Other business logic
│   └── Koha/Schema/Result/         # Auto-generated schema classes
├── scripts/                        # System service scripts
└── t/
    ├── 00-load.t                   # Module loading tests
    ├── 01-constraint.t             # CircAction object tests
    ├── 02-plugin-methods.t         # Plugin metadata and methods
    ├── 03-logger-integration.t     # Koha::Logger integration tests
    ├── 04-backend-templates.t      # Backend action-template correspondence tests
    ├── RapidoILL/
    │   ├── APIHttpClient.t         # APIHttpClient authentication and logging tests
    │   └── StringNormalizer.t      # String normalization tests
    └── db_dependent/
        ├── RapidoILL.t             # Main plugin database tests
        └── RapidoILL/
            ├── QueuedTask.t        # Individual task object tests
            └── QueuedTasks.t       # Task collection tests
```

## Operational Setup

### Cron Jobs
```bash
# One entry per pod, every 5 minutes
*/5 * * * * cd /var/lib/koha/<instance>/plugins; PERL5LIB=/usr/share/koha/lib:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:. perl Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/sync_requests.pl --pod <pod_name>
```

### Task Queue Service
```bash
# Copy and configure systemd service
cp scripts/rapido_task_queue.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable rapido_task_queue.service
```

## Development Workflow

```bash
# Get into KTD shell
ktd --name rapido --shell

# Inside KTD:
cd /kohadevbox/koha && perl misc/devel/install_plugins.pl  # Reinstall plugin
cd /kohadevbox/plugins/rapido-ill                          # Go to plugin dir
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.
prove -v t/ t/db_dependent/                                # Run tests
```

## Packaging Notes

- **Packaging**: Handled by gulpfile (only copies `Koha/` directory)
- **Sample files**: `cron.sample` excluded automatically (not in `Koha/`)
- **Releases**: Only triggered by version tags (`v*.*.*`)
- **CI**: Tests run on every push, packaging only on tags
