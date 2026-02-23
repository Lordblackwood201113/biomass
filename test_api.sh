#!/bin/bash
# test_api.sh - Integration tests for BIOMASS API
# Usage: bash test_api.sh [BASE_URL]
# Default: http://localhost:8000

BASE_URL="${1:-http://localhost:8000}"
ENDPOINT="${BASE_URL}/compute-biomass"
PASS=0
FAIL=0

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

assert_status() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  PASS: $test_name (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $test_name (expected HTTP $expected, got HTTP $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local test_name="$1"
  local json="$2"
  local field="$3"
  local expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d${field})" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    green "  PASS: $test_name ($field = $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $test_name ($field expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_not_null() {
  local test_name="$1"
  local json="$2"
  local field="$3"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d${field}; print('null' if v is None else 'ok')" 2>/dev/null)
  if [ "$actual" = "ok" ]; then
    green "  PASS: $test_name ($field is not null)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $test_name ($field is null)"
    FAIL=$((FAIL + 1))
  fi
}

echo "========================================"
echo "  BIOMASS API Integration Tests"
echo "  Endpoint: $ENDPOINT"
echo "========================================"
echo ""

# -----------------------------------------------------------
echo "TEST 1: Happy path - single tree with height"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "diameter": 46.2,
        "height": 25.5,
        "speciesName": "Symphonia globulifera"
      }
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 200" 200 "$HTTP_CODE"
assert_json_field "n_trees=1" "$BODY" "['summary']['n_trees']" "1"
assert_json_not_null "AGB_kg computed" "$BODY" "['results'][0]['AGB_kg']"
assert_json_not_null "wood_density present" "$BODY" "['results'][0]['wood_density']"
assert_json_field "genus=Symphonia" "$BODY" "['results'][0]['genus']" "Symphonia"
assert_json_field "species=globulifera" "$BODY" "['results'][0]['species']" "globulifera"
echo ""

# -----------------------------------------------------------
echo "TEST 2: Multiple trees, mixed height/no-height"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "diameter": 46.2,
        "height": 25.5,
        "speciesName": "Symphonia globulifera"
      },
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "diameter": 31.0,
        "height": null,
        "speciesName": "Dicorynia guianensis"
      },
      {
        "longitude": -53.2,
        "latitude": 3.95,
        "diameter": 22.5,
        "height": 18.0,
        "speciesName": "Eperua falcata"
      }
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 200" 200 "$HTTP_CODE"
assert_json_field "n_trees=3" "$BODY" "['summary']['n_trees']" "3"
assert_json_not_null "total_AGB_kg" "$BODY" "['summary']['total_AGB_kg']"
assert_json_not_null "tree2 AGB (no height, E-based)" "$BODY" "['results'][1]['AGB_kg']"
echo ""

# -----------------------------------------------------------
echo "TEST 3: Unknown species (fallback to genus average)"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "diameter": 30.0,
        "height": 20.0,
        "speciesName": "Symphonia xxxxxxx"
      }
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 200" 200 "$HTTP_CODE"
assert_json_not_null "AGB computed with genus fallback" "$BODY" "['results'][0]['AGB_kg']"
assert_json_field "genus=Symphonia" "$BODY" "['results'][0]['genus']" "Symphonia"
echo ""

# -----------------------------------------------------------
echo "TEST 4: Empty species name"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "diameter": 30.0,
        "height": 20.0,
        "speciesName": ""
      }
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 200 (no crash)" 200 "$HTTP_CODE"
assert_json_field "n_trees=1" "$BODY" "['summary']['n_trees']" "1"
echo ""

# -----------------------------------------------------------
echo "TEST 5: Invalid payload - missing trees field"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"data": []}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 400" 400 "$HTTP_CODE"
assert_json_field "error=true" "$BODY" "['error']" "True"
echo ""

# -----------------------------------------------------------
echo "TEST 6: Invalid payload - empty trees array"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"trees": []}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 400" 400 "$HTTP_CODE"
echo ""

# -----------------------------------------------------------
echo "TEST 7: Missing required field (no diameter)"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {
        "longitude": -52.68,
        "latitude": 4.08,
        "height": 20.0,
        "speciesName": "Symphonia globulifera"
      }
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 400" 400 "$HTTP_CODE"
echo ""

# -----------------------------------------------------------
echo "TEST 8: Large batch (10 trees, same plot)"
echo "-----------------------------------------------------------"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [
      {"longitude":-52.68,"latitude":4.08,"diameter":46.2,"height":25.5,"speciesName":"Symphonia globulifera"},
      {"longitude":-52.68,"latitude":4.08,"diameter":31.0,"height":22.0,"speciesName":"Dicorynia guianensis"},
      {"longitude":-52.68,"latitude":4.08,"diameter":22.5,"height":18.0,"speciesName":"Eperua falcata"},
      {"longitude":-52.68,"latitude":4.08,"diameter":55.0,"height":30.0,"speciesName":"Vouacapoua americana"},
      {"longitude":-52.68,"latitude":4.08,"diameter":18.3,"height":15.0,"speciesName":"Carapa surinamensis"},
      {"longitude":-52.68,"latitude":4.08,"diameter":40.1,"height":24.0,"speciesName":"Goupia glabra"},
      {"longitude":-52.68,"latitude":4.08,"diameter":28.7,"height":21.0,"speciesName":"Jacaranda copaia"},
      {"longitude":-52.68,"latitude":4.08,"diameter":35.2,"height":23.0,"speciesName":"Virola michelii"},
      {"longitude":-52.68,"latitude":4.08,"diameter":12.5,"height":10.0,"speciesName":"Inga alba"},
      {"longitude":-52.68,"latitude":4.08,"diameter":50.0,"height":28.0,"speciesName":"Qualea rosea"}
    ]
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

assert_status "HTTP 200" 200 "$HTTP_CODE"
assert_json_field "n_trees=10" "$BODY" "['summary']['n_trees']" "10"
assert_json_not_null "total_AGB_kg > 0" "$BODY" "['summary']['total_AGB_kg']"
echo ""

# -----------------------------------------------------------
echo ""
echo "========================================"
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
