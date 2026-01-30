# Phase 9: Credit Cards (Tarjetas de Crédito)

> **Status:** 📋 PLANNED
>
> This phase implements the "Tarjetas de crédito" tab to track credit card debt,
> answer the question: "How much do I need to pay for each card this billing cycle?"

**Architecture:**

- Authentication & Households: PostgreSQL + Go backend ✅
- Movements: PostgreSQL + Go backend ✅
- Payment Methods: PostgreSQL + Go backend ✅
- Accounts: PostgreSQL + Go backend ✅
- **NEW:** Credit card payments → PostgreSQL
- **NEW:** Credit card billing cycle tracking
- **NEW:** Payment method cut-off day field
- **NEW:** Debit card → Savings account link

**Relationship to other phases:**

- See `03_PAYMENT_METHODS_PHASE.md` for payment methods (credit cards)
- See `04_ACCOUNTS_AND_INCOME_PHASE.md` for accounts (savings, cash)
- See `05_MOVEMENTS_PHASE.md` for movements tracking
- See `FUTURE_VISION.md` section 4.4 for product vision

---

## 🎯 Goals

### Primary Goals

1. **Track real credit card debt per billing cycle**
   - Show total amount charged to each credit card
   - NOT the household's portion of SPLIT expenses - the FULL amount paid
   - This answers: "How much must I pay to the bank?"

2. **Billing cycle awareness**
   - Each card has a cut-off day (e.g., 15th of month)
   - Show movements within the billing cycle (e.g., Dec 16 - Jan 15)
   - Navigate between billing cycles (like month navigation)

3. **Credit card payments tracking**
   - Register payments made TO the credit card (abonos)
   - Track from which savings account the payment came
   - Decrease source account balance automatically

4. **Cash reality check**
   - Show total available cash (savings accounts only)
   - Compare against total credit card debt
   - Answer: "Can I pay my cards this month?"

5. **Accurate savings account balance**
   - Track debit card spending (link debit cards to accounts)
   - Balance = initial + income - debit_spending - card_payments

### Why This Matters

From `FUTURE_VISION.md`:
> "I paid with credit card — will I be able to pay it at the end of the month?"

Current pain points:
- No visibility into actual credit card debt
- Can't easily see if savings cover upcoming card payments
- Must manually calculate billing cycles
- Card payments not tracked systematically
- Debit card spending not linked to account balances

---

## 📊 Key Concepts

### Credit Card Debt Calculation

**Important:** The Tarjetas view shows **real debt to the bank**, not household expense allocation.

Example:
- Jose pays $100 dinner with AMEX
- SPLIT: Jose 60%, Caro 40%
- In **Gastos tab**: Shows as $100 expense, Jose's share is $60
- In **Tarjetas tab**: AMEX shows $100 debt (the full card charge)
- Why? Caro pays Jose back to his savings, but Jose still owes $100 to AMEX

### Billing Cycle

Each credit card has a **cut-off day** (día de corte):
- Cut-off day 15 means: cycle runs from 16th of previous month to 15th of current month
- Example: January cycle = Dec 16, 2025 → Jan 15, 2026

**Default cut-off:** Last day of month (handles 28/29/30/31 automatically)

### Card Payments (Abonos)

When user pays their credit card bill:
- Creates a `credit_card_payment` record
- Decreases source savings account balance
- Shows in Tarjetas view under "Pagos a tarjeta" for that card
- Net debt = Total Gastos - Total Pagos a tarjeta

### Savings Account Balance

Balance is calculated dynamically (only for savings accounts, not cash):

```
balance = initial_balance 
        + SUM(income to this account)
        - SUM(movements paid with debit cards linked to this account)
        - SUM(credit card payments from this account)
```

### Debit Card → Account Link

Each debit card **must** be linked to a savings account:
- When a movement is paid with a debit card, it reduces the linked account balance
- This ensures accurate "available cash" calculation
- Enforced at debit card creation/update time

---

## 📊 Data Model

### Modified Tables

#### `payment_methods` - Add cut-off day and account link

