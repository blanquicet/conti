#!/bin/bash
# Comprehensive API Integration Test Suite
# Tests all Households API endpoints with success and failure scenarios

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

BASE_URL="http://localhost:8080"
COOKIES_FILE="/tmp/gastos-cookies.txt"
CARO_COOKIES_FILE="/tmp/gastos-cookies-caro.txt"
JOSE_EMAIL="jose@test.com"
CARO_EMAIL="caro@test.com"
PASSWORD="Test1234!"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# IDs to be populated
JOSE_ID=""
CARO_ID=""
HOUSEHOLD_ID=""
CONTACT_ID=""
LINKED_ID=""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test result tracking
declare -a FAILED_TEST_NAMES=()

# Helper functions
pass_test() {
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "${GREEN}✓ PASS${NC}\n"
}

fail_test() {
  FAILED_TESTS=$((FAILED_TESTS + 1))
  local test_name="$1"
  local reason="${2:-Unknown reason}"
  FAILED_TEST_NAMES+=("$test_name: $reason")
  echo -e "${RED}✗ FAIL: $reason${NC}\n"
}

test_header() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local test_num=$TOTAL_TESTS
  local test_name="$1"
  local test_type="${2:-SUCCESS}"
  
  if [ "$test_type" = "SUCCESS" ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}[$test_num] ${test_name}${NC}"
  else
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}[$test_num] ${test_name} (Error Case)${NC}"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local field_name="${3:-value}"
  
  if [ "$expected" = "$actual" ]; then
    return 0
  else
    echo -e "${RED}Expected $field_name: $expected, got: $actual${NC}"
    return 1
  fi
}

assert_http_status() {
  local expected="$1"
  local url="$2"
  local method="${3:--X GET}"
  local data="${4:-}"
  local cookies="${5:-}"
  
  local curl_cmd="curl -s -o /dev/null -w \"%{http_code}\" $method $url"
  [ -n "$data" ] && curl_cmd="$curl_cmd -H \"Content-Type: application/json\" -d '$data'"
  [ -n "$cookies" ] && curl_cmd="$curl_cmd -b $cookies"
  
  local actual=$(eval $curl_cmd)
  
  if [ "$expected" = "$actual" ]; then
    return 0
  else
    echo -e "${RED}Expected HTTP $expected, got: $actual${NC}"
    return 1
  fi
}

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║     🧪 Gastos Households API Integration Tests        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Clean up old cookies
rm -f $COOKIES_FILE $CARO_COOKIES_FILE

# ═══════════════════════════════════════════════════════════
# SUCCESS SCENARIOS
# ═══════════════════════════════════════════════════════════

test_header "Health Check" "SUCCESS"
if HEALTH=$(curl -s $BASE_URL/health) && echo "$HEALTH" | jq -e '.status == "healthy"' > /dev/null; then
  echo "$HEALTH" | jq .
  pass_test
else
  fail_test "Health Check" "Server not healthy or invalid response"
fi

# ───────────────────────────────────────────────────────────
# Authentication Tests
# ───────────────────────────────────────────────────────────

test_header "Register Jose" "SUCCESS"
REGISTER_RESPONSE=$(curl -s -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"name\":\"Jose\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}" \
  -c $COOKIES_FILE)
if echo "$REGISTER_RESPONSE" | jq -e '.id' > /dev/null; then
  echo "$REGISTER_RESPONSE" | jq .
  JOSE_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.id')
  pass_test
else
  fail_test "Register Jose" "Failed to register user or invalid response"
fi

test_header "Get Current User (/me)" "SUCCESS"
ME_RESPONSE=$(curl -s $BASE_URL/me -b $COOKIES_FILE)
if JOSE_ID=$(echo "$ME_RESPONSE" | jq -r '.id') && [ -n "$JOSE_ID" ] && [ "$JOSE_ID" != "null" ]; then
  echo "$ME_RESPONSE" | jq .
  pass_test
