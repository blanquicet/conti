#!/bin/bash
# Income API Integration Tests
# Tests CRUD operations and audit logging for income entries

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

BASE_URL="${API_BASE_URL:-http://localhost:8080}"
DATABASE_URL="${DATABASE_URL:-postgresql://conti:conti_dev_password@localhost:5432/conti?sslmode=disable}"
COOKIES_FILE="/tmp/gastos-income-test-cookies.txt"
JOSE_EMAIL="jose+income$(date +%s%N)@test.com"
PASSWORD="Test1234!"
DEBUG="${DEBUG:-false}"

# Curl flags based on debug mode
CURL_FLAGS="-s"
if [ "$DEBUG" = "true" ]; then
  CURL_FLAGS="-v"
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║     🧪 Gastos Income API Integration Tests            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Clean up
rm -f $COOKIES_FILE

# Error handler
error_handler() {
  local line=$1
  echo -e "\n${RED}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ✗ TEST FAILED at line $line${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
  if [ -n "$LAST_RESPONSE" ]; then
    echo -e "${YELLOW}Last API Response:${NC}"
    echo "$LAST_RESPONSE" | jq '.' 2>/dev/null || echo "$LAST_RESPONSE"
  fi
  exit 1
}

trap 'error_handler $LINENO' ERR

# Wrapper for curl that captures response
api_call() {
  LAST_RESPONSE=$(curl "$@")
  echo "$LAST_RESPONSE"
}

# Helper function
run_test() {
  echo -e "${CYAN}▶ $1${NC}"
}

# ═══════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════

run_test "Health Check"
HEALTH=$(api_call $CURL_FLAGS $BASE_URL/health)
echo "$HEALTH" | jq -e '.status == "healthy"' > /dev/null
echo -e "${GREEN}✓ Server is healthy${NC}\n"

run_test "Register Jose"
REGISTER_RESPONSE=$(api_call $CURL_FLAGS -X POST $BASE_URL/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"name\":\"Jose\",\"password\":\"$PASSWORD\",\"password_confirm\":\"$PASSWORD\"}" \
  -c $COOKIES_FILE)
echo "$REGISTER_RESPONSE" | jq -e '.message' > /dev/null
echo -e "${GREEN}✓ Jose registered${NC}\n"

run_test "Get Current User (/me)"
ME_RESPONSE=$(api_call $CURL_FLAGS $BASE_URL/me -b $COOKIES_FILE)
JOSE_ID=$(echo "$ME_RESPONSE" | jq -r '.id')
[ "$JOSE_ID" != "null" ] && [ -n "$JOSE_ID" ]
echo -e "${GREEN}✓ Current user verified with ID: $JOSE_ID${NC}\n"

run_test "Login as Jose"
LOGIN_RESPONSE=$(api_call $CURL_FLAGS -X POST $BASE_URL/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$JOSE_EMAIL\",\"password\":\"$PASSWORD\"}" \
  -c $COOKIES_FILE)
echo "$LOGIN_RESPONSE" | jq -e '.message' > /dev/null
LOGIN_ME=$(api_call $CURL_FLAGS $BASE_URL/me -b $COOKIES_FILE)
LOGIN_ID=$(echo "$LOGIN_ME" | jq -r '.id')
[ "$LOGIN_ID" = "$JOSE_ID" ]
echo -e "${GREEN}✓ Login successful${NC}\n"

run_test "Create Household"
HOUSEHOLD_RESPONSE=$(api_call $CURL_FLAGS -X POST $BASE_URL/households \
  -H "Content-Type: application/json" \
  -b $COOKIES_FILE \
  -d '{"name":"Casa de Jose"}')
HOUSEHOLD_ID=$(echo "$HOUSEHOLD_RESPONSE" | jq -r '.id')
[ "$HOUSEHOLD_ID" != "null" ] && [ -n "$HOUSEHOLD_ID" ]
echo -e "${GREEN}✓ Household created with ID: $HOUSEHOLD_ID${NC}\n"

