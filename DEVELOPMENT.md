# Rapido ILL Plugin - Development Guide

Comprehensive development documentation for the Rapido ILL plugin, including setup, testing, and architecture notes.

## API Integration

### OAuth Configuration

**OAuth Scope**: The plugin uses `innreach_tp` as the OAuth scope in APIHttpClient.pm. 

**Important**: This scope name is **correct and required by Rapido**. Despite the "innreach" naming, this is the actual scope that Rapido expects for third-party integrations. Do not change this value.

```perl
# In APIHttpClient.pm - DO NOT MODIFY
$self->{scope} = "innreach_tp";  # Required by Rapido API
```

## Code Quality Standards

### Testing Standards

**Test File Organization:**
- Database-dependent tests for `a_method` in class `Some::Class` go in `t/db_dependent/Some/Class.t`
- Main subtest titled `'a_method() tests'` contains all tests for that method
- Inner subtests have descriptive titles for specific behaviors being tested

**Test File Structure:**
```perl
use Modern::Perl;
use Test::More tests => N;  # N = number of main subtests + use_ok
use Test::Exception;
use Test::MockModule;
use Test::MockObject;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Mocks::Logger;

BEGIN {
    use_ok('Some::Class');
}

# Global variables for entire test file
my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $logger  = t::lib::Mocks::Logger->new();

subtest 'a_method() tests' => sub {
    plan tests => 3;  # Number of individual tests
    
    $schema->storage->txn_begin;
    $logger->clear();
    
    # Test implementation - all tests for this method
    
    $schema->storage->txn_rollback;
};

# OR if multiple behaviors need testing:

subtest 'a_method() tests' => sub {
    plan tests => 2;  # Number of inner subtests
    
    subtest 'Successful operations' => sub {
        plan tests => 3;  # Number of individual tests
        
        $schema->storage->txn_begin;
        $logger->clear();
        
        # Test implementation
        
        $schema->storage->txn_rollback;
    };
    
    subtest 'Error conditions' => sub {
        plan tests => 2;
        
        $schema->storage->txn_begin;
        
        # Error test implementation
        
        $schema->storage->txn_rollback;
    };
};
```

**Transaction Rules:**
- Main subtest must be wrapped in transaction if only one behavior tested
- Each inner subtest wrapped in transaction if multiple behaviors tested
- Never nest transactions

**Global Variables:**
- `$schema`: Database schema object (global to test file)
- `$builder`: TestBuilder instance (global to test file)  
- `$logger`: Logger mock instance (global to test file)

**Transaction Management:**
- Always use `$schema->storage->txn_begin` at start of subtest
- Always use `$schema->storage->txn_rollback` at end of subtest
- Clear logger with `$logger->clear()` before tests that check logging

### Mandatory Pre-Commit Workflow

**CRITICAL**: All code must be formatted with Koha's tidy.pl before committing.

#### Required Steps Before Every Commit:

1. **Format code with Koha tidy.pl**:
   ```bash
   ktd --name rapido --shell --run "cd /kohadevbox/plugins/rapido-ill && /kohadevbox/koha/misc/devel/tidy.pl [modified_files...]"
   ```

2. **Remove all .bak files**:
   ```bash
   find . -name "*.bak" -delete
   ```

3. **Run tests to ensure formatting didn't break anything**:
   ```bash
   ktd --name rapido --shell --run "cd /kohadevbox/plugins/rapido-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/rapido-ill/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:/kohadevbox/plugins/rapido-ill:. && prove -lr t/"
   ```

4. **Commit with clean, formatted code**:
   ```bash
   git add .
   git commit -m "Your commit message"
   ```

**Note**: All modified Perl files (.pm) and test files (.t) must be run through tidy.pl before committing to ensure consistent code formatting across the project.

#### Standard Commit Sequence:

```bash
# 1. Make your code changes
# ... edit files ...

# 2. Format with Koha tidy.pl
ktd --name rapido --shell --run "cd /kohadevbox/plugins/rapido-ill && /kohadevbox/koha/misc/devel/tidy.pl Koha/Plugin/Com/ByWaterSolutions/RapidoILL.pm"

# 3. Clean up backup files
find . -name "*.bak" -delete

# 4. Verify tests still pass
ktd --name rapido --shell --run "cd /kohadevbox/plugins/rapido-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/rapido-ill/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:/kohadevbox/plugins/rapido-ill:. && prove -lr t/"

# 5. Commit
git add .
git commit -m "[#XX] Your descriptive commit message"
```