else
  fail_test "Get Current User" "Failed to get user ID or invalid response"
fi

test_header "Register Caro" "SUCCESS"
CARO_REGISTER=$(curl -s -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CARO_EMAIL\",\"name\":\"Caro\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}" \
  -c $CARO_COOKIES_FILE)
if echo "$CARO_REGISTER" | jq -e '.id' > /dev/null; then
  CARO_ID=$(echo "$CARO_REGISTER" | jq -r '.id')
  echo -e "Caro registered with ID: ${GREEN}$CARO_ID${NC}"
  pass_test
else
  fail_test "Register Caro" "Failed to register user"
fi

test_header "Logout" "SUCCESS"
LOGOUT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/auth/logout -b $COOKIES_FILE)
if [ "$LOGOUT_CODE" = "200" ]; then
  echo -e "Logged out successfully (HTTP 200)"
  pass_test
else
  fail_test "Logout" "Expected HTTP 200, got $LOGOUT_CODE"
fi

test_header "Login as Jose" "SUCCESS"
LOGIN_RESPONSE=$(curl -s -X POST $BASE_URL/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"password\":\"$PASSWORD\"}" \
  -c $COOKIES_FILE)
if echo "$LOGIN_RESPONSE" | jq -e '.id' > /dev/null; then
  echo "$LOGIN_RESPONSE" | jq .
  pass_test
else
  fail_test "Login as Jose" "Login failed or invalid response"
fi

# ───────────────────────────────────────────────────────────
# Household Management Tests
# ───────────────────────────────────────────────────────────

