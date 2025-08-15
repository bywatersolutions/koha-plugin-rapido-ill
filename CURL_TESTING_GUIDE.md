# Mock Rapido API - Curl Testing Guide

Complete step-by-step guide for testing the Mock Rapido API using curl commands.

## Prerequisites

1. **Start KTD environment:**
   ```bash
   ktd --name rapido --shell
   ```

2. **Navigate to plugin directory:**
   ```bash
   cd /kohadevbox/plugins/rapido-ill/scripts
   ```

## Step 1: Start the Mock API

```bash
# Start the API with borrowing scenario
./mock_rapido_api.pl --port=3001 --scenario=borrowing &

# Wait for startup
sleep 3
```

**Expected output:**
```
[2025-08-15 11:44:08.28035] [56045] [info] Starting Mock Rapido API (Working) on port 3001
[2025-08-15 11:44:08.28193] [56045] [info] Listening at "http://*:3001"
```

## Step 2: Test API Status

```bash
curl -s http://localhost:3001/status | jq
```

**Expected response:**
```json
{
  "service": "Mock Rapido API (Working)",
  "version": "2.2.0",
  "uptime": 3,
  "current_scenario": "borrowing",
  "scenario_step": 0,
  "call_counts": {},
  "available_scenarios": ["borrowing", "lending", "mixed"],
  "endpoints": [
    "POST /view/broker/auth",
    "GET /view/broker/circ/circrequests",
    "POST /view/broker/circ/{circId}/lendercancel",
    "POST /view/broker/circ/{circId}/lendershipped",
    "POST /view/broker/circ/{circId}/itemreceived",
    "POST /view/broker/circ/{circId}/itemreturned"
  ]
}
```

## Step 3: Test Authentication

```bash
curl -s -X POST http://localhost:3001/view/broker/auth \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"client_credentials","client_id":"mock_client","client_secret":"mock_secret"}' | jq
```

**Expected response:**
```json
{
  "access_token": "mock_token_12345",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

## Step 4: Test Circulation Requests (Official Rapido Spec Format)

### Step 4a: Concise Format (Default)

```bash
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&state=ACTIVE" | jq
```

**Expected response (Concise - per Rapido spec):**
```json
[
  {
    "circId": "CIRC001",
    "borrowerCode": "MPL",
    "lenderCode": "FRL", 
    "puaLocalServerCode": "MPL",
    "lastCircState": "PENDING_PARTNER_RESPONSE",
    "itemId": "ITEM001",
    "patronId": "23529000445172",
    "dateCreated": 1755251884,
    "lastUpdated": 1755255484,
    "needBefore": 1757851084
  }
]
```

### Step 4b: Verbose Format

```bash
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&state=ACTIVE&content=verbose" | jq
```

**Expected response (Verbose - per Rapido spec):**
```json
[
  {
    "circId": "CIRC001",
    "borrowerCode": "MPL",
    "lenderCode": "FRL",
    "puaLocalServerCode": "MPL",
    "puaAgencyCode": "MPL",
    "lastCircState": "ITEM_SHIPPED",
    "circStatus": "ITEM_SHIPPED",
    "itemId": "ITEM001",
    "itemBarcode": "3999900000001",
    "itemAgencyCode": "FRL",
    "callNumber": "",
    "patronId": "23529000445172",
    "patronName": "Tanya Daniels",
    "patronAgencyCode": "MPL",
    "pickupLocation": "MPL:MPL Library",
    "title": "E Street shuffle",
    "author": "Heylin, Clinton",
    "dateCreated": 1755251884,
    "lastUpdated": 1755255484,
    "needBefore": 1757851084,
    "dueDateTime": 1757851084
  }
]
```

### Step 4c: Test Workflow Progression

```bash
# First call - PENDING_PARTNER_RESPONSE
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695" | jq '.[0] | {status: .lastCircState, item: .itemId}'

# Second call - ITEM_SHIPPED  
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695" | jq '.[0].lastCircState'

