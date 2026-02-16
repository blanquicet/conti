#!/bin/bash
# Contact Linking & Unlinking Integration Tests
# Tests explicit linking flow and bilateral unlink

set -e
set -o pipefail

BASE_URL="${API_BASE_URL:-http://localhost:8080}"
DATABASE_URL="${DATABASE_URL:-postgres://conti:conti_dev_password@localhost:5432/conti?sslmode=disable}"
COOKIES_A="/tmp/gastos-link-a-cookies.txt"
COOKIES_B="/tmp/gastos-link-b-cookies.txt"
TIMESTAMP=$(date +%s%N)
USER_A_EMAIL="alice+link${TIMESTAMP}@test.com"
USER_B_EMAIL="bob+link${TIMESTAMP}@test.com"
PASSWORD="Test1234!"

CURL_FLAGS="-s"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0

echo -e "${YELLOW}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   🧪 Contact Linking & Unlinking Integration Tests    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

rm -f $COOKIES_A $COOKIES_B

error_handler() {
  local line=$1
  echo -e "\n${RED}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ✗ TEST FAILED at line $line${NC}"
  echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
  if [ -n "$LAST_RESPONSE" ]; then
    echo -e "${YELLOW}Last API Response:${NC}"
    echo "$LAST_RESPONSE" | jq '.' 2>/dev/null || echo "$LAST_RESPONSE"
  fi
  exit 1
}
trap 'error_handler $LINENO' ERR

api_call() {
  LAST_RESPONSE=$(curl "$@")
  echo "$LAST_RESPONSE"
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${CYAN}▶ $1${NC}"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓ $1${NC}\n"
}

db_query() {
  if [ -n "$CI" ] || PAGER=cat psql "$DATABASE_URL" -c "SELECT 1" > /dev/null 2>&1; then
    PAGER=cat psql "$DATABASE_URL" -t -c "$1" 2>/dev/null | xargs
  else
    docker compose exec -T postgres psql -U conti -d conti -t -c "$1" 2>/dev/null | xargs
  fi
}

# ═══════════════════════════════════════════════════════════
# SETUP: Two users, two households
# ═══════════════════════════════════════════════════════════

echo -e "${YELLOW}▸ Setting up two users and households...${NC}\n"

api_call $CURL_FLAGS -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER_A_EMAIL\",\"name\":\"Alice Test\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}" \
  -c $COOKIES_A > /dev/null

A_ME=$(api_call $CURL_FLAGS $BASE_URL/me -b $COOKIES_A)
A_ID=$(echo "$A_ME" | jq -r '.id')

A_HOUSEHOLD=$(api_call $CURL_FLAGS -X POST $BASE_URL/households \
  -b $COOKIES_A -H "Content-Type: application/json" \
  -d '{"name":"Alice Household"}')
A_HOUSEHOLD_ID=$(echo "$A_HOUSEHOLD" | jq -r '.id')

api_call $CURL_FLAGS -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$USER_B_EMAIL\",\"name\":\"Bob Test\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}" \
  -c $COOKIES_B > /dev/null

B_ME=$(api_call $CURL_FLAGS $BASE_URL/me -b $COOKIES_B)
B_ID=$(echo "$B_ME" | jq -r '.id')

B_HOUSEHOLD=$(api_call $CURL_FLAGS -X POST $BASE_URL/households \
  -b $COOKIES_B -H "Content-Type: application/json" \
  -d '{"name":"Bob Household"}')
B_HOUSEHOLD_ID=$(echo "$B_HOUSEHOLD" | jq -r '.id')

echo -e "${GREEN}✓ Setup complete: Alice ($A_ID) and Bob ($B_ID)${NC}\n"

# ═══════════════════════════════════════════════════════════
# TEST 1: Creating contact does NOT auto-link
# ═══════════════════════════════════════════════════════════

run_test "T1: Create contact with registered email — should NOT auto-link"
CONTACT_A=$(api_call $CURL_FLAGS -X POST $BASE_URL/households/$A_HOUSEHOLD_ID/contacts \
  -b $COOKIES_A -H "Content-Type: application/json" \
  -d "{\"name\":\"Bob Contact\",\"email\":\"$USER_B_EMAIL\"}")
CONTACT_A_ID=$(echo "$CONTACT_A" | jq -r '.id')
LINK_STATUS=$(echo "$CONTACT_A" | jq -r '.link_status')
LINKED_USER=$(echo "$CONTACT_A" | jq -r '.linked_user_id')
[ "$LINK_STATUS" = "NONE" ] || [ "$LINK_STATUS" = "null" ]
[ "$LINKED_USER" = "null" ] || [ "$LINKED_USER" = "" ]
pass "Contact created with link_status=NONE, no auto-link"

