# Mock Rapido API Guide

A configurable mock API service for testing the Rapido ILL plugin without connecting to real Rapido infrastructure.

## Quick Start

```bash
# 1. Bootstrap the testing environment (run once after fresh KTD)
cd /kohadevbox/plugins/rapido-ill/scripts
./bootstrap_rapido_testing.pl

# 2. Start the mock API
./mock_rapido_api.pl --scenario=borrowing --port=3001

# 3. Test the setup (in another terminal)
./test_mock_api.sh

# 4. Run sync against mock API
./run_sync.sh
```

## Bootstrap Script

The `bootstrap_rapido_testing.pl` script sets up everything needed for testing:

- ✅ **Installs the plugin** in Koha
- ✅ **Configures the plugin** with mock API settings  
- ✅ **Creates helper scripts** for testing and sync
- ✅ **Verifies KTD sample data** compatibility
- ✅ **Sets up database** configuration

**Run this once after starting a fresh KTD environment.**

## Starting the Mock API

### Basic Commands

```bash
# Start with default settings (port 3000, no scenario)
./mock_rapido_api.pl

# Start with specific scenario and port
./mock_rapido_api.pl --scenario=borrowing --port=3001

# Start with custom config file
./mock_rapido_api.pl --config=my_custom_config.json --port=8080

# Show help
./mock_rapido_api.pl --help
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--port=N` | Port to run on | 3000 |
| `--config=FILE` | Configuration file | mock_config.json |
| `--scenario=NAME` | Load predefined scenario | none |
| `--help` | Show help message | - |

### Verifying Startup

```bash
# Check if API is running
curl http://localhost:3001/status

# Expected response:
{
  "service": "Mock Rapido API",
  "version": "1.0.0",
  "current_scenario": "borrowing",
  "scenario_step": 0,
  "available_scenarios": ["borrowing", "lending", "mixed"]
}
```

## Writing Custom Scenarios

### Configuration File Structure

The `mock_config.json` file contains two main sections:

```json
{
  "scenarios": {
    "scenario_name": {
      "description": "What this scenario tests",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "response_name"}
      ]
    }
  },
  "responses": {
    "response_name": {
      "data": [
        {
          "circId": "CIRC001",
          "circStatus": "PENDING_PARTNER_RESPONSE",
          "title": "Test Book"
        }
      ]
    }
  }
}
```

### Creating a Custom Scenario

#### Step 1: Define the Scenario Sequence

```json
{
  "scenarios": {
    "overdue_workflow": {
      "description": "Test overdue item handling",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "item_overdue"},
        {"endpoint": "circulation_requests", "response": "notice_sent"},
        {"endpoint": "circulation_requests", "response": "item_returned"}
      ]
    }
  }
}
```

#### Step 2: Define Response Data

```json
{
  "responses": {
    "item_overdue": {
      "data": [
        {
          "circId": "OVERDUE001",
          "requestId": "REQ_OVERDUE_001",
          "circStatus": "ITEM_OVERDUE",
          "itemBarcode": "39999000088888",
          "title": "The Overdue Chronicles",
          "author": "Late Return",
          "patronName": "Forgetful Reader",
          "patronAgencyCode": "CPL",
          "lenderCode": "LENDER001",
          "dueDateTime": "2025-08-01T23:59:59Z",
          "daysOverdue": 13,
          "lastUpdated": "2025-08-14T10:00:00Z"
        }
      ]
    }
  }
}
```

### Required Fields

#### Borrowing Requests (minimum fields):
- `circId` - Unique circulation ID
- `requestId` - Request identifier
- `circStatus` - Current status
- `itemBarcode` - Item barcode
- `title` - Book title
- `patronName` - Patron name
- `patronAgencyCode` - Patron's library
- `lenderCode` - Lending library
- `pickupLocation` - Where patron picks up