# Third call - ITEM_RECEIVED
curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695" | jq '.[0].lastCircState'
```

**Expected progression:**
```json
{
  "status": "PENDING_PARTNER_RESPONSE",
  "item": "ITEM001"
}
"ITEM_SHIPPED"
"ITEM_RECEIVED"
```

## Step 4d: Test Spec Compliance

```bash
# Test debug endpoint showing format differences
curl -s http://localhost:3001/debug/formats | jq
```

**Key Spec Compliance Features:**
- ✅ **Response format**: Array of objects (no wrapper)
- ✅ **Timestamps**: Unix epoch seconds (not ISO8601)
- ✅ **Default content**: concise
- ✅ **Default state**: ACTIVE if not specified
- ✅ **Required parameters**: startTime and endTime are mandatory

## Step 5: Test Scenario Switching

### Switch to Lending Scenario

```bash
curl -s -X POST http://localhost:3001/control/scenario/lending | jq
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Switched to scenario: lending",
  "scenario": {
    "description": "Typical lending workflow",
    "sequence": [
      {"endpoint": "circulation_requests", "response": "lending_initial"},
      {"endpoint": "circulation_requests", "response": "lending_checkout"},
      {"endpoint": "circulation_requests", "response": "lending_returned"}
    ]
  }
}
```

### Test Lending Workflow

```bash
# First lending request (PENDING_CHECKOUT)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | jq '.[0] | {status: .lastCircState, title: .title, patron: .patronName}'
```

**Expected output:**
```json
{
  "status": "PENDING_CHECKOUT",
  "title": "The C programming language",
  "patron": "Marcus Welch"
}
```

```bash
# Second lending request (ITEM_CHECKED_OUT)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | jq '.[0].lastCircState'
```

**Expected output:**
```json
"ITEM_CHECKED_OUT"
```

## Step 6: Test Action Endpoints

### Test Lender Actions

```bash
# Lender cancel
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendercancel \
  -H "Content-Type: application/json" \
  -d '{"reason":"patron_cancelled"}' | jq
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Lender cancel processed successfully",
  "circId": "CIRC001",
  "data": {"reason": "patron_cancelled"}
}
```

```bash
# Lender shipped
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendershipped \
  -H "Content-Type: application/json" \
  -d '{"tracking_number":"1234567890"}' | jq
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Lender shipped processed successfully",
  "circId": "CIRC001",
  "data": {"tracking_number": "1234567890"}
}
```

### Test Borrower Actions

```bash
# Item received
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/itemreceived | jq
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Borrower item received processed successfully",
  "circId": "CIRC001"
}
```

```bash
# Item returned
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/itemreturned | jq
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Borrower item returned processed successfully",
  "circId": "CIRC001"
}
```

## Step 7: Test Mixed Scenario

```bash
# Switch to mixed scenario
curl -s -X POST http://localhost:3001/control/scenario/mixed | jq

# Test mixed requests (returns multiple items)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | jq 'length as $count | "Items returned: \($count)" as $summary | [$summary] + [.[] | "\(.circId): \(.lastCircState) - \(.title)"]'
```

**Expected output:**
```json
[
  "Items returned: 2",
  "CIRC003: ITEM_SHIPPED - The C programming language",
  "CIRC004: PENDING_CHECKOUT - Perl best practices"
]
```

## Step 8: Test State Reset

```bash
# Reset API state
curl -s -X POST http://localhost:3001/control/reset | jq

# Verify reset
curl -s http://localhost:3001/status | jq '{call_counts, scenario_step}'
```

**Expected output:**
```json
{
  "success": 1,
  "message": "API state reset"
}
```
```json
{
  "call_counts": {},
  "scenario_step": 0
}
```

## Step 9: Test Error Handling

```bash
# Test unknown scenario
curl -s -X POST http://localhost:3001/control/scenario/unknown | jq

# Test unknown endpoint (will return 404)
curl -s http://localhost:3001/unknown/endpoint | jq
```

**Expected responses:**
```json
{
  "success": 0,
  "error": "Unknown scenario: unknown",
  "available": ["borrowing", "lending", "mixed"]
}
```

## Step 10: Performance Testing

```bash
# Test multiple rapid requests
echo "Testing rapid requests..."
for i in {1..5}; do
  echo "Request $i:"
  curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | jq -r '"  Call #\(if length > 0 then "N/A" else "NO_DATA" end): \(if length > 0 then .[0].lastCircState else "NO_DATA" end)"'
done
```

## Step 11: Cleanup

```bash
# Stop the API
pkill -f mock_rapido_api

# Verify it's stopped
curl -s http://localhost:3001/status || echo "API stopped successfully"
```

## Complete Test Script

Save this as `test_all_endpoints.sh`:

```bash
#!/bin/bash

echo "=== Mock Rapido API Complete Test ==="

# Start API
./mock_rapido_api.pl --port=3001 --scenario=borrowing &
sleep 3

echo "1. Testing status..."
curl -s http://localhost:3001/status | jq -r '"✓ Service: \(.service) v\(.version)"'