# ═══════════════════════════════════════════════════════════
# TEST 2: Check email endpoint
# ═══════════════════════════════════════════════════════════

run_test "T2: Check email — registered user"
CHECK=$(api_call $CURL_FLAGS -G "$BASE_URL/contacts/check-email" --data-urlencode "email=$USER_B_EMAIL" -b $COOKIES_A)
IS_REG=$(echo "$CHECK" | jq -r '.is_registered')
DISPLAY=$(echo "$CHECK" | jq -r '.display_name')
[ "$IS_REG" = "true" ]
[ "$DISPLAY" = "Bob Test" ]
pass "check-email returns is_registered=true, display_name=Bob Test"

run_test "T3: Check email — unregistered user"
CHECK2=$(api_call $CURL_FLAGS -G "$BASE_URL/contacts/check-email" --data-urlencode "email=nobody${TIMESTAMP}@test.com" -b $COOKIES_A)
IS_REG2=$(echo "$CHECK2" | jq -r '.is_registered')
[ "$IS_REG2" = "false" ]
pass "check-email returns is_registered=false for unknown email"

# ═══════════════════════════════════════════════════════════
# TEST 3: Request link
# ═══════════════════════════════════════════════════════════

run_test "T4: Request link — sets PENDING"
LINK_RESP=$(api_call $CURL_FLAGS -X POST "$BASE_URL/contacts/$CONTACT_A_ID/request-link" -b $COOKIES_A)
LINK_STATUS2=$(echo "$LINK_RESP" | jq -r '.status')
[ "$LINK_STATUS2" = "pending" ]

# Verify in DB
DB_STATUS=$(db_query "SELECT link_status FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_STATUS" = "PENDING" ]
DB_LINKED=$(db_query "SELECT linked_user_id FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_LINKED" = "$B_ID" ]
pass "Contact is PENDING with linked_user_id set"

# ═══════════════════════════════════════════════════════════
# TEST 4: Bob sees pending link request
# ═══════════════════════════════════════════════════════════

run_test "T5: Bob sees pending link request"
REQUESTS=$(api_call $CURL_FLAGS $BASE_URL/link-requests -b $COOKIES_B)
REQ_COUNT=$(echo "$REQUESTS" | jq 'length')
[ "$REQ_COUNT" -ge 1 ]
pass "Bob has pending link request"

# ═══════════════════════════════════════════════════════════
# TEST 5: Bob accepts link request
# ═══════════════════════════════════════════════════════════

run_test "T6: Bob accepts link request"
ACCEPT=$(api_call $CURL_FLAGS -X POST "$BASE_URL/link-requests/$CONTACT_A_ID/accept" \
  -b $COOKIES_B -H "Content-Type: application/json" \
  -d '{"contact_name":"Alice Contact"}')

# Verify Alice's contact is ACCEPTED
DB_STATUS2=$(db_query "SELECT link_status FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_STATUS2" = "ACCEPTED" ]

# Verify reciprocal contact was created in Bob's household
RECIPROCAL_ID=$(db_query "SELECT id FROM contacts WHERE household_id = '$B_HOUSEHOLD_ID' AND linked_user_id = '$A_ID' AND link_status = 'ACCEPTED'")
[ -n "$RECIPROCAL_ID" ]
pass "Both contacts ACCEPTED (Alice→Bob and Bob→Alice)"

# ═══════════════════════════════════════════════════════════
# TEST 6: Request link on already linked contact fails
# ═══════════════════════════════════════════════════════════

