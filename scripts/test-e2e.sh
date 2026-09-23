#!/bin/bash
set -e

# Configuration
SERVER_IP=$1

if [ -z "$SERVER_IP" ]; then
    echo "Usage: $0 <server_ip>"
    exit 1
fi

BASE_URL="http://$SERVER_IP"
FAILED_TESTS=0

echo "=========================================="
echo "Starting End-to-End Tests"
echo "Target: $BASE_URL"
echo "=========================================="
echo ""

# Test function
run_test() {
    local test_name=$1
    local endpoint=$2
    local expected_code=${3:-200}
    
    echo -n "Testing $test_name... "
    
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$status_code" -eq "$expected_code" ]; then
        echo "✓ PASSED (Status: $status_code)"
        if [ -n "$body" ]; then
            echo "  Response: $body" | head -c 100
            echo ""
        fi
        return 0
    else
        echo "✗ FAILED (Expected: $expected_code, Got: $status_code)"
        echo "  Response: $body"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Run tests
echo "1. Testing Home Endpoint"
run_test "Home" "/" 200

echo ""
echo "2. Testing Health Check Endpoint"
run_test "Health Check" "/health" 200

echo ""
echo "3. Testing Info Endpoint"
run_test "Info" "/api/info" 200

echo ""
echo "4. Testing Data GET Endpoint"
run_test "Data GET" "/api/data" 200

echo ""
echo "5. Testing Data POST Endpoint"
response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"test": "data", "timestamp": "2024-01-01"}' \
    "$BASE_URL/api/data")
status_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

echo -n "Testing Data POST... "
if [ "$status_code" -eq "201" ]; then
    echo "✓ PASSED (Status: $status_code)"
    echo "  Response: $body" | head -c 100
    echo ""
else
    echo "✗ FAILED (Expected: 201, Got: $status_code)"
    echo "  Response: $body"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""
echo "6. Testing Invalid Endpoint (404)"
run_test "404 Test" "/invalid-endpoint" 404

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
if [ $FAILED_TESTS -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ $FAILED_TESTS test(s) failed"
    exit 1
fi