#### Lending Requests (minimum fields):
- `circId` - Unique circulation ID
- `requestId` - Request identifier
- `circStatus` - Current status
- `itemBarcode` - Item barcode
- `title` - Book title
- `patronName` - Requesting patron name
- `patronAgencyCode` - Requesting library
- `borrowerCode` - Borrowing library

### Common Status Values

#### Borrowing Statuses:
- `PENDING_PARTNER_RESPONSE` - Waiting for lender
- `ITEM_SHIPPED` - Item sent by lender
- `ITEM_RECEIVED` - Item arrived at pickup location
- `ITEM_CHECKED_OUT` - Patron has the item
- `ITEM_RETURNED` - Patron returned the item
- `ITEM_OVERDUE` - Item is overdue

#### Lending Statuses:
- `PENDING_CHECKOUT` - Waiting to check out to patron
- `ITEM_CHECKED_OUT` - Checked out to requesting patron
- `ITEM_RETURNED` - Returned by patron
- `ITEM_SHIPPED` - Sent back to owning library

## Configuration File Structure

### Complete Example

```json
{
  "scenarios": {
    "renewal_test": {
      "description": "Test item renewal workflow",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "item_due_soon"},
        {"endpoint": "circulation_requests", "response": "renewal_requested"},
        {"endpoint": "circulation_requests", "response": "renewal_approved"}
      ]
    }
  },
  "responses": {
    "item_due_soon": {
      "data": [{
        "circId": "RENEW001",
        "circStatus": "ITEM_CHECKED_OUT",
        "title": "Popular Book",
        "patronName": "Frequent Reader",
        "dueDateTime": "2025-08-16T23:59:59Z",
        "renewalCount": 0,
        "maxRenewals": 2
      }]
    },
    "renewal_requested": {
      "data": [{
        "circId": "RENEW001",
        "circStatus": "RENEWAL_PENDING",
        "title": "Popular Book",
        "patronName": "Frequent Reader",
        "dueDateTime": "2025-08-16T23:59:59Z"
      }]
    },
    "renewal_approved": {
      "data": [{
        "circId": "RENEW001",
        "circStatus": "ITEM_CHECKED_OUT",
        "title": "Popular Book",
        "patronName": "Frequent Reader",
        "dueDateTime": "2025-09-16T23:59:59Z",
        "renewalCount": 1
      }]
    }
  }
}
```

## Predefined Scenarios

### Borrowing Workflow
Simulates a typical borrowing request lifecycle:

1. **Initial**: `PENDING_PARTNER_RESPONSE` - Request pending partner response
2. **Shipped**: `ITEM_SHIPPED` - Item shipped by lender  
3. **Received**: `ITEM_RECEIVED` - Item received and available for patron

```bash
./mock_rapido_api.pl --scenario=borrowing --port=3001
```

### Lending Workflow
Simulates a typical lending request lifecycle:

1. **Initial**: `PENDING_CHECKOUT` - Request pending checkout
2. **Checkout**: `ITEM_CHECKED_OUT` - Item checked out to requesting patron
3. **Returned**: `ITEM_RETURNED` - Item returned and available

```bash
./mock_rapido_api.pl --scenario=lending --port=3001
```

### Mixed Workflow
Returns multiple requests in different states simultaneously:

- One borrowing request (`ITEM_SHIPPED`)
- One lending request (`PENDING_CHECKOUT`)

```bash
./mock_rapido_api.pl --scenario=mixed --port=3001
```

## API Endpoints

### Actual Rapido ILL Endpoints

Based on analysis of `RapidoILL::Client` library:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/view/broker/auth` | Authentication (OAuth2 token) |
| GET | `/view/broker/circ/circrequests` | Main data sync endpoint |
| POST | `/view/broker/circ/:circId/lendercancel` | Lender cancel operation |
| POST | `/view/broker/circ/:circId/lendershipped` | Lender shipped operation |
| POST | `/view/broker/circ/:circId/itemreceived` | Borrower received operation |
| POST | `/view/broker/circ/:circId/itemreturned` | Borrower returned operation |

### Control Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/status` | API status and current scenario |
| POST | `/control/scenario/:name` | Switch to different scenario |
| POST | `/control/reset` | Reset API state |

