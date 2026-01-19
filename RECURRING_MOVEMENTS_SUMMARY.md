# Recurring Movements (Gastos Periódicos) - Implementation Summary

## 📋 Overview

This document provides a high-level summary of the Recurring Movements feature.

**Spanish term:** "Gastos Periódicos" (more accurate than "Gastos Fijos")

**For full details, see:** `docs/design/08_RECURRING_MOVEMENTS_PHASE.md`

---

## 🎯 What Problem Does This Solve?

**Current pain points:**
- Monthly expenses like rent must be entered manually every month
- Utilities (electricity, water) require repetitive data entry
- Debts that recur predictably are tedious to track

**Solution:**
- **Auto-Generate Templates**: Create movements automatically on schedule (e.g., rent on 1st of month)
- **Pre-Fill Templates**: Appear in dropdown to speed up manual entry
- **Dual Purpose**: Same template can auto-generate SPLIT expense AND pre-fill DEBT_PAYMENT (payment)
- **Variable Amounts**: Templates for expenses that vary monthly (utilities) - pre-fill everything except amount

---

## 🏗️ Architecture

### Database Tables (4 new migrations)

1. **`movements.category_id`** (Migration 030)
   - Change from VARCHAR to UUID foreign key
   - Links movements to categories table
   - Requires data migration script

2. **`recurring_movement_templates`** (Migration 031)
   - Stores template configuration
   - Fields: name, type, category, amount, payer, participants, auto_generate, recurrence
   - Three configurations:
     - FIXED + auto_generate=true: Auto-creates on schedule
     - FIXED + auto_generate=false: Only dropdown pre-fill
     - VARIABLE + auto_generate=false: Dropdown, user enters amount

3. **`movements.generated_from_template_id`** (Migration 032)
   - Tracks which template generated a movement
   - Enables "edit all instances" functionality
   - NULL for manually created movements

4. **`recurring_movement_participants`** (Migration 033)
   - For SPLIT type templates
   - Stores participant percentages

### Backend Services

```
backend/internal/recurring_movements/
├── types.go          # Data models
├── repository.go     # Database access
├── service.go        # Business logic (CRUD templates)
├── generator.go      # Movement generation service
├── scheduler.go      # Background job (runs hourly)
└── handlers.go       # HTTP API endpoints
```

### Frontend Changes

1. **Movement form** (All movement types):
   - When category selected → show "¿Cuál gasto periódico?" dropdown
   - Dropdown shows ALL templates for that category
   - User can select template OR skip (optional field)
   - Pre-fill behavior:
     - Same type: Use template as-is
     - DEBT_PAYMENT from SPLIT: Invert payer ↔ counterparty
   - FIXED: pre-fills amount
   - VARIABLE: leaves amount empty

2. **Movement list**:
   - Auto-generated movements show 🔁 badge
   - Edit/Delete shows scope options (this, all, future)

---

## 📊 Key Concepts

### Template Configurations

| Config | auto_generate | amount_type | Behavior | Example |
|--------|--------------|-------------|----------|---------|
| **Auto-Fixed** | true | FIXED | Auto-creates + Dropdown | Rent: $3.2M on 1st |
| **Manual-Fixed** | false | FIXED | Dropdown only | Annual insurance |
| **Variable** | false | VARIABLE | Dropdown, no amount | Electricity bill |

### Role Inversion (SPLIT ↔ DEBT_PAYMENT)

**Template (SPLIT expense):**
- Payer: Arrendamientos la 99 (contact)
- Participant: Jose (100%)

**Auto-generates:** SPLIT movement (expense)
**Manual DEBT_PAYMENT:** Inverts to:
- Payer: Jose
- Counterparty: Arrendamientos la 99

### Recurrence Patterns

| Pattern | Configuration | Example |
|---------|--------------|---------|
| **MONTHLY** | Day of month (1-31) | Rent on 1st, Insurance on 15th |
| **YEARLY** | Month + Day | Annual subscription on Jan 1 |
| **ONE_TIME** | Single date | One-off scheduled expense |

### Edit/Delete Scopes

| Scope | Effect | Use Case |
|-------|--------|----------|
| **THIS** | Only this movement | Rent increased this month only |
| **FUTURE** | This + future movements | Rent increased permanently |
| **ALL** | Template + all movements | Fixed typo in description |