```sql
-- Migration: Add cutoff_day and linked_account_id to payment_methods
ALTER TABLE payment_methods
ADD COLUMN cutoff_day INTEGER CHECK (cutoff_day >= 1 AND cutoff_day <= 31);

ALTER TABLE payment_methods
ADD COLUMN linked_account_id UUID REFERENCES accounts(id) ON DELETE RESTRICT;

-- NULL cutoff_day means "last day of month" (default behavior)
-- 1-28: specific day (safe for all months)
-- 29-31: will use last day if month is shorter

-- linked_account_id is REQUIRED for debit cards, NULL for others
-- Constraint enforced in application logic

COMMENT ON COLUMN payment_methods.cutoff_day IS 
  'Credit card billing cycle cut-off day. NULL = last day of month. Only applicable for credit_card type.';

COMMENT ON COLUMN payment_methods.linked_account_id IS 
  'For debit cards: the savings account this card draws from. Required for debit_card type, NULL for others.';

-- Index for linked account lookups
CREATE INDEX idx_payment_methods_linked_account ON payment_methods(linked_account_id) 
  WHERE linked_account_id IS NOT NULL;
```

### New Tables

#### `credit_card_payments`

Tracks payments made TO credit cards (paying off the balance).

```sql
CREATE TABLE credit_card_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  
  -- Which credit card is being paid
  credit_card_id UUID NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  
  -- Payment details
  amount DECIMAL(15, 2) NOT NULL CHECK (amount > 0),
  payment_date DATE NOT NULL,
  notes TEXT,
  
  -- Source of payment (must be a savings account)
  source_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);

-- Indexes
CREATE INDEX idx_cc_payments_household ON credit_card_payments(household_id);
CREATE INDEX idx_cc_payments_credit_card ON credit_card_payments(credit_card_id);
CREATE INDEX idx_cc_payments_date ON credit_card_payments(payment_date);
CREATE INDEX idx_cc_payments_source ON credit_card_payments(source_account_id);

-- Constraint: source must be savings account (enforced in application logic)
```

### Savings Account Balance Calculation

Balance is calculated dynamically (not stored):

```sql
-- For savings accounts:
-- balance = initial_balance 
--         + SUM(income to this account)
--         - SUM(movements paid with debit cards linked to this account)
--         - SUM(card payments from this account)

WITH debit_spending AS (
  -- Sum of movements paid with debit cards linked to this account
  SELECT 
    pm.linked_account_id as account_id,
    COALESCE(SUM(m.amount), 0) as total
  FROM movements m
  JOIN payment_methods pm ON pm.id = m.payment_method_id
  WHERE pm.type = 'debit_card'
    AND pm.linked_account_id IS NOT NULL
  GROUP BY pm.linked_account_id
)
SELECT 
  a.id,
  a.name,
  a.type,
  COALESCE(a.initial_balance, 0) 
    + COALESCE(income.total, 0) 
    - COALESCE(debit.total, 0)
    - COALESCE(card_payments.total, 0) AS current_balance
FROM accounts a
LEFT JOIN (
  SELECT account_id, SUM(amount) as total 
  FROM income 
  GROUP BY account_id
) income ON income.account_id = a.id
LEFT JOIN debit_spending debit ON debit.account_id = a.id
LEFT JOIN (
  SELECT source_account_id, SUM(amount) as total 
  FROM credit_card_payments 
  GROUP BY source_account_id
) card_payments ON card_payments.source_account_id = a.id
WHERE a.household_id = $1 
  AND a.type = 'savings';
```

---

## 🔌 Backend API

### Payment Methods - Update for cut-off day and account link

#### Update payment method
```
PATCH /api/payment-methods/:id
Authorization: Bearer <token>

Body:
{
  "cutoff_day": 15,           // 1-31, or null for last day of month (credit cards only)
  "linked_account_id": "uuid" // Required for debit cards
}

Response 200:
{
  "id": "uuid",
  "name": "AMEX Jose",
  "type": "credit_card",
  "cutoff_day": 15,
  "linked_account_id": null,
  ...
}

Errors:
400 - Debit card must have linked_account_id
400 - Linked account must be a savings account
400 - cutoff_day only valid for credit cards
```

### Credit Card Payments Endpoints

