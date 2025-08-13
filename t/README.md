# Rapido ILL Plugin Tests

Tests must be run inside KTD due to database-dependent tests.

## Quick Testing

```bash
# Get into KTD shell
ktd --name rapido --shell

# Inside KTD, set up environment
cd /kohadevbox/plugins/rapido-ill
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run tests (usual prove commands)
prove -v t/ t/db_dependent/                    # All tests
prove -v t/                                    # Unit tests only
prove -v t/db_dependent/                       # Database-dependent only
prove -v t/db_dependent/RapidoILL.t            # Main plugin test
prove -v t/db_dependent/RapidoILL/             # Task queue tests
prove -v t/RapidoILL/                          # RapidoILL utility tests
```

## Test Structure

### Unit Tests (`t/`)
- `00-load.t` - Module loading tests
- `01-constraint.t` - Database constraint and object tests  
- `02-plugin-methods.t` - Plugin method availability tests
- `RapidoILL/`
  - `StringNormalizer.t` - Tests for RapidoILL::StringNormalizer utility class

### Database-Dependent Tests (`t/db_dependent/`)
- `RapidoILL.t` - Tests for main plugin class methods (configuration, etc.)
- `RapidoILL/`
  - `QueuedTask.t` - Tests for RapidoILL::QueuedTask individual object methods
  - `QueuedTasks.t` - Tests for RapidoILL::QueuedTasks collection methods

## Test Coverage

### Core Plugin (44 total tests)
- **Module Loading**: 16 tests - All modules and schema classes load correctly
- **Plugin Methods**: 8 tests - Plugin instantiation and method availability
- **Configuration**: 25 tests - YAML parsing, defaults, caching, error handling
- **Database Constraints**: 3 tests - CircAction object creation and validation

### Task Queue System (19 total tests)
- **QueuedTask Object**: 11 tests - Individual task methods, retry logic, status transitions
- **QueuedTasks Collection**: 8 tests - Collection operations, filtering, method chaining

### Utility Classes (2 total tests)
- **StringNormalizer**: 8 subtests - String processing and normalization methods

## Directory Structure

```
t/
├── 00-load.t                    # Module loading
├── 01-constraint.t              # Database constraints  
├── 02-plugin-methods.t          # Plugin methods
├── RapidoILL/                   # RapidoILL namespace tests
│   └── StringNormalizer.t       # String utility tests
└── db_dependent/                # Database-dependent tests
    ├── RapidoILL.t              # Main plugin tests
    └── RapidoILL/               # RapidoILL namespace db tests
        ├── QueuedTask.t         # Individual task tests
        └── QueuedTasks.t        # Task collection tests
```

## GitHub Actions

Tests run automatically on push/PR using the same KTD environment.

## Requirements

- KTD environment (required for all tests)
- Plugin installed via `misc/devel/install_plugins.pl`
- Test::NoWarnings module (for warning detection)

## Development Notes

- All test files must be executable (`chmod +x`)
- Use proper transaction isolation in database-dependent tests
- Follow Koha's standard test patterns and naming conventions
- Test::NoWarnings automatically adds one test per file for warning detection