# ═══════════════════════════════════════════════════════════
# ACCOUNT SETUP
# ═══════════════════════════════════════════════════════════

run_test "Create Savings Account"
ACCOUNT=$(api_call $CURL_FLAGS -X POST $BASE_URL/accounts \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"owner_id\":\"$JOSE_ID\",\"name\":\"Cuenta de Ahorros\",\"type\":\"savings\",\"initial_balance\":5500000}")
ACCOUNT_ID=$(echo "$ACCOUNT" | jq -r '.id')
[ "$ACCOUNT_ID" != "null" ] && [ -n "$ACCOUNT_ID" ]
echo -e "${GREEN}✓ Created savings account: $ACCOUNT_ID${NC}\n"

run_test "Create Cash Account"
CASH_ACCOUNT=$(api_call $CURL_FLAGS -X POST $BASE_URL/accounts \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"owner_id\":\"$JOSE_ID\",\"name\":\"Efectivo\",\"type\":\"cash\",\"initial_balance\":200000}")
CASH_ACCOUNT_ID=$(echo "$CASH_ACCOUNT" | jq -r '.id')
[ "$CASH_ACCOUNT_ID" != "null" ] && [ -n "$CASH_ACCOUNT_ID" ]
echo -e "${GREEN}✓ Created cash account: $CASH_ACCOUNT_ID${NC}\n"

# ═══════════════════════════════════════════════════════════
# INCOME CRUD OPERATIONS
# ═══════════════════════════════════════════════════════════

echo -e "\n${BLUE}═══ INCOME CRUD OPERATIONS ═══${NC}\n"

run_test "Create Salary Income"
CREATE_INCOME=$(api_call $CURL_FLAGS -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"salary\",\"amount\":5000000,\"description\":\"Salario Enero 2026\",\"income_date\":\"2026-01-15\"}")
echo "$CREATE_INCOME" | jq -e '.id' > /dev/null
INCOME_ID=$(echo "$CREATE_INCOME" | jq -r '.id')
echo "$CREATE_INCOME" | jq -e '.type == "salary"' > /dev/null
echo "$CREATE_INCOME" | jq -e '.amount == 5000000' > /dev/null
echo -e "${GREEN}✓ Created salary income: $INCOME_ID${NC}\n"

run_test "Create Freelance Income"
CREATE_FREELANCE=$(api_call $CURL_FLAGS -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"freelance\",\"amount\":800000,\"description\":\"Proyecto X\",\"income_date\":\"2026-01-22\"}")
echo "$CREATE_FREELANCE" | jq -e '.id' > /dev/null
FREELANCE_ID=$(echo "$CREATE_FREELANCE" | jq -r '.id')
echo -e "${GREEN}✓ Created freelance income: $FREELANCE_ID${NC}\n"

run_test "Create Internal Movement (Savings Withdrawal)"
CREATE_WITHDRAWAL=$(api_call $CURL_FLAGS -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"savings_withdrawal\",\"amount\":1000000,\"description\":\"Retiro de bolsillo\",\"income_date\":\"2026-01-10\"}")
echo "$CREATE_WITHDRAWAL" | jq -e '.id' > /dev/null
WITHDRAWAL_ID=$(echo "$CREATE_WITHDRAWAL" | jq -r '.id')
echo -e "${GREEN}✓ Created savings withdrawal: $WITHDRAWAL_ID${NC}\n"

run_test "Create Bonus Income"
CREATE_BONUS=$(api_call $CURL_FLAGS -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$CASH_ACCOUNT_ID\",\"type\":\"bonus\",\"amount\":500000,\"description\":\"Bono de desempeño\",\"income_date\":\"2026-01-20\"}")
echo "$CREATE_BONUS" | jq -e '.id' > /dev/null
BONUS_ID=$(echo "$CREATE_BONUS" | jq -r '.id')
echo -e "${GREEN}✓ Created bonus income: $BONUS_ID${NC}\n"