#### Create credit card payment
```
POST /api/credit-card-payments
Authorization: Bearer <token>

Body:
{
  "credit_card_id": "uuid",
  "amount": 500000,
  "payment_date": "2026-01-30",
  "source_account_id": "uuid",
  "notes": "Pago parcial AMEX"  // optional
}

Response 201:
{
  "id": "uuid",
  "credit_card_id": "uuid",
  "credit_card_name": "AMEX Jose",
  "amount": 500000,
  "payment_date": "2026-01-30",
  "source_account_id": "uuid",
  "source_account_name": "Cuenta Ahorros Bancolombia",
  "notes": "Pago parcial AMEX",
  "created_at": "timestamp",
  "created_by": "uuid"
}

Errors:
400 - Missing required fields
400 - Source account must be a savings account
400 - Payment method is not a credit card
404 - Credit card not found
404 - Source account not found
403 - Not authorized (wrong household)
```

#### List credit card payments
```
GET /api/credit-card-payments?credit_card_id=uuid&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
Authorization: Bearer <token>

Query params:
- credit_card_id (optional): Filter by specific card
- start_date (optional): Filter by date range
- end_date (optional): Filter by date range

Response 200:
{
  "payments": [
    {
      "id": "uuid",
      "credit_card_id": "uuid",
      "credit_card_name": "AMEX Jose",
      "amount": 500000,
      "payment_date": "2026-01-30",
      "source_account_id": "uuid",
      "source_account_name": "Cuenta Ahorros Bancolombia",
      "notes": "Pago parcial AMEX",
      "created_at": "timestamp"
    }
  ],
  "total": 500000
}
```

#### Delete credit card payment
```
DELETE /api/credit-card-payments/:id
Authorization: Bearer <token>

Response 204: (no content)

Errors:
404 - Payment not found
403 - Not authorized
```

### Credit Card Summary Endpoint

#### Get credit card summary for billing cycle
```
GET /api/credit-cards/summary?cycle_date=YYYY-MM-DD
Authorization: Bearer <token>

Query params:
- cycle_date: Any date within the billing cycle (default: today)

Response 200:
{
  "billing_cycle": {
    "start_date": "2025-12-16",
    "end_date": "2026-01-15",
    "label": "Dic 16 - Ene 15"
  },
  "cards": [
    {
      "id": "uuid",
      "name": "AMEX Jose",
      "owner_id": "uuid",
      "owner_name": "Jose",
      "cutoff_day": 15,
      "institution": "American Express",
      "last4": "1234",
      "total_charges": 1500000,    // Sum of movements paid with this card
      "total_payments": 500000,    // Sum of credit_card_payments
      "net_debt": 1000000,         // charges - payments
      "movement_count": 12,
      "payment_count": 1
    },
    {
      "id": "uuid",
      "name": "Nu Caro",
      "owner_id": "uuid",
      "owner_name": "Caro",
      "cutoff_day": null,  // Last day of month
      "institution": "Nu",
      "last4": "5678",
      "total_charges": 800000,
      "total_payments": 0,
      "net_debt": 800000,
      "movement_count": 5,
      "payment_count": 0
    }
  ],
  "totals": {
    "total_charges": 2300000,
    "total_payments": 500000,
    "total_debt": 1800000
  },
  "available_cash": {
    "total": 5000000,
    "accounts": [
      {
        "id": "uuid",
        "name": "Cuenta Ahorros Bancolombia",
        "type": "savings",
        "balance": 4500000
      },
      {
        "id": "uuid",
        "name": "Cuenta Ahorros Nequi",
        "type": "savings",
        "balance": 500000
      }
    ]
  },
  "can_pay_all": true  // available_cash.total >= totals.total_debt
}
```

### Credit Card Movements Endpoint

#### Get movements for a specific credit card in billing cycle
```
GET /api/credit-cards/:id/movements?cycle_date=YYYY-MM-DD
Authorization: Bearer <token>

Response 200:
{
  "credit_card": {
    "id": "uuid",
    "name": "AMEX Jose",
    "owner_name": "Jose",
    "cutoff_day": 15
  },
  "billing_cycle": {
    "start_date": "2025-12-16",
    "end_date": "2026-01-15",
    "label": "Dic 16 - Ene 15"
  },
  "charges": {
    "movements": [
      {
        "id": "uuid",
        "type": "HOUSEHOLD",
        "description": "Mercado Exito",
        "amount": 250000,
        "movement_date": "2026-01-10",
        "category_name": "Mercado",
        "payer_name": "Jose"
      },
      {
        "id": "uuid",
        "type": "SPLIT",
        "description": "Cena cumpleaños",
        "amount": 180000,  // Full amount, not split portion
        "movement_date": "2026-01-08",
        "category_name": "Salidas juntos",
        "payer_name": "Jose"
      }
    ],
    "total": 430000
  },
  "payments": {
    "items": [
      {
        "id": "uuid",
        "amount": 200000,
        "payment_date": "2026-01-05",
        "source_account_name": "Cuenta Ahorros",
        "notes": "Abono parcial"
      }
    ],
    "total": 200000
  },
  "net_debt": 230000
}
```