---

## 🔄 User Flows

### Flow 1: Rent - Auto-Generate Expense, Manual Payment

**1. Setup** (one-time, manual DB entry):
```sql
INSERT INTO recurring_movement_templates (
  name, type, amount_type, auto_generate,
  payer_contact_id, participants, day_of_month, ...
)
VALUES (
  'Arriendo', 'SPLIT', 'FIXED', true,
  'arrendamientos-la-99-uuid', '[{"user_id":"jose-uuid","percentage":1.0}]', 1, ...
);
```

**2. Automatic expense generation** (1st of each month):
- Scheduler creates SPLIT movement
- Payer: Arrendamientos la 99
- Participant: Jose (100%)
- Amount: $3.2M
- **Result**: Debt created (Jose owes landlord)

**3. Manual payment** (when Jose pays):
- User creates new movement
- Type: DEBT_PAYMENT
- Category: "Gastos fijos"
- Dropdown: Selects "Arriendo"
- Form pre-fills with **inverted roles**:
  - Payer: Jose (was participant)
  - Counterparty: Arrendamientos la 99 (was payer)
  - Amount: $3.2M
- User saves → debt payment recorded

---

### Flow 2: Utilities - Variable Amount, Manual Entry Only

**1. Setup** (one-time):
```sql
INSERT INTO recurring_movement_templates (
  name, type, amount_type, auto_generate,
  payer_contact_id, participants, ...
)
VALUES (
  'Servicios (Energía)', 'SPLIT', 'VARIABLE', false,
  'epm-uuid', '[{"user_id":"jose-uuid","percentage":1.0}]', ...
);
```

**2. Each month** (manual expense entry):
- User creates SPLIT movement
- Category: "Gastos fijos"
- Dropdown: "Servicios (Energía)"
- Form pre-fills:
  - Payer: EPM
  - Participant: Jose (100%)
  - **Amount: EMPTY** ← user enters
- User enters: $245.300
- Saves → expense recorded

**3. Payment** (when Jose pays):
- Same flow as rent payment
- Dropdown: "Servicios (Energía)"
- Inverted roles
- User enters same amount

---

## 🚀 Implementation Plan

### Phase 1: Database Migration (2 days)

- [ ] Migration 030: Add `category_id` to movements
- [ ] Script: Migrate existing category names to IDs
- [ ] Validate: All movements have valid category_id

### Phase 2: Backend Implementation (4 days)

- [ ] Create `internal/recurring_movements` package
- [ ] Repository, Service, Generator, Scheduler
- [ ] HTTP API endpoints (CRUD templates, scoped edit/delete)
- [ ] Unit tests

### Phase 3: Scheduler Service (1 day)

- [ ] Background job (runs hourly)
- [ ] Generate movements from FIXED templates
- [ ] Update template tracking (last_generated, next_scheduled)
- [ ] Logging and error handling

### Phase 4: Frontend Integration (3 days)

- [ ] Update movement form (template dropdown)
- [ ] Pre-fill logic (FIXED vs VARIABLE)
- [ ] Edit/Delete modals (scope selection)
- [ ] Auto-generated badge display
- [ ] API integration

### Phase 5: Testing & Validation (2 days)

- [ ] E2E tests (create, generate, edit, delete)
- [ ] Edge cases (Feb 29, day 31, timezones)
- [ ] Production validation with Jose & Caro's data
- [ ] Monitoring and logging

**Total: ~12 days**

---

## 📝 Initial Templates for Jose & Caro

These will be added manually to the database:

### Auto-Generate Templates (SPLIT with auto_generate=true)

**1. Arriendo (Rent)**
```json
{
  "name": "Arriendo",
  "type": "SPLIT",
  "category_id": "gastos-fijos-uuid",
  "amount_type": "FIXED",
  "amount": 3200000,
  "auto_generate": true,
  "payer_contact_id": "arrendamientos-la-99-uuid",
  "participants": [{"user_id": "jose-uuid", "percentage": 1.0}],
  "recurrence_pattern": "MONTHLY",
  "day_of_month": 1
}
```

### Manual Templates (auto_generate=false)

