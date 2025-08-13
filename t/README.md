# Rapido ILL Plugin Tests

This directory contains tests for the Rapido ILL plugin.

## Quick Testing Commands

```bash
# In KTD environment - set up first:
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run all tests
prove -v t/ t/db_dependent/

# Run specific test files
prove -v t/db_dependent/RapidoILL.t
prove -v t/00-load.t
```

## Test Structure

### Unit Tests (`t/`)
- `00-load.t` - Module loading tests
- `01-constraint.t` - Database constraint and object tests
- `02-plugin-methods.t` - Plugin method availability tests

### Database-Dependent Tests (`t/db_dependent/`)
- `RapidoILL.t` - Tests for Koha::Plugin::Com::ByWaterSolutions::RapidoILL class methods

## Running Tests

### In KTD Environment

```bash
# Set up the environment
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run all tests (unit + db_dependent)
prove -v t/ t/db_dependent/

# Run only unit tests
prove -v t/

# Run only database-dependent tests
prove -v t/db_dependent/

# Run individual tests
prove -v t/00-load.t
prove -v t/db_dependent/RapidoILL.t
```

### In GitHub Actions

Tests are automatically run on:
- Push to any branch
- Pull requests to main branch
- Daily scheduled runs
- Tagged releases

The CI workflow:
1. Sets up KTD with plugins support
2. Installs the plugin
3. Runs all tests in the `t/` directory
4. Runs all tests in the `t/db_dependent/` directory
5. Runs additional validation scripts

## Database-Dependent Tests

Database-dependent tests use Koha's testing framework:
- Use `t::lib::TestBuilder` for creating test data
- Use `t::lib::Mocks` for mocking system preferences
- Wrap tests in database transactions for isolation
- Follow Koha's testing patterns and conventions

### Key Features:
- **Transaction isolation**: Each test file runs in its own transaction
- **Test data**: Uses TestBuilder to create consistent test data
- **Mocking**: Uses Koha's mocking utilities for system preferences
- **dev_mode**: Tests set `dev_mode: true` to disable external API calls

### Important Testing Notes:
- **Test counting**: Each `subtest` counts as 1 test, regardless of internal tests
- **Naming convention**: Use class-based names (`RapidoILL.t` for main class)
- **Method organization**: Group tests by method (`configuration() tests`)
- **Configuration**: Always use `dev_mode: true` in test configs

## Requirements

- Koha Testing Docker (KTD) environment
- Plugin installed via `misc/devel/install_plugins.pl`
- Proper PERL5LIB setup to include plugin libraries
- Database access for db_dependent tests

## Troubleshooting

### Common Issues:
- **Module not found**: Check PERL5LIB includes plugin lib directory
- **Database errors**: Ensure plugin is installed and schema is registered
- **Test plan errors**: Remember each subtest counts as 1 test
- **External API calls**: Use `dev_mode: true` in test configurations