### Accounts Endpoint - Add Balance

#### Get accounts with calculated balances
```
GET /api/accounts?with_balance=true
Authorization: Bearer <token>

Response 200:
[
  {
    "id": "uuid",
    "name": "Cuenta Ahorros Bancolombia",
    "type": "savings",
    "initial_balance": 1000000,
    "current_balance": 4500000,  // NEW: calculated balance
    "institution": "Bancolombia",
    ...
  },
  {
    "id": "uuid",
    "name": "Efectivo",
    "type": "cash",
    "initial_balance": 100000,
    "current_balance": null,  // Not tracked for cash
    ...
  }
]
```

---

## 🎨 Frontend Implementation

### UI Structure (Tarjetas Tab)

```
┌─────────────────────────────────────────────────────────┐
│ Resumen mensual                                    [☰]  │
├─────────────────────────────────────────────────────────┤
│ [Gastos] [Ingresos] [Préstamos] [Presupuesto] [Tarjetas]│
├─────────────────────────────────────────────────────────┤
│      ← Dic 16 - Ene 15, 2026 →                         │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │  Total deuda tarjetas         Efectivo disponible   │ │
│ │  $1,800,000                   $5,000,000            │ │
│ │  ✓ Puedes pagar todas las tarjetas                  │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 💳 AMEX Jose                              $1,000,000│ │
│ │    Jose • ****1234 • Corte: día 15                  │ │
│ │    ▼ Click to expand                                │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 💳 Nu Caro                                  $800,000│ │
│ │    Caro • ****5678 • Corte: fin de mes              │ │
│ │    ▼ Click to expand                                │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│                                              [🔍] [+]   │
└─────────────────────────────────────────────────────────┘
```

### Expanded Card View (3-Level Hierarchy)