**2. Servicios (Utilities - Variable)**
```json
{
  "name": "Servicios (Energía)",
  "type": "SPLIT",
  "amount_type": "VARIABLE",
  "amount": null,
  "auto_generate": false,
  "payer_contact_id": "epm-uuid",
  "participants": [{"user_id": "jose-uuid", "percentage": 1.0}]
}
```

**3. Internet (Fixed, but manual)**
```json
{
  "name": "Internet",
  "type": "HOUSEHOLD",
  "amount_type": "FIXED",
  "amount": 85000,
  "auto_generate": false,
  "payer_user_id": "jose-uuid",
  "payment_method_id": "mastercard-uuid"
}
```

---

## 🔮 Future Enhancements (Not in Phase 8)

### Template Management UI
- Create/edit/delete templates from /hogar page
- View history of generated movements
- Pause/resume templates

### Notifications
- In-app: "Se generó Arriendo ($3.2M)"
- Email summaries (optional)

### Smart Templates
- Pre-fill with last month's amount
- Suggest average of last 3 months
- OCR: Scan bill and extract amount

### Shared Recurring Expenses
- SPLIT type templates with participants
- Cross-family synchronization

---

## 🎨 UI Mockups (Simplified)

### Movement Form with Template Selection

```
┌─────────────────────────────────────┐
│ Tipo: [Gasto compartido (SPLIT) ▼] │
│                                     │
│ Fecha: [1 Feb 2026]                │
│                                     │
│ Categoría: [Gastos fijos ▼]        │
│                                     │
│ ¿Cuál gasto periódico? (opcional)  │
│ [Seleccionar... ▼]                  │
│   - Ninguno (nuevo gasto)           │
│   - Arriendo                        │
│   - Servicios (Energía)             │
│   - Internet                        │
│                                     │
│ Valor: [      ]  ← Empty (variable) │
│ Pagador: [EPM]  ← Pre-filled       │
│ Participante: [Jose 100%] ← filled │
│                                     │
│ [Guardar]                           │
└─────────────────────────────────────┘
```

**If creating DEBT_PAYMENT and selecting "Arriendo":**
```
┌─────────────────────────────────────┐
│ Tipo: [Pago de deuda ▼]            │
│ Categoría: [Gastos fijos ▼]        │
│ Gasto periódico: [Arriendo ▼]      │
│                                     │
│ Valor: [3.200.000] ← Pre-filled    │
│ Pagador: [Jose] ← INVERTED         │
│ Contraparte: [Arrendamientos la 99]│
│              ← INVERTED             │
│ [Guardar]                           │
└─────────────────────────────────────┘
```

### Edit Scope Modal

```
┌─────────────────────────────────────┐
│  Editar gasto periódico             │
│                                     │
│  Este gasto fue generado            │
│  automáticamente. ¿Qué deseas       │
│  editar?                            │
│                                     │
│  [Solo esta vez (1 Feb 2026)]      │
│  [Esta y futuras ocurrencias]      │
│  [Todas las ocurrencias]           │
│                                     │
│  [Cancelar]                         │
└─────────────────────────────────────┘
```

---

## ✅ Success Criteria

- [ ] Templates can be created (manually via DB)
- [ ] Auto-generate templates create movements on schedule (SPLIT type)
- [ ] Manual templates appear in dropdown for ALL movement types
- [ ] Role inversion works (SPLIT template pre-fills DEBT_PAYMENT)
- [ ] VARIABLE templates leave amount empty
- [ ] Auto-generated movements show 🔁 badge
- [ ] Edit/Delete scopes work correctly (THIS, FUTURE, ALL)
- [ ] No duplicate generations (idempotent)
- [ ] Scheduler runs reliably every hour
- [ ] Jose & Caro's rent auto-generates on 1st of month
- [ ] Utilities template pre-fills form (except amount)
- [ ] Debt payment form pre-fills with inverted roles

---

## 🎯 Next Steps

1. Review design document (`08_RECURRING_MOVEMENTS_PHASE.md`)
2. Confirm approach and details
3. Start implementation with Phase 1 (database migration)
4. Add initial templates for Jose & Caro
5. Test with February 2026 rent generation

---

**Questions? See full design doc or ask!** 🚀
