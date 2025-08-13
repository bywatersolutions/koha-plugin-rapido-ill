# Rapido ILL Plugin Tests

This directory contains tests for the Rapido ILL plugin.

## Running Tests

### In KTD Environment

```bash
# Set up the environment
export PERL5LIB=$PERL5LIB:Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:.

# Run all tests
prove -v t/

# Run individual tests
prove -v t/00-load.t
prove -v t/01-constraint.t
prove -v t/02-plugin-methods.t
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
4. Runs additional validation scripts

## Test Files

- `00-load.t` - Module loading tests
- `01-constraint.t` - Database constraint and object tests
- `02-plugin-methods.t` - Plugin method availability tests

## Requirements

- Koha Testing Docker (KTD) environment
- Plugin installed via `misc/devel/install_plugins.pl`
- Proper PERL5LIB setup to include plugin libraries