```
┌─────────────────────────────────────────────────────────┐
│ 💳 AMEX Jose                                $1,000,000  │
│    Jose • ****1234 • Corte: día 15           [▲ collapse]│
│ ├─────────────────────────────────────────────────────┤ │
│ │ 📤 Gastos                                 $1,500,000 │ │
│ │    ▼ Click to expand                                │ │
│ ├─────────────────────────────────────────────────────┤ │
│ │ 📥 Pagos a tarjeta                          $500,000 │ │
│ │    ▼ Click to expand                                │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Expanded Gastos/Pagos View

```
┌─────────────────────────────────────────────────────────┐
│ 📤 Gastos                                   $1,500,000  │
│    ▲ Click to collapse                                  │
│ ├───────────────────────────────────────────────────────┤
│ │ Mercado Exito                                         │
│ │ $250,000 • 10 Ene 2026 • Mercado              [⋮]    │
│ ├───────────────────────────────────────────────────────┤
│ │ Cena cumpleaños                                       │
│ │ $180,000 • 8 Ene 2026 • Salidas juntos        [⋮]    │
│ ├───────────────────────────────────────────────────────┤
│ │ ...more movements...                                  │
│ └───────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 📥 Pagos a tarjeta                            $500,000  │
│    ▲ Click to collapse                                  │
│ ├───────────────────────────────────────────────────────┤
│ │ Abono parcial                                         │
│ │ $500,000 • 5 Ene 2026 • Desde: Cta Ahorros    [⋮]    │
│ └───────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘
```

### Filter Dropdown

```
┌─────────────────────────────────────────────────────────┐
│ Filtrar por                                             │
├─────────────────────────────────────────────────────────┤
│ Tarjeta                                                 │
│ ☑ AMEX Jose                                            │
│ ☑ MasterCard Oro Jose                                  │
│ ☑ Nu Caro                                              │
├─────────────────────────────────────────────────────────┤
│ Propietario                                             │
│ ☑ Jose                                                 │
│ ☑ Caro                                                 │
├─────────────────────────────────────────────────────────┤
│ [Todos] [Limpiar]                           [Aplicar]  │
└─────────────────────────────────────────────────────────┘
```

### Add Card Payment Modal

```
┌─────────────────────────────────────────────────────────┐
│ Registrar pago a tarjeta                           [×]  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Tarjeta *                                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ ▾ AMEX Jose                                         │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Monto *                                                 │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 500.000                                             │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Fecha *                                                 │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 30/01/2026                                          │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Cuenta origen *                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ ▾ Cuenta Ahorros Bancolombia ($4,500,000)           │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Notas (opcional)                                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Pago parcial enero                                  │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│                              [Cancelar] [Registrar]     │
└─────────────────────────────────────────────────────────┘
```

### Payment Methods Form Update

#### Cut-off Day (Credit Cards Only)

```
┌─────────────────────────────────────────────────────────┐
│ Día de corte                                            │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ ▾ Último día del mes                                │ │
│ │   ─────────────────                                 │ │
│ │   1                                                 │ │
│ │   2                                                 │ │
│ │   ...                                               │ │
│ │   15                                                │ │
│ │   ...                                               │ │
│ │   28                                                │ │
│ └─────────────────────────────────────────────────────┘ │
│ ℹ️ El ciclo de facturación va del día siguiente al      │
│    corte hasta el día de corte del mes siguiente.       │
└─────────────────────────────────────────────────────────┘
```

#### Linked Account (Debit Cards Only - REQUIRED)

```
┌─────────────────────────────────────────────────────────┐
│ Cuenta vinculada *                                      │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ ▾ Cuenta Ahorros Bancolombia                        │ │
│ │   ─────────────────                                 │ │
│ │   Cuenta Ahorros Bancolombia                        │ │
│ │   Cuenta Ahorros Nequi                              │ │
│ └─────────────────────────────────────────────────────┘ │
│ ℹ️ Los pagos con esta tarjeta débito se descontarán     │
│    del saldo de la cuenta seleccionada.                 │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Implementation Details

### Billing Cycle Calculation

```go
// GetBillingCycle returns start and end dates for a billing cycle
// containing the given reference date.
func GetBillingCycle(referenceDate time.Time, cutoffDay *int) (start, end time.Time) {
    // Default to last day of month if cutoffDay is nil
    if cutoffDay == nil || *cutoffDay > 28 {
        // Use last day of month logic
        return getBillingCycleLastDay(referenceDate)
    }
    
    day := *cutoffDay
    year, month, refDay := referenceDate.Year(), referenceDate.Month(), referenceDate.Day()
    
    if refDay <= day {
        // Reference is before or on cutoff: cycle is prev month (day+1) to this month (day)
        prevMonth := month - 1
        prevYear := year
        if prevMonth < 1 {
            prevMonth = 12
            prevYear--
        }
        start = time.Date(prevYear, prevMonth, day+1, 0, 0, 0, 0, referenceDate.Location())
        end = time.Date(year, month, day, 23, 59, 59, 999999999, referenceDate.Location())
    } else {
        // Reference is after cutoff: cycle is this month (day+1) to next month (day)
        nextMonth := month + 1
        nextYear := year
        if nextMonth > 12 {
            nextMonth = 1
            nextYear++
        }
        start = time.Date(year, month, day+1, 0, 0, 0, 0, referenceDate.Location())
        end = time.Date(nextYear, nextMonth, day, 23, 59, 59, 999999999, referenceDate.Location())
    }
    
    return start, end
}

// getBillingCycleLastDay handles cutoff on last day of month
func getBillingCycleLastDay(referenceDate time.Time) (start, end time.Time) {
    year, month, _ := referenceDate.Year(), referenceDate.Month(), referenceDate.Day()
    
    // End is last day of current month
    firstOfNextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, referenceDate.Location())
    end = firstOfNextMonth.Add(-time.Second)
    
    // Start is first day of current month
    start = time.Date(year, month, 1, 0, 0, 0, 0, referenceDate.Location())
    
    return start, end
}
```

### Movement Query for Credit Card Charges