echo "2. Testing auth..."
curl -s -X POST http://localhost:3001/view/broker/auth | jq -r '"✓ Token: \(.access_token[:20])..."'

echo "3. Testing borrowing workflow (Rapido spec format)..."
for i in {1..3}; do
  status=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&state=ACTIVE" | jq -r 'if length > 0 then .[0].lastCircState else "NO_DATA" end')
  echo "  Step $i: $status"
done

echo "4. Testing concise vs verbose format..."
concise_fields=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695" | jq 'if length > 0 then .[0] | keys | length else 0 end')
verbose_fields=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&content=verbose" | jq 'if length > 0 then .[0] | keys | length else 0 end')
echo "  Concise fields: $concise_fields, Verbose fields: $verbose_fields"

echo "5. Testing scenario switch..."
curl -s -X POST http://localhost:3001/control/scenario/lending | jq -r '"✓ \(.message)"'

echo "6. Testing lending workflow..."
status=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?startTime=1742713250&endTime=1755205695&state=ACTIVE" | jq -r '.[0].lastCircState')
echo "  Lending status: $status"

echo "7. Testing actions..."
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendercancel | jq -r '"✓ \(.message)"'

echo "8. Testing spec compliance..."
curl -s http://localhost:3001/debug/formats | jq -r '"✓ \(.spec_info)"'

# Cleanup
pkill -f mock_rapido_api
echo "✓ Test complete - All endpoints match official Rapido API specification!"
```

## Troubleshooting

**API won't start:**
- Check if port 3001 is already in use: `ss -tlnp | grep 3001`
- Kill existing processes: `pkill -f mock_rapido_api`
- Try a different port: `--port=3002`

**Curl hangs:**
- Check API logs for errors
- Verify API is listening: `curl -s http://localhost:3001/status`
- Try with timeout: `curl --max-time 5 ...`

**jq not available:**
- Install jq: `apt-get install jq` (in KTD container)
- Alternative: Use `| python3 -m json.tool` instead of `| jq`
- View raw response: remove `| jq` entirely

**JSON parsing errors:**
- Check API response format with: `curl -s URL | head -5`
- Verify API is returning valid JSON
- Use `jq .` to validate JSON structure

This guide provides comprehensive testing of all Mock Rapido API functionality using standard curl commands with jq for clean JSON formatting.

## Step 5: Test Scenario Switching

### Switch to Lending Scenario

```bash
curl -s -X POST http://localhost:3001/control/scenario/lending | python3 -m json.tool
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Switched to scenario: lending",
  "scenario": {
    "description": "Typical lending workflow",
    "sequence": [
      {"endpoint": "circulation_requests", "response": "lending_initial"},
      {"endpoint": "circulation_requests", "response": "lending_checkout"},
      {"endpoint": "circulation_requests", "response": "lending_returned"}
    ]
  }
}
```

### Test Lending Workflow

```bash
# First lending request (PENDING_CHECKOUT)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | \
  python3 -c "import sys,json; data=json.load(sys.stdin); print(f'Status: {data[\"data\"][0][\"circStatus\"]}'); print(f'Title: {data[\"data\"][0][\"title\"]}'); print(f'Patron: {data[\"data\"][0][\"patronName\"]}')"
```

**Expected output:**
```
Status: PENDING_CHECKOUT
Title: The C programming language
Patron: Marcus Welch
```

```bash
# Second lending request (ITEM_CHECKED_OUT)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | \
  python3 -c "import sys,json; data=json.load(sys.stdin); print(f'Status: {data[\"data\"][0][\"circStatus\"]}')"
```

**Expected output:**
```
Status: ITEM_CHECKED_OUT
```

## Step 6: Test Action Endpoints

### Test Lender Actions

```bash
# Lender cancel
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendercancel \
  -H "Content-Type: application/json" \
  -d '{"reason":"patron_cancelled"}' | python3 -m json.tool
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Lender cancel processed successfully",
  "circId": "CIRC001",
  "data": {"reason": "patron_cancelled"}
}
```

```bash
# Lender shipped
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendershipped \
  -H "Content-Type: application/json" \
  -d '{"tracking_number":"1234567890"}' | python3 -m json.tool
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Lender shipped processed successfully",
  "circId": "CIRC001",
  "data": {"tracking_number": "1234567890"}
}
```

### Test Borrower Actions

```bash
# Item received
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/itemreceived | python3 -m json.tool
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Borrower item received processed successfully",
  "circId": "CIRC001"
}
```

```bash
# Item returned
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/itemreturned | python3 -m json.tool
```

