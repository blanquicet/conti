# Plan: Budget Inheritance + Unified Scope System

## Problem

Two related systems need scope editing, but neither has it fully implemented:

1. **Budgets**: Currently month-specific records with manual "Copy from previous month".
   Users expect budgets to persist automatically across months.

2. **Recurring Movement Templates**: The design doc defines THIS/FUTURE/ALL scope for
   editing templates, the frontend has a scope modal for *movements* in the Gastos tab,
   but the backend has zero scope implementation.

## Key UX Decision

**Scope belongs in the Presupuesto tab, NOT in the Gastos tab.**

| Tab | What you edit | Scope? |
|-----|--------------|--------|
| **Gastos** | A specific movement (what already happened) | ❌ No — always that one movement |
| **Presupuesto** | A template/recurring expense (the definition) | ✅ THIS/FUTURE/ALL |
| **Presupuesto** | Budget amount for a category | ✅ THIS/FUTURE/ALL |

This means:
- REMOVE the scope modal from Gastos tab (simplify)
- ADD scope to Presupuesto tab for both template editing and budget editing
- `PATCH/DELETE /movements/:id` stays as-is (no scope needed)
- `PATCH/DELETE /recurring-movements/:id` gets scope support
- `PUT /budgets` gets scope support

## Proposed Approach

### A. Budget Inheritance (no schema change)

Keep `monthly_budgets` table. Implement the lookup logic from design doc (line 185-188)
that was never built:

> "If no budget for current month → use most recent previous month's budget"

Budget set in January automatically applies to Feb, Mar, etc.

### B. Budget Scope (THIS/FUTURE/ALL)

When user edits a budget amount, show scope modal after clicking save:

| Scope | Backend behavior |
|-------|-----------------|
| **THIS** | Upsert record for this specific month only |
| **FUTURE** | Upsert this month + delete all records for months > this month |
| **ALL** | Update ALL existing records to this amount |

### C. Template Scope (THIS/FUTURE/ALL)

When user edits/deletes a template from Presupuesto tab:

| Scope | Edit behavior | Delete behavior |
|-------|--------------|-----------------|
| **THIS** | Update only the template definition | Deactivate template (stop auto-generating) |
| **FUTURE** | Update template + update future auto-generated movements | Deactivate template + delete future auto-generated movements |
| **ALL** | Update template + update ALL auto-generated movements | Deactivate template + delete ALL auto-generated movements |

### D. Simplify Gastos Tab

Remove scope modal from Gastos tab. Edit/delete always affects only that specific
movement, regardless of whether it was auto-generated.

---

## Tasks

### Phase 1: Budget Inheritance (Backend)

**1.1 — Implement budget fallback in repository**
- File: `backend/internal/budgets/repository.go` → `GetByMonth()`
- If no budget for exact month, query most recent previous month
- Existing unique constraint `(household_id, category_id, month)` stays
- No DB migration needed

**1.2 — Add scope parameter to budget Set**
- File: `backend/internal/budgets/types.go`
  - Add scope constants: THIS, FUTURE, ALL
  - Add Scope field to SetBudgetInput (default: FUTURE)
- File: `backend/internal/budgets/service.go` → `Set()`
  - THIS: simple upsert (current behavior)
  - FUTURE: upsert this month + delete records for months > this month
  - ALL: update ALL existing records to this amount
- File: `backend/internal/budgets/repository.go`
  - Add `DeleteFutureRecords(ctx, householdID, categoryID, afterMonth)`
  - Add `UpdateAllRecords(ctx, householdID, categoryID, amount)`
- File: `backend/internal/budgets/handler.go`
  - Accept `scope` in request body (default: "FUTURE")

### Phase 2: Template Scope (Backend)

**2.1 — Add scope to template Update endpoint**
- File: `backend/internal/recurringmovements/handler.go`
  - Accept `scope` query param on `PATCH /recurring-movements/:id`
- File: `backend/internal/recurringmovements/service.go` → `Update()`
  - THIS: update only the template definition (current behavior)
  - FUTURE: update template + update movements with
    `generated_from_template_id = template_id AND movement_date >= now()`
  - ALL: update template + update ALL movements with same template_id
- Needs access to movements repository for FUTURE/ALL

**2.2 — Add scope to template Delete endpoint**
- File: `backend/internal/recurringmovements/handler.go`
  - Accept `scope` query param on `DELETE /recurring-movements/:id`
- File: `backend/internal/recurringmovements/service.go` → `Delete()`
  - THIS: deactivate template only (set is_active=false)
  - FUTURE: deactivate template + delete future auto-generated movements
  - ALL: deactivate template + delete ALL auto-generated movements
- Needs access to movements repository for FUTURE/ALL

### Phase 3: Frontend — Presupuesto Tab

**3.1 — Create reusable scope modal component**
- Extract/refactor showScopeModal() into generic function
- Accepts: title, description, scope option labels
- Returns: Promise<string> with selected scope
- Context-specific labels:
  - Budget: "Solo este mes" / "De este mes en adelante" / "Todos los meses"
  - Template: "Solo el template" / "Template y futuros movimientos" / "Template y todos"

**3.2 — Budget edit with scope modal**
- When user edits budget total → save → show scope modal
- Send scope to backend: `PUT /api/budgets { ..., scope: "FUTURE" }`
- Update success message to reflect scope choice

**3.3 — Template edit/delete with scope modal**
- When user edits a template → save → show scope modal
- When user deletes a template → show scope modal before confirming
- Send scope to backend endpoints

**3.4 — Remove "Copiar del mes anterior" button**
- Remove button and `copyBudgetsFromPrevMonth()` function

**3.5 — Remove "Gestionar categorías" button**
- Remove the button (currently shows TODO alert)

### Phase 4: Frontend — Simplify Gastos Tab

**4.1 — Remove scope modal from Gastos tab**
- Remove showScopeModal() calls from movement edit/delete handlers
- Remove the `hasTemplate` check that triggers scope modal
- Edit/delete always operates on that single movement
- Keep the 🔁 badge on auto-generated movements (informational only)

### Phase 5: Integration Testing

**5.1 — Budget inheritance tests**
- Set budget Jan → query Feb → returns Jan's amount
- Set override for Mar → query Mar → returns override
- Query Apr → returns Mar's value (most recent)

**5.2 — Budget scope tests**
- scope=THIS for Mar → Apr does NOT have Mar's value
- scope=FUTURE for Mar → future records deleted, Apr inherits Mar
- scope=ALL → all existing records updated

**5.3 — Template scope tests**
- Edit template scope=THIS → only template changes, movements untouched
- Edit template scope=FUTURE → template + future movements updated
- Delete template scope=ALL → template deactivated + all movements deleted

---

## Dependencies

```
1.1 (budget fallback) → 3.4 (remove copy button)
1.2 (budget scope backend) → 3.2 (budget scope frontend)
2.1 + 2.2 (template scope backend) → 3.3 (template scope frontend)
3.1 (scope modal component) → 3.2 + 3.3 (uses it)
4.1 (simplify gastos) has no dependencies
```

## Notes

- **No DB migration needed** — inheritance is query-level, scope uses existing tables
- `updateBudgetFromTemplates()` doesn't need to change — upserts current month,
  inheritance handles future months
- `TemplatesSumCalculator` validation (budget >= templates sum) stays as-is
- The `CopyBudgets` endpoint can be deprecated but doesn't need removal immediately