### Helper Scripts

- **`bootstrap_rapido_testing.pl`** - One-time setup for fresh KTD
- **`test_mock_api.sh`** - Test all API endpoints
- **`run_sync.sh`** - Run sync_requests.pl with proper environment

### Example Responses

#### Status Endpoint
```bash
curl http://localhost:3001/status
```

```json
{
  "service": "Mock Rapido API",
  "version": "1.0.0",
  "uptime": 3600,
  "current_scenario": "borrowing",
  "scenario_step": 2,
  "call_counts": {
    "circulation_requests": 3
  },
  "available_scenarios": ["borrowing", "lending", "mixed"]
}
```

#### Circulation Requests
```bash
curl http://localhost:3001/circulation_requests
```

```json
{
  "data": [
    {
      "circId": "CIRC001",
      "circStatus": "ITEM_SHIPPED",
      "title": "Test Book for Borrowing",
      "patronName": "John Doe",
      "itemBarcode": "39999000001234",
      "lenderCode": "LENDER001",
      "lastUpdated": "2025-08-14T11:00:00Z"
    }
  ],
  "meta": {
    "call_number": 2,
    "scenario": "borrowing",
    "step": 2,
    "timestamp": "2025-08-14T20:30:00Z"
  }
}
```

## Testing Workflows

### Basic Workflow Testing

```bash
# Start API with scenario
./mock_rapido_api.pl --scenario=borrowing --port=3001

# Test progression - each call advances to next step
curl http://localhost:3001/circulation_requests  # Step 1: PENDING_PARTNER_RESPONSE
curl http://localhost:3001/circulation_requests  # Step 2: ITEM_SHIPPED
curl http://localhost:3001/circulation_requests  # Step 3: ITEM_RECEIVED
```

### Switching Scenarios During Testing

```bash
# Switch to lending scenario
curl -X POST http://localhost:3001/control/scenario/lending

# Test lending workflow
curl http://localhost:3001/circulation_requests  # PENDING_CHECKOUT
curl http://localhost:3001/circulation_requests  # ITEM_CHECKED_OUT
curl http://localhost:3001/circulation_requests  # ITEM_RETURNED
```

### Resetting State

```bash
# Reset API state to start over
curl -X POST http://localhost:3001/control/reset

# Verify reset
curl http://localhost:3001/status
```

### Testing Action Endpoints

```bash
# Test lender checkout operation
curl -X POST http://localhost:3001/lender/checkout \
  -H "Content-Type: application/json" \
  -d '{"circId": "CIRC001", "itemBarcode": "39999000001234"}'

# Test borrower received operation  
curl -X POST http://localhost:3001/borrower/received \
  -H "Content-Type: application/json" \
  -d '{"circId": "CIRC001", "itemBarcode": "39999000001234"}'
```

## Integration with Rapido Plugin

### Plugin Configuration

Update your Rapido plugin configuration to point to the mock API:

```yaml
mock-pod:
  base_url: http://localhost:3001
  client_id: mock_client
  client_secret: mock_secret
  server_code: 11747
  partners_library_id: CPL
  partners_category: ILL
  default_item_type: ILL
  # ... other settings remain the same
```

### Running Sync Against Mock API

```bash
# Run sync_requests.pl against the mock pod
perl sync_requests.pl --pod mock-pod

# Run with specific start time
perl sync_requests.pl --pod mock-pod --start_time 1692000000
```

### Testing Complete Workflows

1. **Start Mock API** with desired scenario
2. **Configure plugin** to use mock pod
3. **Run sync script** multiple times to progress through workflow
4. **Verify plugin behavior** at each step
5. **Switch scenarios** to test different conditions