run_test "T7: Request link on already linked contact — should fail"
HTTP_CODE=$(curl $CURL_FLAGS -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/contacts/$CONTACT_A_ID/request-link" -b $COOKIES_A)
[ "$HTTP_CODE" = "409" ]
pass "Returns 409 Conflict for already-linked contact"

# ═══════════════════════════════════════════════════════════
# TEST 7: Unlink — bilateral
# ═══════════════════════════════════════════════════════════

run_test "T8: Alice unlinks contact — both sides unlinked"
UNLINK=$(api_call $CURL_FLAGS -X POST "$BASE_URL/contacts/$CONTACT_A_ID/unlink" -b $COOKIES_A)
UNLINK_STATUS=$(echo "$UNLINK" | jq -r '.status')
[ "$UNLINK_STATUS" = "unlinked" ]

# Verify Alice's contact is NONE with no linked_user_id
DB_STATUS3=$(db_query "SELECT link_status FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_STATUS3" = "NONE" ]
DB_LINKED3=$(db_query "SELECT COALESCE(linked_user_id::text, 'NULL') FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_LINKED3" = "NULL" ]

# Verify reciprocal (Bob's contact) is also NONE
DB_RECIP_STATUS=$(db_query "SELECT link_status FROM contacts WHERE id = '$RECIPROCAL_ID'")
[ "$DB_RECIP_STATUS" = "NONE" ]
DB_RECIP_LINKED=$(db_query "SELECT COALESCE(linked_user_id::text, 'NULL') FROM contacts WHERE id = '$RECIPROCAL_ID'")
[ "$DB_RECIP_LINKED" = "NULL" ]

# Verify was_unlinked_at is set on reciprocal (notification for Bob)
DB_UNLINKED_AT=$(db_query "SELECT CASE WHEN was_unlinked_at IS NOT NULL THEN 'SET' ELSE 'NULL' END FROM contacts WHERE id = '$RECIPROCAL_ID'")
[ "$DB_UNLINKED_AT" = "SET" ]
pass "Both contacts unlinked, was_unlinked_at set on reciprocal"

# ═══════════════════════════════════════════════════════════
# TEST 8: Dismiss unlink banner
# ═══════════════════════════════════════════════════════════

run_test "T9: Bob dismisses unlink banner"
DISMISS=$(api_call $CURL_FLAGS -X POST "$BASE_URL/contacts/$RECIPROCAL_ID/dismiss-unlink" -b $COOKIES_B)
DISMISS_STATUS=$(echo "$DISMISS" | jq -r '.status')
[ "$DISMISS_STATUS" = "dismissed" ]

DB_UNLINKED_AT2=$(db_query "SELECT CASE WHEN was_unlinked_at IS NOT NULL THEN 'SET' ELSE 'NULL' END FROM contacts WHERE id = '$RECIPROCAL_ID'")
[ "$DB_UNLINKED_AT2" = "NULL" ]
pass "was_unlinked_at cleared after dismiss"

# ═══════════════════════════════════════════════════════════
# TEST 9: Re-link after unlink
# ═══════════════════════════════════════════════════════════

run_test "T10: Alice re-links contact (Vincular after unlink)"
RELINK=$(api_call $CURL_FLAGS -X POST "$BASE_URL/contacts/$CONTACT_A_ID/request-link" -b $COOKIES_A)
RELINK_STATUS=$(echo "$RELINK" | jq -r '.status')
[ "$RELINK_STATUS" = "pending" ]

DB_STATUS4=$(db_query "SELECT link_status FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_STATUS4" = "PENDING" ]
pass "Contact re-linked with PENDING status"

# ═══════════════════════════════════════════════════════════
# TEST 10: Unlink PENDING (cancel request)
# ═══════════════════════════════════════════════════════════

run_test "T11: Alice unlinks PENDING contact (cancel request)"
UNLINK2=$(api_call $CURL_FLAGS -X POST "$BASE_URL/contacts/$CONTACT_A_ID/unlink" -b $COOKIES_A)
[ "$(echo "$UNLINK2" | jq -r '.status')" = "unlinked" ]

DB_STATUS5=$(db_query "SELECT link_status FROM contacts WHERE id = '$CONTACT_A_ID'")
[ "$DB_STATUS5" = "NONE" ]
pass "PENDING contact unlinked (request cancelled)"

# ═══════════════════════════════════════════════════════════
# TEST 11: Create contact with request_link=true
# ═══════════════════════════════════════════════════════════

run_test "T12: Create contact with request_link=true — sets PENDING immediately"
CONTACT_A2=$(api_call $CURL_FLAGS -X POST $BASE_URL/households/$A_HOUSEHOLD_ID/contacts \
  -b $COOKIES_A -H "Content-Type: application/json" \
  -d "{\"name\":\"Bob Again\",\"email\":\"$USER_B_EMAIL\",\"request_link\":true}")
CONTACT_A2_ID=$(echo "$CONTACT_A2" | jq -r '.id')
LINK_STATUS_A2=$(echo "$CONTACT_A2" | jq -r '.link_status')
[ "$LINK_STATUS_A2" = "PENDING" ]
pass "New contact created with PENDING link status"

# ═══════════════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════════════

rm -f $COOKIES_A $COOKIES_B

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ✓ ALL $TESTS_PASSED/$TESTS_RUN TESTS PASSED                              ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"