run_test "List Income (No Filters)"
INCOME_LIST=$(api_call $CURL_FLAGS -X GET $BASE_URL/income -b $COOKIES_FILE)
INCOME_COUNT=$(echo "$INCOME_LIST" | jq '.income_entries | length')
[ "$INCOME_COUNT" -ge "4" ]
echo -e "${GREEN}✓ Listed $INCOME_COUNT income entries${NC}\n"

run_test "Verify Income Totals"
TOTAL_AMOUNT=$(echo "$INCOME_LIST" | jq -r '.totals.total_amount')
REAL_INCOME=$(echo "$INCOME_LIST" | jq -r '.totals.real_income_amount')
INTERNAL_MOVEMENTS=$(echo "$INCOME_LIST" | jq -r '.totals.internal_movements_amount')
echo "$INCOME_LIST" | jq -e '.totals.total_amount == 7300000' > /dev/null
echo "$INCOME_LIST" | jq -e '.totals.real_income_amount == 6300000' > /dev/null
echo "$INCOME_LIST" | jq -e '.totals.internal_movements_amount == 1000000' > /dev/null
echo -e "${GREEN}✓ Totals verified (total: $TOTAL_AMOUNT, real: $REAL_INCOME, internal: $INTERNAL_MOVEMENTS)${NC}\n"

run_test "Get Income by ID"
GET_INCOME=$(api_call $CURL_FLAGS -X GET $BASE_URL/income/$INCOME_ID -b $COOKIES_FILE)
echo "$GET_INCOME" | jq -e '.id == "'$INCOME_ID'"' > /dev/null
echo "$GET_INCOME" | jq -e '.member_name' > /dev/null
echo "$GET_INCOME" | jq -e '.account_name' > /dev/null
echo "$GET_INCOME" | jq -e '.description == "Salario Enero 2026"' > /dev/null
echo -e "${GREEN}✓ Retrieved income details with enriched data${NC}\n"

run_test "Update Income"
UPDATE_INCOME=$(api_call $CURL_FLAGS -X PATCH $BASE_URL/income/$INCOME_ID \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d '{"amount":5200000,"description":"Salario Enero + Bono"}')
echo "$UPDATE_INCOME" | jq -e '.amount == 5200000' > /dev/null
echo "$UPDATE_INCOME" | jq -e '.description == "Salario Enero + Bono"' > /dev/null
echo -e "${GREEN}✓ Updated income (amount: 5000000 → 5200000)${NC}\n"

run_test "Update Income Type"
UPDATE_TYPE=$(api_call $CURL_FLAGS -X PATCH $BASE_URL/income/$FREELANCE_ID \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d '{"type":"bonus","description":"Proyecto X - Reclasificado como Bono"}')
echo "$UPDATE_TYPE" | jq -e '.type == "bonus"' > /dev/null
echo -e "${GREEN}✓ Updated income type (freelance → bonus)${NC}\n"

run_test "Update Income Account"
UPDATE_ACCOUNT=$(api_call $CURL_FLAGS -X PATCH $BASE_URL/income/$BONUS_ID \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"account_id\":\"$ACCOUNT_ID\"}")
echo "$UPDATE_ACCOUNT" | jq -e '.account_id == "'$ACCOUNT_ID'"' > /dev/null
echo -e "${GREEN}✓ Updated income account (cash → savings)${NC}\n"

run_test "Delete Income"
DELETE_INCOME_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X DELETE $BASE_URL/income/$WITHDRAWAL_ID -b $COOKIES_FILE)
[ "$DELETE_INCOME_STATUS" = "204" ]
echo -e "${GREEN}✓ Deleted income: $WITHDRAWAL_ID${NC}\n"

# ═══════════════════════════════════════════════════════════
# FILTERING AND QUERYING
# ═══════════════════════════════════════════════════════════

echo -e "\n${BLUE}═══ FILTERING AND QUERYING ═══${NC}\n"

