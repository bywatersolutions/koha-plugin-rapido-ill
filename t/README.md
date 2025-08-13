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
prove -v t/ t/db_dependent/           # All tests
prove -v t/                           # Unit tests only
prove -v t/db_dependent/              # Database-dependent only
prove -v t/db_dependent/RapidoILL.t   # Specific test
```

## Test Structure

### Unit Tests (`t/`)
- `00-load.t` - Module loading tests
- `01-constraint.t` - Database constraint and object tests
- `02-plugin-methods.t` - Plugin method availability tests
- `StringNormalizer.t` - Tests for RapidoILL::StringNormalizer utility class

### Database-Dependent Tests (`t/db_dependent/`)
- `RapidoILL.t` - Tests for Koha::Plugin::Com::ByWaterSolutions::RapidoILL class methods

## GitHub Actions

Tests run automatically on push/PR using the same KTD environment.

## Requirements

- KTD environment (required for all tests)
- Plugin installed via `misc/devel/install_plugins.pl`