test_header "Create Household" "SUCCESS"
HOUSEHOLD_RESPONSE=$(curl -s -X POST $BASE_URL/households \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Casa de Jose y Caro"}')
if HOUSEHOLD_ID=$(echo "$HOUSEHOLD_RESPONSE" | jq -r '.id') && [ "$HOUSEHOLD_ID" != "null" ]; then
  echo "$HOUSEHOLD_RESPONSE" | jq .
  echo -e "Household created with ID: ${GREEN}$HOUSEHOLD_ID${NC}"
  pass_test
else
  fail_test "Create Household" "Failed to create household or invalid response"
fi

test_header "List Households" "SUCCESS"
LIST_RESPONSE=$(curl -s $BASE_URL/households -b $COOKIES_FILE)
if echo "$LIST_RESPONSE" | jq -e '.households[0].id' > /dev/null; then
  echo "$LIST_RESPONSE" | jq .
  HOUSEHOLD_COUNT=$(echo "$LIST_RESPONSE" | jq '.households | length')
  echo -e "Found ${GREEN}$HOUSEHOLD_COUNT${NC} household(s)"
  pass_test
else
  fail_test "List Households" "No households found or invalid response"
fi

test_header "Get Household Details" "SUCCESS"
DETAILS_RESPONSE=$(curl -s $BASE_URL/households/$HOUSEHOLD_ID -b $COOKIES_FILE)
if echo "$DETAILS_RESPONSE" | jq -e '.id' > /dev/null; then
  echo "$DETAILS_RESPONSE" | jq .
  pass_test
else
  fail_test "Get Household Details" "Failed to get household details"
fi

test_header "Update Household Name" "SUCCESS"
UPDATE_RESPONSE=$(curl -s -X PATCH $BASE_URL/households/$HOUSEHOLD_ID \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Mi Hogar Actualizado"}')
if NAME=$(echo "$UPDATE_RESPONSE" | jq -r '.name') && [ "$NAME" = "Mi Hogar Actualizado" ]; then
  echo "$UPDATE_RESPONSE" | jq .
  pass_test
else
  fail_test "Update Household" "Name not updated correctly"
fi

# ───────────────────────────────────────────────────────────
# Member Management Tests
# ───────────────────────────────────────────────────────────

test_header "Add Member (Caro)" "SUCCESS"
if [ -z "$CARO_ID" ]; then
  fail_test "Add Member" "Caro ID not available from previous tests"
else
  MEMBER_RESPONSE=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/members \
    -H "Content-Type: application/json" \
    -b $COOKIES_FILE \
    -d "{\"email\":\"$CARO_EMAIL\"}")
  if CARO_MEMBER_ID=$(echo "$MEMBER_RESPONSE" | jq -r '.user_id') && [ "$CARO_MEMBER_ID" = "$CARO_ID" ]; then
    echo "$MEMBER_RESPONSE" | jq .
    pass_test
  else
    fail_test "Add Member" "Failed to add Caro as member"
  fi
fi

test_header "Promote Member to Owner" "SUCCESS"
PROMOTE_RESPONSE=$(curl -s -X PATCH $BASE_URL/households/$HOUSEHOLD_ID/members/$CARO_ID/role \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"role":"owner"}')
if ROLE=$(echo "$PROMOTE_RESPONSE" | jq -r '.role') && [ "$ROLE" = "owner" ]; then
  echo "$PROMOTE_RESPONSE" | jq .
  pass_test
else
  fail_test "Promote Member" "Role not updated to owner"
fi

test_header "Demote Owner to Member" "SUCCESS"
DEMOTE_RESPONSE=$(curl -s -X PATCH $BASE_URL/households/$HOUSEHOLD_ID/members/$CARO_ID/role \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"role":"member"}')
if ROLE=$(echo "$DEMOTE_RESPONSE" | jq -r '.role') && [ "$ROLE" = "member" ]; then
  echo "$DEMOTE_RESPONSE" | jq .
  pass_test
else
  fail_test "Demote Member" "Role not updated to member"
fi

# ───────────────────────────────────────────────────────────
# Contact Management Tests
# ───────────────────────────────────────────────────────────

test_header "Create Unlinked Contact" "SUCCESS"
CONTACT_RESPONSE=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/contacts \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Papá","email":"papa@test.com","phone":"+57 300 123 4567"}')
if CONTACT_ID=$(echo "$CONTACT_RESPONSE" | jq -r '.id') && [ "$CONTACT_ID" != "null" ]; then
  echo "$CONTACT_RESPONSE" | jq .
  IS_REGISTERED=$(echo "$CONTACT_RESPONSE" | jq -r '.is_registered')
  if [ "$IS_REGISTERED" = "false" ]; then
    echo -e "Contact created as ${GREEN}unlinked${NC} (is_registered: false)"
    pass_test
  else
    fail_test "Create Unlinked Contact" "Expected is_registered=false, got $IS_REGISTERED"
  fi
else
  fail_test "Create Unlinked Contact" "Failed to create contact"
fi

test_header "Create Auto-Linked Contact" "SUCCESS"
LINKED_CONTACT=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/contacts \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d "{\"name\":\"Maria\",\"email\":\"$CARO_EMAIL\"}")
if LINKED_ID=$(echo "$LINKED_CONTACT" | jq -r '.id') && [ "$LINKED_ID" != "null" ]; then
  echo "$LINKED_CONTACT" | jq .
  IS_REGISTERED=$(echo "$LINKED_CONTACT" | jq -r '.is_registered')
  LINKED_USER=$(echo "$LINKED_CONTACT" | jq -r '.user_id')
  if [ "$IS_REGISTERED" = "true" ] && [ "$LINKED_USER" = "$CARO_ID" ]; then
    echo -e "Contact auto-linked to Caro! (user_id: ${GREEN}$LINKED_USER${NC})"
    pass_test
  else
    fail_test "Create Auto-Linked Contact" "Not auto-linked to Caro (is_registered=$IS_REGISTERED, user_id=$LINKED_USER)"
  fi
else
  fail_test "Create Auto-Linked Contact" "Failed to create contact"
fi