run_test "Filter Income by Member"
MEMBER_INCOME=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?member_id=$JOSE_ID" -b $COOKIES_FILE)
MEMBER_COUNT=$(echo "$MEMBER_INCOME" | jq '.income_entries | length')
[ "$MEMBER_COUNT" -ge "3" ]
echo -e "${GREEN}✓ Filtered by member: $MEMBER_COUNT entries${NC}\n"

run_test "Filter Income by Account"
ACCOUNT_INCOME=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?account_id=$ACCOUNT_ID" -b $COOKIES_FILE)
ACCOUNT_COUNT=$(echo "$ACCOUNT_INCOME" | jq '.income_entries | length')
[ "$ACCOUNT_COUNT" -ge "2" ]
echo -e "${GREEN}✓ Filtered by account: $ACCOUNT_COUNT entries${NC}\n"

run_test "Filter Income by Month"
MONTH_INCOME=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?month=2026-01" -b $COOKIES_FILE)
MONTH_COUNT=$(echo "$MONTH_INCOME" | jq '.income_entries | length')
[ "$MONTH_COUNT" -ge "3" ]
echo -e "${GREEN}✓ Filtered by month: $MONTH_COUNT entries${NC}\n"

run_test "Filter Income by Type (salary)"
TYPE_INCOME=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?type=salary" -b $COOKIES_FILE)
TYPE_COUNT=$(echo "$TYPE_INCOME" | jq '.income_entries | length')
[ "$TYPE_COUNT" -ge "1" ]
echo -e "${GREEN}✓ Filtered by type (salary): $TYPE_COUNT entries${NC}\n"

run_test "Filter Income by Type (bonus)"
BONUS_INCOME=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?type=bonus" -b $COOKIES_FILE)
BONUS_COUNT=$(echo "$BONUS_INCOME" | jq '.income_entries | length')
[ "$BONUS_COUNT" -ge "2" ]
echo -e "${GREEN}✓ Filtered by type (bonus): $BONUS_COUNT entries${NC}\n"

run_test "Combine Filters (member + month)"
COMBINED=$(api_call $CURL_FLAGS -X GET "$BASE_URL/income?member_id=$JOSE_ID&month=2026-01" -b $COOKIES_FILE)
COMBINED_COUNT=$(echo "$COMBINED" | jq '.income_entries | length')
[ "$COMBINED_COUNT" -ge "3" ]
echo -e "${GREEN}✓ Combined filters: $COMBINED_COUNT entries${NC}\n"

# ═══════════════════════════════════════════════════════════
# VALIDATION AND ERROR CASES
# ═══════════════════════════════════════════════════════════

echo -e "\n${BLUE}═══ VALIDATION AND ERROR CASES ═══${NC}\n"

run_test "Prevent Income to Checking Account"
CREATE_CHECKING=$(api_call $CURL_FLAGS -X POST $BASE_URL/accounts \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"owner_id\":\"$JOSE_ID\",\"name\":\"Cuenta Corriente\",\"type\":\"checking\"}")
CHECKING_ID=$(echo "$CREATE_CHECKING" | jq -r '.id')
if [ "$CHECKING_ID" = "null" ] || [ -z "$CHECKING_ID" ]; then
  echo -e "${RED}Failed to create checking account${NC}"
  exit 1
fi
INVALID_INCOME_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$CHECKING_ID\",\"type\":\"salary\",\"amount\":1000000,\"description\":\"Test\",\"income_date\":\"2026-01-15\"}")
[ "$INVALID_INCOME_STATUS" = "400" ]
echo -e "${GREEN}✓ Prevented income to checking account${NC}\n"

run_test "Reject Negative Amount"
NEGATIVE_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"salary\",\"amount\":-1000,\"description\":\"Test\",\"income_date\":\"2026-01-15\"}")
[ "$NEGATIVE_STATUS" = "400" ]
echo -e "${GREEN}✓ Rejected negative amount${NC}\n"

