# Mock Rapido API Service

A configurable mock API service for testing the Rapido ILL plugin without connecting to real Rapido infrastructure.

## Features

- **Configurable Scenarios**: Predefined workflow sequences (borrowing, lending, mixed)
- **State Tracking**: Simulates workflow progression through multiple API calls
- **Realistic Data**: Returns properly formatted Rapido API responses
- **Control Endpoints**: Switch scenarios and reset state during testing
- **Logging**: Detailed logging of all API interactions

## Quick Start

```bash
# Start the mock API (default port 3000)
./mock_rapido_api.pl

# Start with a specific scenario
./mock_rapido_api.pl --scenario=borrowing --port=8080

# Test the API
./test_mock_api.pl
```

## Configuration

The service uses a JSON configuration file (`mock_config.json`) that defines:

### Scenarios
Sequences of API responses that simulate different workflows:

```json
{
  "scenarios": {
    "borrowing": {
      "description": "Typical borrowing workflow",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "borrowing_initial"},
        {"endpoint": "circulation_requests", "response": "borrowing_shipped"},
        {"endpoint": "circulation_requests", "response": "borrowing_received"}
      ]
    }
  }
}
```

### Responses
The actual data returned for each step:

```json
{
  "responses": {
    "borrowing_initial": {
      "data": [
        {
          "circId": "CIRC001",
          "circStatus": "PENDING_PARTNER_RESPONSE",
          "title": "Test Book for Borrowing",
          "patronName": "John Doe"
        }
      ]
    }
  }
}
```

## API Endpoints

### Core Rapido Endpoints

- `POST /auth/token` - Authentication (returns mock token)
- `GET /locals` - Library information
- `GET /circulation_requests` - Main data sync endpoint
- `POST /lender/:action` - Lender actions (checkout, checkin, etc.)
- `POST /borrower/:action` - Borrower actions (received, returned, etc.)

### Control Endpoints

- `GET /status` - API status and current scenario
- `POST /control/scenario/:name` - Switch to different scenario
- `POST /control/reset` - Reset API state

## Predefined Scenarios

### Borrowing Workflow
Simulates a typical borrowing request lifecycle:
1. **Initial**: Request pending partner response
2. **Shipped**: Item shipped by lender
3. **Received**: Item received and available for patron

### Lending Workflow  
Simulates a typical lending request lifecycle:
1. **Initial**: Request pending checkout
2. **Checkout**: Item checked out to requesting patron
3. **Returned**: Item returned and available

### Mixed Workflow
Returns multiple requests in different states simultaneously.

## Usage with Rapido Plugin

Update your plugin configuration to point to the mock API:

```yaml
mock-pod:
  base_url: http://localhost:3000
  client_id: mock_client
  client_secret: mock_secret
  server_code: 11747
  # ... other settings
```

Then run sync_requests.pl against the mock pod:

```bash
perl sync_requests.pl --pod mock-pod
```

## Testing Workflow Progression

The mock API tracks state across calls, so you can test complete workflows:

```bash
# Start with borrowing scenario
curl -X POST http://localhost:3000/control/scenario/borrowing

# First sync - gets "PENDING_PARTNER_RESPONSE" 
curl http://localhost:3000/circulation_requests

# Second sync - gets "ITEM_SHIPPED"
curl http://localhost:3000/circulation_requests  

# Third sync - gets "ITEM_RECEIVED"
curl http://localhost:3000/circulation_requests

# Reset for next test
curl -X POST http://localhost:3000/control/reset
```

## Custom Scenarios

Create custom scenarios by editing `mock_config.json`:

```json
{
  "scenarios": {
    "my_test": {
      "description": "Custom test scenario",
      "sequence": [
        {"endpoint": "circulation_requests", "response": "my_response"}
      ]
    }
  },
  "responses": {
    "my_response": {
      "data": [
        {
          "circId": "CUSTOM001",
          "circStatus": "CUSTOM_STATUS",
          "title": "My Test Book"
        }
      ]
    }
  }
}
```

## Development Tips

1. **Monitor Logs**: The service logs all API calls and state changes
2. **Use Status Endpoint**: Check current scenario and call counts
3. **Reset Between Tests**: Use `/control/reset` to start fresh
4. **Test Edge Cases**: Create scenarios with empty responses, errors, etc.
5. **Timing Tests**: Add delays or specific timestamps to test sync logic

## Dependencies

- Mojolicious::Lite (for web server)
- Mojo::JSON (for JSON handling)  
- File::Slurp (for config file handling)
- DateTime (for timestamps)

Install with: `cpanm Mojolicious File::Slurp DateTime`

## Examples

See `test_mock_api.pl` for comprehensive usage examples and testing patterns.