test_header "List Contacts" "SUCCESS"
CONTACTS_LIST=$(curl -s $BASE_URL/households/$HOUSEHOLD_ID/contacts -b $COOKIES_FILE)
if CONTACT_COUNT=$(echo "$CONTACTS_LIST" | jq 'length') && [ "$CONTACT_COUNT" -ge "2" ]; then
  echo "$CONTACTS_LIST" | jq .
  echo -e "Found ${GREEN}$CONTACT_COUNT${NC} contact(s)"
  pass_test
else
  fail_test "List Contacts" "Expected at least 2 contacts, got $CONTACT_COUNT"
fi

test_header "Update Contact" "SUCCESS"
UPDATE_CONTACT=$(curl -s -X PATCH $BASE_URL/households/$HOUSEHOLD_ID/contacts/$CONTACT_ID \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Papa Juan","email":"papa@test.com","phone":"+57 300 999 8888"}')
if NAME=$(echo "$UPDATE_CONTACT" | jq -r '.name') && [ "$NAME" = "Papa Juan" ]; then
  echo "$UPDATE_CONTACT" | jq .
  pass_test
else
  fail_test "Update Contact" "Name not updated correctly"
fi

test_header "Delete Contact" "SUCCESS"
DELETE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  $BASE_URL/households/$HOUSEHOLD_ID/contacts/$CONTACT_ID \
  -b $COOKIES_FILE)
if [ "$DELETE_CODE" = "204" ]; then
  echo -e "Contact deleted successfully (HTTP 204 No Content)"
  pass_test
else
  fail_test "Delete Contact" "Expected HTTP 204, got $DELETE_CODE"
fi

# ───────────────────────────────────────────────────────────
# Member Removal Tests
# ───────────────────────────────────────────────────────────

test_header "Remove Member from Household" "SUCCESS"
REMOVE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  $BASE_URL/households/$HOUSEHOLD_ID/members/$CARO_ID \
  -b $COOKIES_FILE)
if [ "$REMOVE_CODE" = "204" ]; then
  echo -e "Member removed successfully (HTTP 204 No Content)"
  pass_test
else
  fail_test "Remove Member" "Expected HTTP 204, got $REMOVE_CODE"
fi

# ═══════════════════════════════════════════════════════════
# FAILURE SCENARIOS (Error Cases)
# ═══════════════════════════════════════════════════════════

test_header "Unauthorized Access (No Session)" "FAILURE"
rm -f /tmp/no-cookies.txt
UNAUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  $BASE_URL/households \
  -H "Content-Type: application/json" \
  -d '{"name":"Unauthorized Test"}')
if [ "$UNAUTH_CODE" = "401" ]; then
  echo -e "Correctly rejected with HTTP 401 Unauthorized"
  pass_test
else
  fail_test "Unauthorized Access" "Expected HTTP 401, got $UNAUTH_CODE"
fi