#### Benefits of This Workflow:

- ✅ **Consistent formatting**: All code follows Koha standards
- ✅ **Clean commits**: No backup file pollution in git history
- ✅ **Professional quality**: Matches Koha project standards
- ✅ **Maintainable codebase**: Uniform style across all files
- ✅ **Easy reviews**: Reviewers focus on logic, not formatting

#### Configuration:

The repository includes `.perltidyrc` copied from Koha's main repository to ensure consistent formatting standards.

### Quality Assurance Tools

**NEW**: As of [#115], QA tools configuration added for automated code quality checks.

#### Spell Checking
- `.codespell-ignore` file for managing false positives in spell checking
- Integrated with Koha's QA toolchain for consistent vocabulary

#### Koha QA Integration  
- `.kohaqarc` configuration file for Koha QA tools integration
- Ensures plugin code meets Koha community standards
- Automated checks for common coding issues and style violations

## Known Issues and Workarounds

### ILL Request Status Setting (Bug #40682)

**Issue**: Koha's ILL request status handling has a design flaw where the `->status()` method performs an implicit `->store()` call, making it impossible to set both data fields and status in a single database transaction.

**Upstream Bug**: https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40682

**Problem**: When you need to update both data fields and status on an ILL request, you cannot do:
```perl
# ❌ WRONG - This doesn't work as expected
$req->set({
    biblio_id => $biblio_id,
    status    => 'NEW_STATUS'  # This gets ignored!
})->store();
```

**Current Workaround**: Always use separate calls for data and status:
```perl
# ✅ CORRECT - Separate data and status setting
$req->set({
    biblio_id => $biblio_id,
    due_date  => $due_date,
    # ... other data fields
});

$req->status('NEW_STATUS')->store();  # Explicit store() for future-proofing
```

**Note**: We explicitly call `->store()` after `->status()` even though `->status()` currently does an implicit store. This ensures the code will continue to work correctly if/when the upstream bug is fixed and `->status()` no longer performs the implicit store operation.

**Problematic Locations**: The following files still use the incorrect pattern and should be updated:

1. **BorrowerActions.pm:219-224** (Legacy code):
```perl
$req->set({
    biblio_id => $item->biblionumber,
    status    => 'B_ITEM_SHIPPED',  # ❌ This gets ignored
})->store();
```

**Fixed Locations**: The following files use the correct pattern:

1. **ActionHandler/Borrower.pm** - Uses separate data and status calls
2. **ActionHandler/Lender.pm** - Uses separate data and status calls
3. **Backend/LenderActions.pm** - Uses separate status calls

## HTTP Logging Implementation

### Enhanced Logging Across All HTTP Verbs

**Implementation**: All HTTP verb methods (POST, PUT, GET, DELETE) in `APIHttpClient.pm` now include enhanced error and debug logging.

**Logging Pattern**:
```perl
if ( $self->logger ) {
    if ( $response->is_success ) {
        $self->logger->info( "{VERB} request successful: " . $response->code . " " . $response->message );
    } else {
        $self->logger->error(
            "{VERB} request failed: " . $response->code . " " . $response->message . " to " . $endpoint );
        
        # In debug mode, log the full response content for troubleshooting
        if ( $self->logger->can('debug') ) {
            my $content = $response->decoded_content || $response->content || 'No content';
            $self->logger->debug( "{VERB} request failed response body: " . $content );
            
            # Also log request headers if available for debugging
            if ( $response->request ) {
                $self->logger->debug( "{VERB} request headers: " . $response->request->headers->as_string );
            }
        }
    }
}
```

**Benefits**:
- **Production Debugging**: Actual API error responses instead of blessed object references
- **Complete HTTP Context**: Full request/response information available
- **Performance Conscious**: Debug details only logged when logger supports debug level
- **Consistent Experience**: Same detailed logging across all HTTP operations

**Example Enhanced Logging**:
```
[ERROR] POST request failed: 400 Bad Request to https://dev03-na.alma.exlibrisgroup.com/view/broker/circ/01CUY0000031/borrowercancel
[DEBUG] POST request failed response body: {"error": "Request cannot be cancelled", "reason": "Item already shipped"}
[DEBUG] POST request headers: Authorization: Bearer [token]...
```

### Backend Exception Logging Enhancement

**Implementation**: Enhanced `RequestFailed` exception logging in `Backend.pm` with detailed response content.

**Pattern**:
```perl
} catch {
    $self->{plugin}->logger->warn("[method_name] $_");
    my $message = "$_";
    if ( ref($_) eq 'RapidoILL::Exception::RequestFailed' ) {
        my $response_content = $_->response->decoded_content || $_->response->content || 'No response content';
        my $status_line = $_->response->status_line || 'Unknown status';
        $message = "$_ | " . $_->method . " - HTTP " . $status_line . " - Response: " . $response_content;
        
        # In debug mode, log additional details
        if ( $self->{plugin}->logger->can('debug') ) {
            $self->{plugin}->logger->debug("[method_name] Full HTTP response details:");
            $self->{plugin}->logger->debug("[method_name] Status: " . $status_line);
            $self->{plugin}->logger->debug("[method_name] Headers: " . $_->response->headers->as_string);
            $self->{plugin}->logger->debug("[method_name] Content: " . $response_content);
        }
    }
}
```

## Testing Infrastructure

### APIHttpClient Testing Patterns

**Required Imports**:
```perl
use Test::More tests => N;
use Test::Exception;
use Test::MockModule;
use HTTP::Response;
use HTTP::Request;
use JSON qw(encode_json);

use t::lib::Mocks;
use t::lib::Mocks::Logger;

BEGIN {
    unshift @INC, 'Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib';
    use_ok('RapidoILL::APIHttpClient');
    use_ok('Koha::Plugin::Com::ByWaterSolutions::RapidoILL');
    use_ok('RapidoILL::Exceptions');
}
```

**Mandatory Plugin Parameter**:
```perl
# ✅ CORRECT - Always include plugin parameter
my $plugin = Koha::Plugin::Com::ByWaterSolutions::RapidoILL->new();
my $client = RapidoILL::APIHttpClient->new({
    base_url      => 'https://test.example.com',
    client_id     => 'test_client',
    client_secret => 'test_secret',
    plugin        => $plugin,  # MANDATORY
    dev_mode      => 1,
});
```

### LWP::UserAgent Mocking for HTTP Client Testing

**Critical Pattern**:
```perl
# Mock BEFORE client instantiation
my $ua_mock = Test::MockModule->new('LWP::UserAgent');
my $mock_ua = bless {}, 'LWP::UserAgent';

$ua_mock->mock('new', sub { return $mock_ua; });
$ua_mock->mock('request', sub {
    my $response = HTTP::Response->new(200, 'OK');
    $response->content(encode_json({
        access_token => 'test_token',
        expires_in   => 3600,
    }));
    $response->header('Content-Type', 'application/json');
    return $response;
});

# NOW create the client
my $client = RapidoILL::APIHttpClient->new({...});

# Test functionality
my $result = $client->refresh_token();

# Clean up between subtests
$ua_mock->unmock_all();
```

**Key Points**:
- Mock `LWP::UserAgent->new()` constructor AND `request()` method
- Set up mocks BEFORE creating APIHttpClient instances
- Use `unmock_all()` between subtests to prevent mock persistence
- Create realistic HTTP::Response objects with proper content and headers

### Logger Testing with t::lib::Mocks::Logger

**Setup Pattern**:
```perl
# Set up mock logger
my $logger = t::lib::Mocks::Logger->new;

# Create client and assign logger
my $client = RapidoILL::APIHttpClient->new({...});
$client->{logger} = $logger;

$logger->clear();

# Perform operations that generate logs
$client->some_method();

# Verify logging
$logger->info_like(qr/Expected info message/, 'Info log verification');
$logger->error_like(qr/Expected error message/, 'Error log verification');
$logger->debug_like(qr/Expected debug message/, 'Debug log verification');

# Count logs by level
is($logger->count('error'), 0, 'No error logs expected');
```

### Exception Testing Patterns

**Working Pattern for OAuth2 Exceptions**:
```perl
# Import exceptions in BEGIN block
BEGIN {
    use_ok('RapidoILL::Exceptions');
}

# Test exception with eval block (more reliable than throws_ok)
my $exception_caught = 0;
my $exception_message = '';

eval {
    $client->method_that_should_fail();
};

if (my $error = $@) {
    $exception_caught = 1;
    $exception_message = "$error";
}

ok($exception_caught, 'Exception was thrown');
like($exception_message, qr/Expected error pattern/, 'Exception message correct');
```

### Test Structure Best Practices

**Subtest Organization**:
```perl
subtest 'refresh_token() tests' => sub {
    plan tests => 3;

    subtest 'Successful token refresh' => sub {
        plan tests => 6;
        
        # Set up fresh mocks for this scenario
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        # ... mock setup
        
        # Test logic
        # ... assertions
        
        # Clean up
        $ua_mock->unmock_all();
    };

    subtest 'Failed token refresh' => sub {
        plan tests => 4;
        
        # Fresh mocks for failure scenario
        my $ua_mock = Test::MockModule->new('LWP::UserAgent');
        # ... different mock setup
        
        # Test logic
        # ... assertions
        
        # Clean up
        $ua_mock->unmock_all();
    };
};
```

### LenderActions Testing Best Practices

**Method-Level Testing Pattern**:
```perl
# Test LenderActions methods directly instead of going through backend
lives_ok {
    $plugin->get_lender_actions($pod)->process_renewal_decision(
        $ill_request,
        {
            approve        => 1,
            new_due_date   => dt_from_string('2025-12-31'),
            client_options => { skip_api_request => 1 }
        }
    );
} 'Method executes without throwing exceptions';
```

**Real Test Data Setup**:
```perl
# Create real test objects instead of complex mocking
my $item     = $builder->build_sample_item({ itype => $itemtype->itemtype });
my $checkout = $builder->build_object({
    class => 'Koha::Checkouts',
    value => { itemnumber => $item->itemnumber }
});

# Add proper attributes to ILL request
$plugin->add_or_update_attributes({
    request    => $ill_request,
    attributes => {
        circId      => 'TEST_CIRC_001',
        pod         => 'test-pod',
        itemId      => $item->itemnumber,
        checkout_id => $checkout->id,
    }
});
```

**Exception Handling in Methods**:
```perl
# Wrap methods in try/catch for proper error handling
return try {
    Koha::Database->schema->storage->txn_do(sub {
        # Method implementation
    });
    return $self;
} catch {
    RapidoILL::Exception->throw(
        sprintf("Unhandled exception: %s", $_)
    );
}
```

**Key Principles**:
- **Direct method testing**: Test LenderActions methods directly, not through backend layer
- **Real data over mocking**: Use actual Koha objects (checkouts, items) instead of complex mocks
- **Skip API calls**: Use `skip_api_request => 1` in client_options instead of mocking HTTP
- **Exception safety**: Wrap methods in try/catch blocks to capture and handle errors properly
- **Performance optimization**: Use `$self->{pod}` instead of `get_req_pod($req)` calls

### Common Testing Pitfalls

1. **Missing Plugin Parameter**: APIHttpClient requires `plugin` parameter - always provide it
2. **Mock Timing**: Set up LWP::UserAgent mocks BEFORE creating APIHttpClient instances
3. **Mock Persistence**: Use `unmock_all()` between subtests to avoid interference
4. **Exception Handling**: Use eval blocks for complex exception testing instead of throws_ok
5. **Logger Assignment**: Assign mocked logger to `$client->{logger}`, not during construction

### Running Tests

```bash
# In KTD environment
ktd --name rapido --shell --run "cd /kohadevbox/plugins/rapido-ill && export PERL5LIB=/kohadevbox/koha:/kohadevbox/plugins/rapido-ill/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/lib:/kohadevbox/plugins/rapido-ill:. && prove -v t/RapidoILL/APIHttpClient.t"
```
4. **Backend/BorrowerActions.pm** - Most methods use correct pattern

**Action Required**: Until Bug #40682 is resolved upstream, all ILL request updates must use the separate call pattern. Legacy code should be updated when touched.

## Logging

The RapidoILL plugin uses Koha's standard logging system for consistent log management and integration with Koha's log4perl configuration.

### Logger Access

All plugin components have access to a centralized logger instance:

```perl
# In main plugin methods
$self->logger->warn("Warning message");
$self->logger->info("Info message");
$self->logger->error("Error message");
$self->logger->debug("Debug message");

# In Backend, ActionHandler, and other components
$self->{plugin}->logger->warn("Warning from component");
```

### Logger Configuration

The logger is configured with:
- **Interface**: `api` (for API-related logging)
- **Category**: `rapidoill` (for filtering RapidoILL-specific logs)
- **Fallback**: Graceful degradation if Koha::Logger fails

### Logging Best Practices

#### 1. Use Appropriate Log Levels

```perl
# ✅ CORRECT - Use appropriate levels
$self->logger->debug("Processing circId: $circ_id");           # Development info
$self->logger->info("ILL request created: id=$req_id");       # Important events
$self->logger->warn("Missing checkout_id for request $id");   # Potential issues
$self->logger->error("Failed to process request: $error");    # Actual errors
```

#### 2. Include Context Information

```perl
# ✅ CORRECT - Include relevant context
$self->logger->warn(
    sprintf(
        "[%s][%s]: Request %s missing required attribute '%s'",
        $component, $method, $req->id, $attribute_name
    )
);

# ❌ AVOID - Vague messages without context
$self->logger->warn("Missing attribute");
```

#### 3. Use Structured Messages

```perl
# ✅ CORRECT - Structured for parsing/filtering
$self->logger->info(
    sprintf(
        "ILL request updated: circId=%s, status='%s', ill_request_id=%s",
        $data->{circId}, $data->{circStatus}, $req->id
    )
);
```

#### 4. Component Prefixes

Use consistent prefixes to identify the source component:

```perl
# Backend operations
$self->{plugin}->logger->warn("[item_shipped] $_");

# ActionHandler operations  
$self->{plugin}->logger->warn("[lender_actions][item_received]: $_");

# Main plugin operations
$self->logger->error("Error processing circId=$circ_id: $error");
```

### Log Filtering

Logs can be filtered by category in Koha's log4perl configuration:

```perl
# In koha-conf.xml or log4perl.conf
log4perl.logger.rapidoill = DEBUG, RAPIDOILL
log4perl.appender.RAPIDOILL = Log::Log4perl::Appender::File
log4perl.appender.RAPIDOILL.filename = /var/log/koha/rapidoill.log
```

### Testing Logger Usage

In tests, mock the logger to verify logging behavior:

```perl
# Mock logger for testing
my $mock_logger = Test::MockObject->new();
$mock_logger->mock('warn', sub { return; });
$mock_logger->mock('info', sub { return; });
$mock_logger->mock('error', sub { return; });
$mock_logger->mock('debug', sub { return; });

$mock_plugin->mock('logger', sub { return $mock_logger; });
```

### Migration from rapido_warn

**Deprecated**: The old `rapido_warn()` method has been removed. Use the logger instead:

```perl
# ❌ OLD - Deprecated (removed)
$self->rapido_warn("Warning message");

# ✅ NEW - Use logger
$self->logger->warn("Warning message");
```

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

#### Cancellation Workflows:

**Borrowing Cancellation (2 Steps):**
1. `CREATED` ← `PATRON_HOLD` - Initial borrowing request
2. `CANCELED` ← `BORROWING_SITE_CANCEL` - Borrower cancels request

**Lending Cancellation (2 Steps):**
1. `CREATED` ← `ITEM_HOLD` - Initial lending request
2. `COMPLETED` ← `OWNING_SITE_CANCEL` - Lender cancels request

#### Lending Scenario:
- `lending_initial`: `circStatus: CREATED, lastCircState: ITEM_HOLD`
- `lending_shipped`: `circStatus: ACTIVE, lastCircState: ITEM_SHIPPED`
- `lending_in_transit`: `circStatus: ACTIVE, lastCircState: ITEM_IN_TRANSIT`
- `lending_final_checkin`: `circStatus: COMPLETED, lastCircState: FINAL_CHECKIN`

#### Cancellation Scenarios:

**Borrowing Cancellation (2 Steps):**
- `borrowing_cancel_initial`: `circStatus: CREATED, lastCircState: PATRON_HOLD`
- `borrowing_site_cancel`: `circStatus: CANCELED, lastCircState: BORROWING_SITE_CANCEL`

**Lending Cancellation (2 Steps):**
- `lending_cancel_initial`: `circStatus: CREATED, lastCircState: ITEM_HOLD`
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
- **`t/00-load.t`** - Basic module loading tests (16 modules)
- **`t/01-constraint.t`** - CircAction and CircActions object tests
- **`t/02-plugin-methods.t`** - Plugin metadata and core method tests
- **`t/03-logger-integration.t`** - Koha::Logger integration and plugin-level logging tests
- **`t/04-backend-templates.t`** - Backend action-template correspondence tests

**Component Tests (t/RapidoILL/):**
- **`t/RapidoILL/APIHttpClient.t`** - APIHttpClient authentication and HTTP request logging tests
- **`t/RapidoILL/StringNormalizer.t`** - String normalization and validation tests
- **`t/RapidoILL/Exceptions.t`** - Exception handling tests (17 exception classes)
- **`t/RapidoILL/Backend/BorrowerActions.t`** - Borrower-side circulation actions including FINAL_CHECKIN
- **`t/RapidoILL/Backend/LenderActions.t`** - Lender-side circulation actions including FINAL_CHECKIN

**Database-Dependent Tests (t/db_dependent/):**
- **`t/db_dependent/RapidoILL.t`** - Main plugin database operations and configuration tests
- **`t/db_dependent/RapidoILL_sync_circ_requests.t`** - Circulation request synchronization tests
- **`t/db_dependent/RapidoILL_add_or_update_attributes.t`** - Attribute management tests
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
prove -v t/RapidoILL/Backend/BorrowerActions.t
prove -v t/db_dependent/RapidoILL.t
```

#### Test Coverage Areas

**Renewal Notes Functionality:**
- Configurable checkout notes for renewal requests and acceptances
- Integration with Koha's checkout note system
- Test coverage in ActionHandler/Borrower.t and Backend/BorrowerActions.t
- Proper configuration handling and optional behavior

**Pickup Location Strategy:**
- Lending-side pickup location configuration options
- Support for partners_library, homebranch, and holdingbranch strategies
- Unit test coverage for all strategy implementations

**FINAL_CHECKIN Functionality:**
- borrower_final_checkin method with paper trail (B_ITEM_CHECKED_IN → COMP)
- lender_final_checkin method behavior
- FINAL_CHECKIN mapping in both BorrowerActions and LenderActions
- No exceptions thrown for FINAL_CHECKIN in either perspective
- Complete method call sequences and integration testing

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

### ActionHandler Implementation Patterns

#### Adding New Action Handlers

When implementing handlers for new Rapido circulation states:

1. **Status Graph First**: Always add the target status to `Backend.pm` `status_graph()` method before implementing the handler
2. **API-Aligned Naming**: Use status names that align with Rapido API action names (e.g., `OWNING_SITE_CANCEL` → `B_CANCELLED_BY_OWNER`)
3. **Dispatch Mapping**: Add the action to the `$status_to_method` hash in the appropriate ActionHandler class
4. **Method Implementation**: Follow the established patterns for database transactions, logging, and error handling

#### Example Implementation Pattern

```perl
# 1. Add to Backend.pm status_graph()
B_NEW_STATUS => {
    prev_actions   => [],
    id             => 'B_NEW_STATUS',
    name           => 'Description of status',
    ui_method_name => 'Description of status',
    method         => q{},
    next_actions   => ['COMP'],
    ui_method_icon => q{},
},

# 2. Add to ActionHandler dispatch table
my $status_to_method = {
    'RAPIDO_ACTION_NAME' => \&method_name,
    # ...
};

# 3. Implement the method
sub method_name {
    my ( $self, $action ) = @_;
    
    my $req = $action->ill_request;
    
    Koha::Database->new->schema->txn_do(
        sub {
            # Update status
            $req->status('B_NEW_STATUS')->store();
            
            # Add attributes for tracking
            $self->{plugin}->add_or_update_attributes({
                attributes => { tracking_field => \'NOW()' },
                request    => $req,
            });
            
            # Cleanup if needed (with error handling)
            if ( $req->biblio_id ) {
                try {
                    $self->{plugin}->cleanup_virtual_record({
                        biblio_id => $req->biblio_id,
                        request   => $req,
                    });
                } catch {
                    $self->{plugin}->logger->warn("Cleanup failed: $_");
                };
            }
            
            # Log the action
            $self->{plugin}->logger->info(
                sprintf("Action processed for ILL request %d", $req->id)
            );
        }
    );
    
    return;
}
```

#### Testing ActionHandler Methods

Follow the established testing patterns:

```perl
subtest 'method_name() tests' => sub {
    plan tests => 3;
    
    subtest 'basic functionality' => sub {
        # Test core method behavior
    };
    
    subtest 'with additional scenarios' => sub {
        # Test edge cases, cleanup, etc.
    };
    
    subtest 'dispatch mechanism' => sub {
        # Test that action routes correctly through handle_from_action
    };
};
```

**Key Testing Requirements:**
- Use grouped subtests for method-specific tests
- Test both direct method calls and dispatch mechanism
- Verify status changes, attribute updates, and logging
- Use database transactions for isolation
- Test error handling and cleanup scenarios

## Key Architecture Points

### Method Parameter Patterns

**CRITICAL**: Use consistent parameter patterns across all plugin methods.

#### Single Parameter Methods
```perl
# ✅ CORRECT - Single parameter can be passed directly
sub get_borrower_action_handler {
    my ( $self, $pod ) = @_;
    
    RapidoILL::Exception::MissingParameter->throw( param => 'pod' )
        unless $pod;
    
    # Implementation
}

# Usage
my $handler = $plugin->get_borrower_action_handler('test_pod');
```

#### Multiple Parameter Methods
```perl
# ✅ CORRECT - Multiple parameters MUST use hashref
sub get_action_handler {
    my ( $self, $params ) = @_;
    
    $self->validate_params( { required => [qw(pod perspective)], params => $params } );
    
    my $pod = $params->{pod};
    my $perspective = $params->{perspective};
    # Implementation
}

# Usage
my $handler = $plugin->get_action_handler({
    pod => 'test_pod',
    perspective => 'borrower'
});
```

#### Parameter Validation with validate_params
```perl
# ✅ REQUIRED - Always use validate_params for hashref methods
sub method_with_multiple_params {
    my ( $self, $params ) = @_;
    
    $self->validate_params( { 
        required => [qw(param1 param2)], 
        params => $params 
    } );
    
    # Method implementation using $params->{param1}, etc.
}
```

**Benefits of This Pattern:**
- **Consistency**: All methods follow the same parameter conventions
- **Validation**: Centralized parameter validation with clear error messages
- **Extensibility**: Easy to add new parameters without breaking existing calls
- **Readability**: Clear parameter names in method calls
- **Maintainability**: Consistent error handling across the codebase

**When to Use Each Pattern:**
- **Single parameter**: Simple methods with one clear input (IDs, names, etc.)
- **Hashref + validate_params**: Any method with 2+ parameters or optional parameters

**The validate_params Method:**
```perl
sub validate_params {
    my ( $self, $args ) = @_;

    foreach my $param ( @{ $args->{required} } ) {
        RapidoILL::Exception::MissingParameter->throw( param => $param )
            unless defined $args->{params}->{$param};
    }
}
```

This method provides:
- **Consistent error messages** across all plugin methods
- **Proper exception types** (RapidoILL::Exception::MissingParameter)
- **Parameter field information** for debugging
- **Centralized validation logic** that's easy to maintain

#### Backend Actions Method Patterns

**NEW**: As of [#68], all Backend Actions methods follow a standardized signature pattern.

```perl
# ✅ STANDARDIZED - All Backend Actions methods use this pattern
sub method_name {
    my ( $self, $req, $params ) = @_;
    
    $params //= {};
    my $client_options = $params->{client_options} // {};
    
    # Method implementation
    # Use $client_options when calling Rapido client methods
    
    return $self; # Enable method chaining
}
```

**Usage Examples:**
```perl
# Simple usage (no additional parameters)
$actions->cancel_request($ill_request);
$actions->item_shipped($ill_request);
$actions->final_checkin($ill_request);

# With client options for API passthrough
$actions->cancel_request($ill_request, {
    client_options => { timeout => 30, retry => 3 }
});

# Method chaining support
$actions->item_shipped($ill_request)
        ->final_checkin($ill_request);

# BorrowerActions with additional parameters
$actions->borrower_receive_unshipped($ill_request, {
    circId     => 'circ_123',
    attributes => { title => 'Book Title' },
    barcode    => 'BARCODE123',
    client_options => { notify_rapido => 1 }
});
```

**Key Benefits:**
- **Consistent API**: All Backend Actions methods follow the same pattern
- **Request-first**: ILL request object is always the first parameter
- **Optional parameters**: Second parameter is optional hashref for additional data
- **Client options**: Standardized way to pass options to Rapido client calls
- **Method chaining**: All methods return `$self` for fluent interfaces
- **Backward compatible**: Simple calls without params still work

**Migration from Old Patterns:**
```perl
# ❌ OLD - BorrowerActions used hashref-first approach
$actions->item_in_transit({ request => $req });
$actions->borrower_cancel({ request => $req });

# ✅ NEW - Consistent request-first approach
$actions->item_in_transit($req);
$actions->borrower_cancel($req);

# ❌ OLD - LenderActions had no client options support
$actions->cancel_request($req); # No way to pass client options

# ✅ NEW - Consistent client options support
$actions->cancel_request($req, { client_options => $opts });
```

### Configuration System
- YAML config stored in plugin database via `store_data()`/`retrieve_data()`
- `configuration()` method applies defaults and transformations
- **Always set `dev_mode: true` in test configs** to disable external API calls
- Configuration is cached - use `{ recreate => 1 }` to force reload

#### Renewal Notes Configuration

**NEW**: As of [#116], configurable checkout notes for renewal workflows.

```yaml
your_pod_name:
  # ... existing configuration ...
  
  # Optional: Message set as checkout note when renewal is requested
  renewal_request_note: "ILL renewal has been requested from the lending library"
  
  # Optional: Message set as checkout note when renewal is accepted  
  renewal_accepted_note: "ILL renewal has been approved by the lending library"
```

**Behavior:**
- Notes are set using the same mechanism as `opac-issue-note.pl`
- Includes `notedate`, `note`, and `noteseen` fields
- Both configuration entries are optional
- Staff can view and manage notes in checkout details

#### Pickup Location Strategy

**NEW**: As of [#112], lending sites can configure pickup location strategy.

```yaml
your_pod_name:
  lending:
    pickup_location_strategy: partners_library  # or homebranch, holdingbranch
```

**Options:**
- `partners_library`: Use the configured partners library (default)
- `homebranch`: Use the item's home branch
- `holdingbranch`: Use the item's holding branch

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
│   │   ├── Backend/
│   │   │   ├── BorrowerActions.pm  # Borrower-side circulation actions
│   │   │   └── LenderActions.pm    # Lender-side circulation actions
│   │   └── ...                     # Other business logic
│   └── Koha/Schema/Result/         # Auto-generated schema classes
├── scripts/                        # System service scripts
│   ├── run_command.pl              # Command-line tool for individual actions
│   ├── sync_requests.pl            # Sync script for circulation requests
│   ├── task_queue_daemon.pl        # Task queue processing daemon
│   ├── config.pl                   # Configuration management script
│   └── ...                         # Other operational scripts
└── t/
    ├── 00-load.t                   # Module loading tests (16 modules)
    ├── 01-constraint.t             # CircAction object tests
    ├── 02-plugin-methods.t         # Plugin metadata and methods
    ├── 03-logger-integration.t     # Koha::Logger integration tests
    ├── 04-backend-templates.t      # Backend action-template correspondence tests
    ├── RapidoILL/
    │   ├── APIHttpClient.t         # APIHttpClient authentication and logging tests
    │   ├── StringNormalizer.t      # String normalization tests
    │   ├── Exceptions.t            # Exception handling tests (17 classes)
    │   └── Backend/
    │       ├── BorrowerActions.t   # Borrower circulation actions (FINAL_CHECKIN)
    │       └── LenderActions.t     # Lender circulation actions (FINAL_CHECKIN)
    └── db_dependent/
        ├── RapidoILL.t             # Main plugin database tests
        ├── RapidoILL_sync_circ_requests.t      # Sync tests
        ├── RapidoILL_add_or_update_attributes.t # Attribute tests
        └── RapidoILL/
            ├── QueuedTask.t        # Individual task object tests
            └── QueuedTasks.t       # Task collection tests
```
    └── db_dependent/
        ├── RapidoILL.t             # Main plugin database tests
        └── RapidoILL/
            ├── QueuedTask.t        # Individual task object tests
            └── QueuedTasks.t       # Task collection tests
```

## Operational Setup

### Command-Line Tools

#### run_command.pl Script

**NEW**: As of [#117], a command-line script is available for executing individual Rapido ILL actions.

```bash
# Execute lending actions
./run_command.pl --lending --pod dev03-na --request_id 123 --command item_shipped

# Execute borrowing actions  
./run_command.pl --borrowing --pod dev03-na --request_id 456 --command borrower_cancel

# List available commands
./run_command.pl --list_commands

# Skip API calls (useful for cleanup)
./run_command.pl --lending --pod dev03-na --request_id 789 --command final_checkin --skip_api_req
```

**Available Commands:**
- **Lending**: `cancel_request`, `final_checkin`, `item_shipped`, `process_renewal_decision`
- **Borrowing**: `borrower_cancel`, `borrower_renew`, `final_checkin`, `item_in_transit`, `item_received`, `receive_unshipped`, `return_uncirculated`

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
