# Rapido ILL Plugin - Development Guide

Comprehensive development documentation for the Rapido ILL plugin, including setup, testing, and architecture notes.

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
