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
prove -v -r -s t/                          # All tests (recursive + shuffle)
prove -v t/                                # Unit tests only
prove -v t/db_dependent/                   # Database-dependent only
prove -v t/db_dependent/RapidoILL.t        # Main plugin test
prove -v t/db_dependent/RapidoILL/         # Task queue tests
prove -v t/RapidoILL/                      # RapidoILL utility tests

# Run new FINAL_CHECKIN tests
prove -v t/RapidoILL/Backend/              # Backend action tests
prove -v t/RapidoILL/BorrowingWorkflowIntegration.t  # Workflow integration tests
```

## Test Structure

### Unit Tests (`t/`)
- `00-load.t` - Module loading tests
- `01-constraint.t` - Database constraint and object tests  
- `02-plugin-methods.t` - Plugin method availability tests
- `RapidoILL/`
  - `StringNormalizer.t` - Tests for RapidoILL::StringNormalizer utility class
  - `APIHttpClient.t` - HTTP client functionality tests
  - `Exceptions.t` - Exception handling tests
  - `BorrowingWorkflowIntegration.t` - Complete borrowing workflow integration tests
  - `Backend/`
    - `BorrowerActions.t` - Tests for borrower-side circulation actions
    - `LenderActions.t` - Tests for lender-side circulation actions

### Database-Dependent Tests (`t/db_dependent/`)
- `RapidoILL.t` - Tests for main plugin class methods (configuration, etc.)
- `RapidoILL_sync_circ_requests.t` - Circulation request synchronization tests
- `RapidoILL_add_or_update_attributes.t` - Attribute management tests
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

### FINAL_CHECKIN Functionality (New)
- **BorrowerActions**: Tests `borrower_final_checkin` method and FINAL_CHECKIN handling
- **LenderActions**: Tests `lender_final_checkin` method and consistency with borrower
- **Workflow Integration**: Tests complete 5-step borrowing workflow with real mock API data

#### FINAL_CHECKIN Test Coverage:
- ✅ `FINAL_CHECKIN` properly mapped in `BorrowerActions`
- ✅ `borrower_final_checkin` sets ILL request status to `'COMP'`
- ✅ No exceptions thrown for `FINAL_CHECKIN` in borrower context
- ✅ Consistent behavior between borrower and lender perspectives
- ✅ Complete borrowing workflow validation (PATRON_HOLD → FINAL_CHECKIN)
- ✅ Real mock API data structure compatibility

## Directory Structure

```
t/
├── 00-load.t                    # Module loading
├── 01-constraint.t              # Database constraints  
├── 02-plugin-methods.t          # Plugin methods
├── RapidoILL/                   # RapidoILL namespace tests
│   ├── StringNormalizer.t       # String utility tests
│   ├── APIHttpClient.t          # HTTP client tests
│   ├── Exceptions.t             # Exception handling tests
│   ├── BorrowingWorkflowIntegration.t  # Workflow integration tests
│   └── Backend/                 # Backend action tests
│       ├── BorrowerActions.t    # Borrower circulation actions
│       └── LenderActions.t      # Lender circulation actions
└── db_dependent/                # Database-dependent tests
    ├── RapidoILL.t              # Main plugin tests
    ├── RapidoILL_sync_circ_requests.t     # Sync tests
    ├── RapidoILL_add_or_update_attributes.t  # Attribute tests
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
- **Use `prove -r -s t/` for best testing**: recursive finds all tests, shuffle ensures independence
- **Never add shell scripts for running tests** - always use `prove` within KTD
