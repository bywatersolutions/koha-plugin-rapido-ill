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
```bash
# Get into KTD shell
ktd --name rapido --shell

# Inside KTD, set up environment and run tests
cd /kohadevbox/plugins/rapido-ill
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run tests (usual prove commands)
prove -v t/ t/db_dependent/
prove -v t/db_dependent/RapidoILL.t
prove -v t/00-load.t
```

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
- **Naming**: Class-based (`RapidoILL.t` for main class)
- **Structure**: Method-based subtests (`configuration() tests`)

## Common Issues & Solutions

### KTD Environment
- **`/.env: No such file or directory`**: Set `KTD_HOME` environment variable
- **Plugin not found**: Check `PLUGINS_DIR` points to parent directory
- **Module loading**: Ensure `PERL5LIB` includes plugin lib directory

### Testing
- **Test plan errors**: Count subtests, not internal tests
- **Database isolation**: Always use transactions in db_dependent tests
- **External API calls**: Set `dev_mode: true` in test configurations

### CI/CD
- **GitHub Actions**: No `--proxy` flag needed, separate `up -d` and `--wait-ready`
- **Environment setup**: Use `$GITHUB_PATH` not sudo for PATH modification
- **Multi-version testing**: Uses matrix strategy with dynamic version resolution

## File Structure

```
Koha/Plugin/Com/ByWaterSolutions/RapidoILL/
├── RapidoILL.pm                    # Main plugin class
├── lib/
│   ├── RapidoILL/
│   │   ├── QueuedTask.pm           # Individual task model
│   │   ├── QueuedTasks.pm          # Task collection
│   │   ├── Client.pm               # API client
│   │   └── ...                     # Other business logic
│   └── Koha/Schema/Result/         # Auto-generated schema classes
├── scripts/                        # System service scripts
└── t/
    ├── 00-load.t                   # Unit tests
    ├── 01-constraint.t             # Unit tests
    ├── 02-plugin-methods.t         # Unit tests
    └── db_dependent/
        └── RapidoILL.t             # Database-dependent tests
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