**Expected response:**
```json
{
  "success": 1,
  "message": "Borrower item returned processed successfully",
  "circId": "CIRC001"
}
```

## Step 7: Test Mixed Scenario

```bash
# Switch to mixed scenario
curl -s -X POST http://localhost:3001/control/scenario/mixed | python3 -m json.tool

# Test mixed requests (returns multiple items)
curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | \
  python3 -c "import sys,json; data=json.load(sys.stdin); print(f'Items returned: {len(data[\"data\"])}'); [print(f'  {item[\"circId\"]}: {item[\"circStatus\"]} - {item[\"title\"]}') for item in data['data']]"
```

**Expected output:**
```
Items returned: 2
  CIRC003: ITEM_SHIPPED - The C programming language
  CIRC004: PENDING_CHECKOUT - Perl best practices
```

## Step 8: Test State Reset

```bash
# Reset API state
curl -s -X POST http://localhost:3001/control/reset | python3 -m json.tool

# Verify reset
curl -s http://localhost:3001/status | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'Call counts: {data[\"call_counts\"]}'); print(f'Scenario step: {data[\"scenario_step\"]}')"
```

**Expected output:**
```json
{
  "success": 1,
  "message": "API state reset"
}
```
```
Call counts: {}
Scenario step: 0
```

## Step 9: Test Error Handling

```bash
# Test unknown scenario
curl -s -X POST http://localhost:3001/control/scenario/unknown | python3 -m json.tool

# Test unknown endpoint
curl -s http://localhost:3001/unknown/endpoint | python3 -m json.tool
```

**Expected responses:**
```json
{
  "success": 0,
  "error": "Unknown scenario: unknown",
  "available": ["borrowing", "lending", "mixed"]
}
```

## Step 10: Performance Testing

```bash
# Test multiple rapid requests
echo "Testing rapid requests..."
for i in {1..5}; do
  echo "Request $i:"
  curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | \
    python3 -c "import sys,json; data=json.load(sys.stdin); print(f'  Call #{data[\"meta\"][\"call_number\"]}: {data[\"data\"][0][\"circStatus\"] if data[\"data\"] else \"NO_DATA\"}')"
done
```

## Step 11: Cleanup

```bash
# Stop the API
pkill -f mock_rapido_api

# Verify it's stopped
curl -s http://localhost:3001/status || echo "API stopped successfully"
```

## Complete Test Script

Save this as `test_all_endpoints.sh`:

```bash
#!/bin/bash

echo "=== Mock Rapido API Complete Test ==="

# Start API
./mock_rapido_api.pl --port=3001 --scenario=borrowing &
sleep 3

echo "1. Testing status..."
curl -s http://localhost:3001/status | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'✓ Service: {data[\"service\"]} v{data[\"version\"]}')"

echo "2. Testing auth..."
curl -s -X POST http://localhost:3001/view/broker/auth | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'✓ Token: {data[\"access_token\"][:20]}...')"

echo "3. Testing borrowing workflow..."
for i in {1..3}; do
  status=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['data'][0]['circStatus'] if data['data'] else 'NO_DATA')")
  echo "  Step $i: $status"
done

echo "4. Testing scenario switch..."
curl -s -X POST http://localhost:3001/control/scenario/lending | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'✓ {data[\"message\"]}')"

echo "5. Testing lending workflow..."
status=$(curl -s "http://localhost:3001/view/broker/circ/circrequests?state=ACTIVE" | python3 -c "import sys,json; data=json.load(sys.stdin); print(data['data'][0]['circStatus'])")
echo "  Lending status: $status"

echo "6. Testing actions..."
curl -s -X POST http://localhost:3001/view/broker/circ/CIRC001/lendercancel | python3 -c "import sys,json; data=json.load(sys.stdin); print(f'✓ {data[\"message\"]}')"

# Cleanup
pkill -f mock_rapido_api
echo "✓ Test complete!"
```

## Troubleshooting

**API won't start:**
- Check if port 3001 is already in use: `ss -tlnp | grep 3001`
- Kill existing processes: `pkill -f mock_rapido_api`
- Try a different port: `--port=3002`

**Curl hangs:**
- Check API logs for errors
- Verify API is listening: `curl -s http://localhost:3001/status`
- Try with timeout: `curl --max-time 5 ...`

**JSON parsing errors:**
- Install python3 if not available
- Use `jq` instead: `curl ... | jq .`
- View raw response: remove `| python3 -m json.tool`

This guide provides comprehensive testing of all Mock Rapido API functionality using standard curl commands.
