#!/bin/bash
# Helper script for testing the mock API

API_URL="http://localhost:3001"

echo "=== Testing Mock Rapido API ==="
echo ""

echo "1. Checking API status..."
curl -s "$API_URL/status" | python3 -m json.tool 2>/dev/null || curl -s "$API_URL/status"

echo ""
echo ""
echo "2. Testing authentication..."
curl -s -X POST "$API_URL/view/broker/auth" \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"client_credentials","client_id":"mock_client","client_secret":"mock_secret"}'

echo ""
echo ""
echo "3. Testing circulation requests (will advance through scenario)..."
for i in {1..3}; do
  echo "   Step $i:"
  curl -s "$API_URL/view/broker/circ/circrequests?state=ACTIVE&startTime=1742713250&endTime=1755204317" | \
    python3 -c "import sys,json; data=json.load(sys.stdin); print(f\"    Status: {data.get('data',[{}])[0].get('circStatus','NO_DATA') if data.get('data') else 'EMPTY'}\")" 2>/dev/null || \
    echo "    (Raw response - install python3 for formatted output)"
done

echo ""
echo "=== Mock API Test Complete ==="
