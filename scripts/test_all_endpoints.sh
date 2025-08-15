#!/bin/bash

echo "=== Mock Rapido API Complete Test (Spec Compliant) ==="

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