## Examples

### Example 1: Testing Error Conditions

```json
{
  "scenarios": {
    "error_test": {
      "description": "Test error handling",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "network_error"},
        {"endpoint": "circulation_requests", "response": "empty_response"}
      ]
    }
  },
  "responses": {
    "network_error": {
      "error": "Network timeout",
      "status": 500
    },
    "empty_response": {
      "data": []
    }
  }
}
```

### Example 2: Testing Multiple Items

```json
{
  "scenarios": {
    "bulk_test": {
      "description": "Test multiple items processing",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "multiple_items"}
      ]
    }
  },
  "responses": {
    "multiple_items": {
      "data": [
        {
          "circId": "BULK001",
          "circStatus": "ITEM_SHIPPED",
          "title": "Book 1",
          "patronName": "Patron 1"
        },
        {
          "circId": "BULK002",
          "circStatus": "PENDING_CHECKOUT", 
          "title": "Book 2",
          "patronName": "Patron 2"
        }
      ]
    }
  }
}
```

### Example 3: Testing Edge Cases

```json
{
  "scenarios": {
    "edge_cases": {
      "description": "Test unusual data conditions",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "unicode_data"},
        {"endpoint": "circulation_requests", "response": "missing_fields"}
      ]
    }
  },
  "responses": {
    "unicode_data": {
      "data": [{
        "circId": "UNICODE001",
        "title": "Tëst Bøøk with Ünicødé",
        "author": "Spëciål Çhäractërs",
        "patronName": "José María García-López"
      }]
    },
    "missing_fields": {
      "data": [{
        "circId": "MINIMAL001",
        "circStatus": "UNKNOWN_STATUS",
        "title": "Minimal Data Book"
      }]
    }
  }
}
```

## Troubleshooting

### Common Issues

#### API Won't Start
```bash
# Check if port is already in use
netstat -an | grep :3001

# Try different port
./mock_rapido_api.pl --port=3002
```

#### Configuration Errors
```bash
# Validate JSON syntax
python -m json.tool mock_config.json

# Check for syntax errors in Perl
perl -c mock_rapido_api.pl
```

#### Connection Refused
```bash
# Verify API is running
ps aux | grep mock_rapido_api

# Check logs
tail -f /tmp/mock_api.log
```

### Debugging Tips

1. **Use Status Endpoint**: Always check `/status` to see current state
2. **Check Logs**: API logs all requests and responses
3. **Validate JSON**: Ensure configuration file is valid JSON
4. **Test Incrementally**: Start with simple scenarios, add complexity
5. **Use Verbose Mode**: Add logging to see detailed request/response data

### Dependencies

Required Perl modules (available in KTD):
- `Mojolicious::Lite` - Web framework
- `Mojo::JSON` - JSON handling
- `File::Slurp` - File operations
- `DateTime` - Timestamp handling

### Performance Notes

- The mock API is designed for testing, not production use
- Configuration is loaded once at startup
- State is kept in memory (resets on restart)
- Suitable for development and CI testing environments

## Advanced Usage

### Custom Response Headers

Add custom headers to responses:

```json
{
  "responses": {
    "custom_response": {
      "data": [...],
      "headers": {
        "X-Custom-Header": "test-value",
        "X-Rate-Limit": "100"
      }
    }
  }
}
```

### Conditional Responses

Create responses based on request parameters:

```json
{
  "responses": {
    "conditional_response": {
      "conditions": {
        "startTime": "2025-08-14T00:00:00Z"
      },
      "data": [...]
    }
  }
}
```

### Response Delays

Add artificial delays to simulate network latency:

```json
{
  "responses": {
    "slow_response": {
      "delay": 2000,
      "data": [...]
    }
  }
}
```

This comprehensive mock API system provides everything needed to test Rapido ILL plugin workflows in a controlled, predictable environment.
