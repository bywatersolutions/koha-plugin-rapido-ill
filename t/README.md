# Rapido ILL Plugin Tests

This directory contains tests for the Rapido ILL plugin.

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
- Push to main branch
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

## Requirements

- Koha Testing Docker (KTD) environment
- Plugin installed via `misc/devel/install_plugins.pl`
- Proper PERL5LIB setup to include plugin libraries
- Database access for db_dependent tests