run_test "Reject Zero Amount"
ZERO_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"salary\",\"amount\":0,\"description\":\"Test\",\"income_date\":\"2026-01-15\"}")
[ "$ZERO_STATUS" = "400" ]
echo -e "${GREEN}✓ Rejected zero amount${NC}\n"

run_test "Reject Missing Required Fields"
MISSING_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d '{"amount":1000000}')
[ "$MISSING_STATUS" = "400" ]
echo -e "${GREEN}✓ Rejected missing required fields${NC}\n"

run_test "Reject Invalid Income Type"
INVALID_TYPE_STATUS=$(curl $CURL_FLAGS -w "%{http_code}" -o /dev/null -X POST $BASE_URL/income \
  -b $COOKIES_FILE \
  -H "Content-Type: application/json" \
  -d "{\"member_id\":\"$JOSE_ID\",\"account_id\":\"$ACCOUNT_ID\",\"type\":\"invalid_type\",\"amount\":1000000,\"description\":\"Test\",\"income_date\":\"2026-01-15\"}")
[ "$INVALID_TYPE_STATUS" = "400" ]
echo -e "${GREEN}✓ Rejected invalid income type${NC}\n"

# ═══════════════════════════════════════════════════════════
# ACCOUNT BALANCE VERIFICATION
# ═══════════════════════════════════════════════════════════

echo -e "\n${BLUE}═══ ACCOUNT BALANCE VERIFICATION ═══${NC}\n"

run_test "Verify Account Balance After Income"
BALANCE_ACCOUNT=$(api_call $CURL_FLAGS -X GET $BASE_URL/accounts/$ACCOUNT_ID -b $COOKIES_FILE)
# Initial balance 5500000 + salary (5200000 updated) + freelance (800000) + bonus (500000 moved here) = 12000000
echo "$BALANCE_ACCOUNT" | jq -e '.current_balance == 12000000' > /dev/null
CURRENT_BALANCE=$(echo "$BALANCE_ACCOUNT" | jq -r '.current_balance')
echo -e "${GREEN}✓ Account balance correct: $CURRENT_BALANCE${NC}\n"

run_test "Verify Cash Account Balance"
CASH_BALANCE=$(api_call $CURL_FLAGS -X GET $BASE_URL/accounts/$CASH_ACCOUNT_ID -b $COOKIES_FILE)
# Initial balance 200000 (bonus was moved to savings account)
echo "$CASH_BALANCE" | jq -e '.current_balance == 200000' > /dev/null
CASH_CURRENT=$(echo "$CASH_BALANCE" | jq -r '.current_balance')
echo -e "${GREEN}✓ Cash account balance correct: $CASH_CURRENT${NC}\n"

# ═══════════════════════════════════════════════════════════
# AUDIT LOGGING VERIFICATION
# ═══════════════════════════════════════════════════════════

echo -e "\n${BLUE}═══ AUDIT LOGGING VERIFICATION ═══${NC}\n"

run_test "Verify audit logs for income creation"
INCOME_AUDIT_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action = 'INCOME_CREATED'
    AND resource_id IN ('$INCOME_ID', '$FREELANCE_ID', '$BONUS_ID')
    AND success = true
")
INCOME_AUDIT_COUNT=$(echo "$INCOME_AUDIT_COUNT" | xargs)
[ "$INCOME_AUDIT_COUNT" = "3" ]
echo -e "${GREEN}✓ Found $INCOME_AUDIT_COUNT audit logs for income creation${NC}\n"

run_test "Verify audit logs for income update (amount change)"
INCOME_UPDATE_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action = 'INCOME_UPDATED'
    AND resource_id = '$INCOME_ID'
    AND success = true
")
INCOME_UPDATE_COUNT=$(echo "$INCOME_UPDATE_COUNT" | xargs)
[ "$INCOME_UPDATE_COUNT" = "1" ]
echo -e "${GREEN}✓ Found audit log for income amount update${NC}\n"