```sql
-- Get all movements paid with a specific credit card in date range
SELECT 
    m.id,
    m.type,
    m.description,
    m.amount,  -- Full amount, not split portion
    m.movement_date,
    c.name as category_name,
    COALESCE(pu.name, pc.name) as payer_name
FROM movements m
LEFT JOIN categories c ON c.id = m.category_id
LEFT JOIN users pu ON pu.id = m.payer_user_id
LEFT JOIN contacts pc ON pc.id = m.payer_contact_id
WHERE m.payment_method_id = $1  -- credit card ID
  AND m.movement_date >= $2     -- cycle start
  AND m.movement_date <= $3     -- cycle end
  AND m.household_id = $4
ORDER BY m.movement_date DESC;
```

### Savings Account Balance Calculation

```sql
-- Calculate balance for savings accounts
WITH debit_spending AS (
  -- Sum of movements paid with debit cards linked to each account
  SELECT 
    pm.linked_account_id as account_id,
    COALESCE(SUM(m.amount), 0) as total
  FROM movements m
  JOIN payment_methods pm ON pm.id = m.payment_method_id
  WHERE pm.type = 'debit_card'
    AND pm.linked_account_id IS NOT NULL
    AND pm.household_id = $1
  GROUP BY pm.linked_account_id
),
income_totals AS (
  SELECT account_id, COALESCE(SUM(amount), 0) as total
  FROM income
  WHERE household_id = $1
  GROUP BY account_id
),
card_payment_totals AS (
  SELECT source_account_id, COALESCE(SUM(amount), 0) as total
  FROM credit_card_payments
  WHERE household_id = $1
  GROUP BY source_account_id
)
SELECT 
  a.id,
  a.name,
  a.type,
  a.initial_balance,
  COALESCE(a.initial_balance, 0) 
    + COALESCE(it.total, 0) 
    - COALESCE(ds.total, 0)
    - COALESCE(cpt.total, 0) AS current_balance
FROM accounts a
LEFT JOIN income_totals it ON it.account_id = a.id
LEFT JOIN debit_spending ds ON ds.account_id = a.id
LEFT JOIN card_payment_totals cpt ON cpt.source_account_id = a.id
WHERE a.household_id = $1 
  AND a.type = 'savings'
  AND a.is_active = true;
```

---

## ✅ Implementation Checklist

### Database Migrations

- [ ] Add `cutoff_day` column to `payment_methods` table
- [ ] Add `linked_account_id` column to `payment_methods` table
- [ ] Create `credit_card_payments` table
- [ ] Add indexes for performance

### Backend

- [ ] **Payment Methods Update**
  - [ ] Add `CutoffDay *int` field to types
  - [ ] Add `LinkedAccountID *string` field to types
  - [ ] Update repository to handle new fields
  - [ ] Update PATCH handler to accept new fields
  - [ ] Validate cutoff_day (1-31 or null, only for credit cards)
  - [ ] Validate linked_account_id (required for debit cards, must be savings account)

- [ ] **Credit Card Payments Module**
  - [ ] Create `internal/creditcardpayments` package
  - [ ] Types: CreditCardPayment, CreateInput
  - [ ] Repository: Create, List, Delete, GetByID
  - [ ] Service: Business logic, authorization, validation
  - [ ] Handlers: POST, GET, DELETE endpoints
  - [ ] Validate source account is savings type
  - [ ] Validate credit_card_id is a credit card

- [ ] **Credit Cards Summary Module**
  - [ ] Create `internal/creditcards` package (or extend movements)
  - [ ] GetSummary: Aggregate cards, charges, payments, available cash
  - [ ] GetCardMovements: List movements for a card in cycle
  - [ ] Billing cycle calculation logic
  - [ ] Available cash calculation (savings accounts with balance)

- [ ] **Accounts Balance Calculation**
  - [ ] Add `with_balance` query param to GET /accounts
  - [ ] Calculate: initial + income - debit_spending - card_payments
  - [ ] Only for savings accounts

### Frontend

- [ ] **Tarjetas Tab Structure**
  - [ ] Add billing cycle navigator (with cutoff-aware logic)
  - [ ] Add totals header (debt vs available cash)
  - [ ] Add card list with expandable details
  - [ ] Reuse CSS from Ingresos/Gastos/Préstamos views