test_header "Register with Mismatched Passwords" "FAILURE"
MISMATCH_RESPONSE=$(curl -s -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"fail@test.com","name":"Fail","password":"Test1234!","password_confirm":"Different123!"}')
ERROR=$(echo "$MISMATCH_RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Mismatched Passwords" "Should have returned error for password mismatch"
fi

test_header "Register with Duplicate Email" "FAILURE"
DUPLICATE_RESPONSE=$(curl -s -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"name\":\"Jose Duplicate\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}")
ERROR=$(echo "$DUPLICATE_RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Duplicate Email" "Should have returned error for duplicate email"
fi

test_header "Login with Invalid Password" "FAILURE"
WRONG_PW=$(curl -s -X POST $BASE_URL/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"password\":\"WrongPassword123!\"}")
ERROR=$(echo "$WRONG_PW" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Invalid Password" "Should have returned error for wrong password"
fi

test_header "Create Household with Empty Name" "FAILURE"
EMPTY_NAME=$(curl -s -X POST $BASE_URL/households \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":""}')
ERROR=$(echo "$EMPTY_NAME" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Empty Household Name" "Should have returned error for empty name"
fi

test_header "Get Non-Existent Household" "FAILURE"
NOT_FOUND=$(curl -s -o /dev/null -w "%{http_code}" \
  $BASE_URL/households/99999999 \
  -b $COOKIES_FILE)
if [ "$NOT_FOUND" = "404" ]; then
  echo -e "Correctly returned HTTP 404 Not Found"
  pass_test
else
  fail_test "Non-Existent Household" "Expected HTTP 404, got $NOT_FOUND"
fi

test_header "Add Non-Existent User as Member" "FAILURE"
BAD_MEMBER=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/members \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"email":"nonexistent@test.com"}')
ERROR=$(echo "$BAD_MEMBER" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Non-Existent Member" "Should have returned error for non-existent user"
fi

test_header "Add Duplicate Member" "FAILURE"
# Re-add Caro first
curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/members \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d "{\"email\":\"$CARO_EMAIL\"}" > /dev/null

# Try to add again
DUP_MEMBER=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/members \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d "{\"email\":\"$CARO_EMAIL\"}")
ERROR=$(echo "$DUP_MEMBER" | jq -r '.error // empty')
if [[ "$ERROR" == *"miembro"* ]] || [[ "$ERROR" == *"member"* ]]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Duplicate Member" "Should have returned error about duplicate member"
fi

test_header "Access Household as Non-Member" "FAILURE"
# Create another household with Jose
JOSE_HOUSE=$(curl -s -X POST $BASE_URL/households \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Jose Only House"}')
JOSE_HOUSE_ID=$(echo "$JOSE_HOUSE" | jq -r '.id')

# Try to access with Caro (who is not a member)
ACCESS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  $BASE_URL/households/$JOSE_HOUSE_ID \
  -b $CARO_COOKIES_FILE)
if [ "$ACCESS_CODE" = "403" ] || [ "$ACCESS_CODE" = "404" ]; then
  echo -e "Correctly denied access (HTTP $ACCESS_CODE)"
  pass_test
else
  fail_test "Non-Member Access" "Expected HTTP 403/404, got $ACCESS_CODE"
fi

test_header "Update Contact with Invalid Data" "FAILURE"
# Create a contact first
TEST_CONTACT=$(curl -s -X POST $BASE_URL/households/$HOUSEHOLD_ID/contacts \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Test Contact","email":"test@example.com"}')
TEST_CONTACT_ID=$(echo "$TEST_CONTACT" | jq -r '.id')

# Try to update with empty name
INVALID_UPDATE=$(curl -s -X PATCH $BASE_URL/households/$HOUSEHOLD_ID/contacts/$TEST_CONTACT_ID \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":""}')
ERROR=$(echo "$INVALID_UPDATE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo -e "Correctly rejected: ${GREEN}$ERROR${NC}"
  pass_test
else
  fail_test "Invalid Contact Update" "Should have returned error for empty name"
fi

test_header "Delete Non-Existent Contact" "FAILURE"
DELETE_BAD=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  $BASE_URL/households/$HOUSEHOLD_ID/contacts/99999999 \
  -b $COOKIES_FILE)
if [ "$DELETE_BAD" = "404" ]; then
  echo -e "Correctly returned HTTP 404 Not Found"
  pass_test
else
  fail_test "Delete Non-Existent Contact" "Expected HTTP 404, got $DELETE_BAD"
fi

# ═══════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}           TEST EXECUTION SUMMARY              ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}\n"

echo -e "Total Tests:  ${CYAN}$TOTAL_TESTS${NC}"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                 ✅ ALL TESTS PASSED! ✅                ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}\n"
  EXIT_CODE=0
else
  echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║                  ❌ TESTS FAILED! ❌                   ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}\n"
  
  echo -e "${RED}Failed Tests:${NC}"
  for failed in "${FAILED_TEST_NAMES[@]}"; do
    echo -e "  ${RED}✗${NC} $failed"
  done
  echo ""
  EXIT_CODE=1
fi

# Clean up
rm -f $COOKIES_FILE $CARO_COOKIES_FILE

exit $EXIT_CODE