run_test "Verify income update audit has old and new values"
INCOME_UPDATE_AUDIT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT 
    old_values::text,
    new_values::text
  FROM audit_logs 
  WHERE action = 'INCOME_UPDATED' 
    AND resource_id = '$INCOME_ID'
  LIMIT 1
")
# Check old values contain original amount (5000000)
echo "$INCOME_UPDATE_AUDIT" | grep -q "5000000"
# Check new values contain updated amount (5200000)
echo "$INCOME_UPDATE_AUDIT" | grep -q "5200000"
# Check new values contain updated description
echo "$INCOME_UPDATE_AUDIT" | grep -q "Salario Enero + Bono"
echo -e "${GREEN}✓ Income update audit log contains old and new values${NC}\n"

run_test "Verify audit logs for income type update"
TYPE_UPDATE_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action = 'INCOME_UPDATED'
    AND resource_id = '$FREELANCE_ID'
    AND success = true
")
TYPE_UPDATE_COUNT=$(echo "$TYPE_UPDATE_COUNT" | xargs)
[ "$TYPE_UPDATE_COUNT" = "1" ]
echo -e "${GREEN}✓ Found audit log for income type update${NC}\n"

run_test "Verify audit logs for income account update"
ACCOUNT_UPDATE_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action = 'INCOME_UPDATED'
    AND resource_id = '$BONUS_ID'
    AND success = true
")
ACCOUNT_UPDATE_COUNT=$(echo "$ACCOUNT_UPDATE_COUNT" | xargs)
[ "$ACCOUNT_UPDATE_COUNT" = "1" ]
echo -e "${GREEN}✓ Found audit log for income account update${NC}\n"

run_test "Verify audit logs for income deletion"
INCOME_DELETE_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action = 'INCOME_DELETED'
    AND resource_id = '$WITHDRAWAL_ID'
    AND success = true
")
INCOME_DELETE_COUNT=$(echo "$INCOME_DELETE_COUNT" | xargs)
[ "$INCOME_DELETE_COUNT" = "1" ]
echo -e "${GREEN}✓ Found audit log for income deletion${NC}\n"

run_test "Verify income deletion audit has old values"
INCOME_DELETE_SNAPSHOT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT old_values::text 
  FROM audit_logs 
  WHERE action = 'INCOME_DELETED' 
    AND resource_id = '$WITHDRAWAL_ID'
  LIMIT 1
")
echo "$INCOME_DELETE_SNAPSHOT" | grep -q "$WITHDRAWAL_ID"
echo "$INCOME_DELETE_SNAPSHOT" | grep -q "1000000"
echo "$INCOME_DELETE_SNAPSHOT" | grep -q "savings_withdrawal"
echo -e "${GREEN}✓ Income deletion audit log contains old values${NC}\n"

run_test "Verify all income audit logs have user tracking"
USER_TRACKED_COUNT=$(PAGER=cat psql $DATABASE_URL -t -c "
  SELECT COUNT(*) 
  FROM audit_logs 
  WHERE action IN ('INCOME_CREATED', 'INCOME_UPDATED', 'INCOME_DELETED')
    AND user_id = '$JOSE_ID'
    AND success = true
")
USER_TRACKED_COUNT=$(echo "$USER_TRACKED_COUNT" | xargs)
[ "$USER_TRACKED_COUNT" -ge "6" ]
echo -e "${GREEN}✓ All income audit logs have user tracking ($USER_TRACKED_COUNT logs)${NC}\n"

# ═══════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════

echo -e "\n${GREEN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║              ✅ ALL TESTS PASSED! ✅                   ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

echo -e "${CYAN}Test Summary:${NC}"
echo -e "  • CRUD Operations: ✓"
echo -e "  • Filtering & Querying: ✓"
echo -e "  • Validation & Error Cases: ✓"
echo -e "  • Account Balance Verification: ✓"
echo -e "  • Audit Logging: ✓"
echo ""