- [ ] **Card Payment Modal**
  - [ ] Create modal component (similar to recurring movements)
  - [ ] Credit card dropdown (credit cards only)
  - [ ] Amount input with Colombian formatting
  - [ ] Date picker
  - [ ] Source account dropdown (savings only, with balance shown)
  - [ ] Notes field
  - [ ] Validation and submission

- [ ] **Filters**
  - [ ] Filter by card
  - [ ] Filter by owner
  - [ ] Reuse filter dropdown pattern from other tabs

- [ ] **Payment Methods Form**
  - [ ] Add cut-off day field (only for credit cards)
  - [ ] Add linked account field (only for debit cards, REQUIRED)
  - [ ] Dropdown: "Último día del mes" + days 1-28
  - [ ] Help text explaining fields

- [ ] **Data Loading**
  - [ ] Load credit card summary on tab activation
  - [ ] Load card movements on expansion
  - [ ] Refresh after payment creation/deletion

### Testing

- [ ] **Backend Integration Tests**
  - [ ] Create credit card payment
  - [ ] Reject payment from non-savings account
  - [ ] List payments with filters
  - [ ] Delete payment
  - [ ] Verify source account balance decreases
  - [ ] Verify credit card summary calculation
  - [ ] Test billing cycle edge cases (month boundaries)
  - [ ] Debit card must have linked account
  - [ ] Linked account must be savings type

- [ ] **E2E Tests**
  - [ ] View Tarjetas tab
  - [ ] Expand card to see movements and payments
  - [ ] Create card payment
  - [ ] Delete card payment
  - [ ] Verify totals update correctly
  - [ ] Navigate billing cycles
  - [ ] Filter by card/owner

---

## 🚀 Migration Strategy

### Existing Data

1. **Payment methods - Credit cards**: 
   - Existing credit cards get `cutoff_day = NULL` (last day of month)
   - Users can update via payment methods form

2. **Payment methods - Debit cards**:
   - Existing debit cards get `linked_account_id = NULL`
   - **IMPORTANT:** Users must link debit cards to accounts before balance calculation is accurate
   - Show warning in UI if debit cards are unlinked

3. **Credit card payments**:
   - New table, no historical data to migrate
   - Users start fresh tracking card payments

4. **Movements**:
   - Already have `payment_method_id` linking to credit/debit cards
   - No changes needed

### Rollout Plan

1. Deploy database migrations
2. Deploy backend with new endpoints
3. Deploy frontend with Tarjetas tab
4. **Prompt users to link debit cards to accounts**
5. Users configure cut-off days for their cards
6. Users start registering card payments

---

## 📝 Notes

### Design Decisions

1. **Separate table for card payments** (not movement type)
   - Card payments are internal transfers, not expenses
   - Shouldn't appear in Gastos or affect budget tracking
   - Simpler accounting model

2. **Dynamic balance calculation**
   - No risk of balance getting out of sync
   - Easy to audit and verify
   - Follows pattern from income tracking

3. **Full amount in Tarjetas view** (not split portion)
   - Matches real-world card statement
   - Users need to pay full amount to bank
   - Split reimbursements go to savings account

4. **Billing cycle navigation** (not calendar month)
   - Each card can have different cut-off day
   - Shows relevant movements for upcoming payment
   - More useful than arbitrary month view

5. **Balance only for savings accounts** (not cash)
   - Simplifies the model
   - Cash is typically not tracked precisely
   - Focus on bank accounts where reconciliation matters

6. **Debit cards must link to accounts**
   - Ensures accurate balance calculation
   - Makes the debit card → account relationship explicit
   - Required field for debit cards

### Future Enhancements

- Credit limit tracking
- Payment due date reminders
- Automatic card payment suggestions ("You usually pay X on day Y")
- Historical debt chart (debt over time)
- Card statement import (OCR/PDF parsing)
- Interest calculation for unpaid balances

---

## 🔗 Related Documents

- `FUTURE_VISION.md` - Section 4.4 (Credit cards & cash reality)
- `03_PAYMENT_METHODS_PHASE.md` - Payment methods implementation
- `04_ACCOUNTS_AND_INCOME_PHASE.md` - Accounts and balance tracking
- `05_MOVEMENTS_PHASE.md` - Movements with payment methods

---

**Last Updated:** 2026-01-30  
**Status:** 📋 PLANNED  
**Next Phase:** Implementation
