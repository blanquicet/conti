# Budgets & Categories Management Phase

> **Current Status:** 📋 PLANNED
>
> This phase introduces:
> 1. Categories management (move from hardcoded to database, per-household customization)
> 2. Monthly budgets per category
> 3. Budget progress indicators in the Gastos view
> 4. Category and budget management UI in the Home page

**Architecture:**

- Categories: PostgreSQL (per household, customizable)
- Monthly budgets: PostgreSQL (per household, per category, per month)
- Budget indicators: Calculated in real-time from movements + budget data

**Relationship to other phases:**

- Builds on top of Phase 5 (movements system) 
- Categories were hardcoded in Phase 5, now become database entities
- See `FUTURE_VISION.md` section 4.3 for product vision on budgets

---

## 🎯 Goals

1. **Move categories from hardcoded to database**
   - Each household can define their own categories
   - Categories can be grouped (Casa, Jose, Caro, Carro, etc.)
   - Default categories created automatically on household creation
   - Categories can be edited, reordered, added, deleted (with validation)

2. **Add monthly budget per category**
   - Budget amount is defined per category per month
   - When no budget is set for a month, use previous month's budget (or null)
   - Budget can be edited from the Home page
   - Budget is optional (categories without budget are allowed)

3. **Budget progress indicators in Gastos view**
   - Show for each category: spent / budget
   - Visual indicator: under budget (green), on track (yellow), exceeded (red)
   - Percentage indicator
   - Only show if budget is defined for that category

4. **Category management UI in Home page**
   - View all categories grouped
   - Add new category (with name, group, optional icon/color)
   - Edit category name, group, icon, color
   - Reorder categories within group
   - Delete category (with validation - cannot delete if used in movements)
   - Set monthly budget per category

---

## 📊 Data Model

### New Tables

#### `categories`

Represents expense categories per household

```sql
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  
  -- Category info
  name VARCHAR(100) NOT NULL,
  category_group VARCHAR(100), -- Optional grouping (Casa, Jose, Caro, Carro, etc.)
  
  -- UI metadata
  icon VARCHAR(10), -- Emoji or icon identifier
  color VARCHAR(20), -- Hex color or color name
  display_order INT NOT NULL DEFAULT 0,
  
  -- Lifecycle
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Constraints
  UNIQUE(household_id, name),
  CHECK (name != '')
);

CREATE INDEX idx_categories_household ON categories(household_id);
CREATE INDEX idx_categories_household_active ON categories(household_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_categories_household_group ON categories(household_id, category_group);
CREATE INDEX idx_categories_display_order ON categories(household_id, display_order);
```

**Business rules:**

- **Household-specific**: Each household has its own categories
- **Unique names**: Category names must be unique within a household
- **Grouping**: Categories can be grouped for UI organization (Casa, Jose, Caro, etc.)
- **Display order**: Controls order of display in dropdowns and lists
- **Active/Inactive**: Inactive categories don't appear in new movement dropdowns but still visible in management UI
- **Cannot delete if used**: Categories used in movements cannot be deleted (only deactivated)
- **Default categories**: Created automatically when household is created

**Default categories to create on household creation:**

```
Group: Casa
- Casa - Gastos fijos
- Casa - Cositas para casa  
- Casa - Provisionar mes entrante
- Casa - Imprevistos
- Kellys
- Mercado

Group: Jose
- Jose - Vida cotidiana
- Jose - Gastos fijos
- Jose - Imprevistos

Group: Caro
- Caro - Vida cotidiana
- Caro - Gastos fijos
- Caro - Imprevistos

Group: Carro
- Uber/Gasolina/Peajes/Parqueaderos
- Pago de SOAT/impuestos/mantenimiento
- Carro - Seguro
- Carro - Imprevistos

Group: Ahorros
- Ahorros para SOAT/impuestos/mantenimiento
- Ahorros para cosas de la casa
- Ahorros para vacaciones
- Ahorros para regalos

Group: Inversiones
- Inversiones Caro
- Inversiones Jose
- Inversiones Juntos

Group: Diversión
- Vacaciones
- Salidas juntos

Ungrouped:
- Regalos
- Gastos médicos
- Préstamo
```

#### `monthly_budgets`

Represents monthly budget amounts per category

```sql
CREATE TABLE monthly_budgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  
  -- Month and amount
  month DATE NOT NULL, -- Stored as first day of month (YYYY-MM-01)
  amount DECIMAL(15, 2) NOT NULL CHECK (amount >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'COP',
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Constraints
  UNIQUE(household_id, category_id, month)
);

CREATE INDEX idx_monthly_budgets_household ON monthly_budgets(household_id);
CREATE INDEX idx_monthly_budgets_category ON monthly_budgets(category_id);
CREATE INDEX idx_monthly_budgets_household_month ON monthly_budgets(household_id, month);
CREATE INDEX idx_monthly_budgets_category_month ON monthly_budgets(category_id, month);
```

**Business rules:**

- **Monthly granularity**: One budget amount per category per month
- **Month stored as DATE**: Stored as first day of month (e.g., '2025-01-01' for January 2025)
- **Sparse data**: Only months with explicit budget are stored
- **Budget lookup logic**:
  - If budget exists for current month → use it
  - If no budget for current month → use most recent previous month's budget
  - If no budget at all → category has no budget (don't show indicator)
- **Budget can be 0**: Explicit 0 budget means "should not spend in this category this month"
- **Cannot delete category if budgets exist**: When deactivating category, budgets remain but are not shown

### Modified Tables

#### `movements` - Add category_id foreign key

```sql
-- Migration to add category_id and migrate data
ALTER TABLE movements 
ADD COLUMN category_id UUID REFERENCES categories(id) ON DELETE RESTRICT;

-- Create index
CREATE INDEX idx_movements_category ON movements(category_id);

-- Migration logic (run after categories table is populated):
-- 1. For each household, create categories from distinct category values in movements
-- 2. Update movements.category_id based on movements.category name match
-- 3. After migration, category column can be kept for backwards compatibility or dropped
```

**Migration strategy:**

1. Create `categories` table
2. Create `monthly_budgets` table
3. Populate `categories` with default categories for existing households
4. Add `category_id` column to `movements` (nullable initially)
5. Migrate existing movements: match `movements.category` string to `categories.name` and set `category_id`
6. Once migration verified, can make `category_id` NOT NULL for HOUSEHOLD/DEBT_PAYMENT movements
7. Keep `category` column for backwards compatibility (or drop after full migration)

---

## 🔌 Backend API

### Categories Endpoints

#### List categories
```
GET /api/categories
Authorization: Bearer <token>

Query params:
- include_inactive (optional): boolean, default false

Response 200:
{
  "categories": [
    {
      "id": "uuid",
      "household_id": "uuid",
      "name": "Casa - Gastos fijos",
      "category_group": "Casa",
      "icon": "🏠",
      "color": "#4CAF50",
      "display_order": 0,
      "is_active": true,
      "created_at": "timestamp",
      "updated_at": "timestamp"
    },
    ...
  ],
  "grouped": {
    "Casa": [...],
    "Jose": [...],
    "Caro": [...],
    "Carro": [...],
    "Ahorros": [...],
    "Inversiones": [...],
    "Diversión": [...],
    "": [...] // Ungrouped
  }
}

Errors:
404 - User has no household
```

**Business logic:**
- Return categories for user's household
- By default, only active categories (unless include_inactive=true)
- Return both flat list and grouped structure
- Order by display_order within each group

#### Create category
```
POST /api/categories
Authorization: Bearer <token>

Body:
{
  "name": "Nueva categoría",
  "category_group": "Casa",
  "icon": "🏠",
  "color": "#4CAF50"
}

Response 201:
{
  "id": "uuid",
  "household_id": "uuid",
  "name": "Nueva categoría",
  "category_group": "Casa",
  "icon": "🏠",
  "color": "#4CAF50",
  "display_order": 100,
  "is_active": true,
  "created_at": "timestamp",
  "updated_at": "timestamp"
}

Errors:
400 - Invalid input
409 - Category with that name already exists
404 - User has no household
403 - User is not household member
```

**Business logic:**
- Only household members can create categories
- Name must be unique within household
- display_order is auto-assigned (max + 1 within group)
- All fields except name are optional

#### Update category

```
PATCH /api/categories/:id
Authorization: Bearer <token>
Content-Type: application/json
```

**Path Parameters:**
- `id` (string, required): UUID of the category to update

**Request Body (all fields optional):**
```json
{
  "name": "Casa - Servicios públicos",
  "category_group": "Casa",
  "icon": "💡",
  "color": "#FFC107",
  "display_order": 3,
  "is_active": true
}
```

**Field Descriptions:**
- `name` (string, optional): New name for the category
  - Min length: 1 character
  - Max length: 100 characters
  - Must be unique within the household
  - Cannot be empty string
  
- `category_group` (string, optional): Group to which category belongs
  - Can be null (ungrouped category)
  - Examples: "Casa", "Jose", "Caro", "Carro", "Ahorros", etc.
  
- `icon` (string, optional): Emoji or icon identifier
  - Max length: 10 characters
  - Can be null
  
- `color` (string, optional): Color in hex format or color name
  - Max length: 20 characters
  - Examples: "#4CAF50", "green"
  - Can be null
  
- `display_order` (integer, optional): Order for display in UI
  - Used to control sort order within group
  - Lower numbers appear first
  
- `is_active` (boolean, optional): Whether category is active
  - `true`: Category appears in movement dropdowns
  - `false`: Category hidden from dropdowns but still visible in management UI

**Response 200 (Success):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "household_id": "660e8400-e29b-41d4-a716-446655440000",
  "name": "Casa - Servicios públicos",
  "category_group": "Casa",
  "icon": "💡",
  "color": "#FFC107",
  "display_order": 3,
  "is_active": true,
  "created_at": "2025-01-10T15:30:00Z",
  "updated_at": "2025-01-10T20:15:30Z"
}
```

**Errors:**
- `400` - Invalid input (empty name, name too long, etc.)
- `401` - Unauthorized (no valid session)
- `403` - Forbidden (user is not household member)
- `404` - Category not found or not in user's household
- `409` - Conflict (name already exists in household)
- `500` - Internal server error

**Business logic:**

1. **Authorization Checks:**
   - Extract user from session cookie
   - Verify user is authenticated
   - Find category by ID and verify it exists
   - Get category's household_id
   - Verify user is member of that household
   - If checks fail → return 403 Forbidden or 404 Not Found

2. **Name Uniqueness Validation:**
   ```sql
   -- Check if another category in same household has this name
   SELECT COUNT(*) FROM categories 
   WHERE household_id = ? 
     AND name = ? 
     AND id != ? -- Exclude current category
     AND is_active = true;
   
   -- If count > 0 → return 409 Conflict
   ```
   - Name uniqueness is case-sensitive
   - Only applies within the same household

3. **Partial Update Logic:**
   - Only update fields that are provided in request body
   - Always update `updated_at` timestamp

4. **Side Effects of Renaming:**
   - ✅ **Movements are NOT affected** - They reference `category_id` (UUID), not name
   - ✅ **Budgets are NOT affected** - They reference `category_id`, not name
   - ✅ **UI updates automatically** - Frontend fetches categories by ID
   - **No data migration needed** - All references are by UUID

5. **Display Order Handling:**
   - Simple update approach (gaps in numbering are acceptable)
   - UI queries: `ORDER BY display_order ASC`
   - May result in gaps (e.g., 1, 2, 5, 10) - this is OK

**Example Scenarios:**

Scenario 1 - Simple Name Change:
```bash
curl -X PATCH https://api.gastos.com/api/categories/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name": "Casa - Servicios (Luz, Agua, Gas)"}'
```

Scenario 2 - Name Conflict (409):
```bash
curl -X PATCH .../api/categories/:id \
  -d '{"name": "Mercado"}'
# Returns 409 if "Mercado" already exists
```

Scenario 3 - Move to Different Group:
```bash
curl -X PATCH .../api/categories/:id \
  -d '{"name": "Servicios del hogar", "category_group": "Casa", "display_order": 10}'
```

Scenario 4 - Deactivate Category:
```bash
curl -X PATCH .../api/categories/:id \
  -d '{"is_active": false}'
```

**Implementation Signatures:**

Handler:
```go
func (h *CategoryHandler) UpdateCategory(w http.ResponseWriter, r *http.Request) {
    // 1. Extract category ID from URL path
    // 2. Parse JSON body into UpdateCategoryInput
    // 3. Get user from session
    // 4. Call service.UpdateCategory(ctx, userID, categoryID, input)
    // 5. Return updated category as JSON
}
```

Service:
```go
func (s *CategoryService) UpdateCategory(
    ctx context.Context, 
    userID string, 
    categoryID string, 
    input *UpdateCategoryInput,
) (*Category, error) {
    // 1. Verify user has access to category (same household)
    // 2. Validate input (name uniqueness, field constraints)
    // 3. Update category in repository
    // 4. Return updated category
}
```

Repository:
```go
func (r *CategoryRepository) Update(
    ctx context.Context,
    categoryID string,
    input *UpdateCategoryInput,
) (*Category, error) {
    // 1. Build UPDATE query with only provided fields
    // 2. Execute query in transaction
    // 3. Return updated category
}
```

**Frontend Example:**
```javascript
async function updateCategory(categoryId, updates) {
  const response = await fetch(`/api/categories/${categoryId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify(updates),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to update category');
  }

  return await response.json();
}

// Usage: Rename category
async function handleCategoryRename(categoryId, currentName) {
  const newName = prompt('Nuevo nombre:', currentName);
  if (!newName || newName === currentName) return;

  try {
    const updated = await updateCategory(categoryId, { name: newName });
    document.querySelector(`[data-category-id="${categoryId}"] .category-name`)
      .textContent = updated.name;
    showToast('✅ Categoría actualizada', 'success');
  } catch (error) {
    showToast('❌ ' + error.message, 'error');
  }
}
```

**Database Transaction:**
```sql
BEGIN;

-- Check name uniqueness (if name is being updated)
SELECT COUNT(*) FROM categories 
WHERE household_id = $1 AND name = $2 AND id != $3;

-- If count > 0, ROLLBACK and return 409

-- Update category
UPDATE categories 
SET 
  name = COALESCE($1, name),
  category_group = COALESCE($2, category_group),
  icon = COALESCE($3, icon),
  color = COALESCE($4, color),
  display_order = COALESCE($5, display_order),
  is_active = COALESCE($6, is_active),
  updated_at = NOW()
WHERE id = $7
RETURNING *;

COMMIT;
```

**Testing Checklist:**
- [ ] Update category name successfully
- [ ] Reject empty name
- [ ] Reject name > 100 characters
- [ ] Reject duplicate name in same household
- [ ] Allow duplicate name in different household
- [ ] Update only name (other fields unchanged)
- [ ] Update multiple fields at once
- [ ] Move category to different group
- [ ] Deactivate/reactivate category
- [ ] Reject update if user not in household
- [ ] Reject update if category doesn't exist
- [ ] Verify movements still work after rename
- [ ] Verify budgets still work after rename
- [ ] Test concurrent updates (race condition)

#### Delete category
```
DELETE /api/categories/:id
Authorization: Bearer <token>

Response 204: (no content)

Errors:
404 - Category not found or not in user's household
403 - User is not household member
409 - Category is used in movements (cannot delete)
```

**Business logic:**
- Only household members can delete categories
- Cannot delete if category is used in any movement (check movements.category_id)
- If used in movements, suggest deactivating instead (is_active = false)

#### Reorder categories
```
POST /api/categories/reorder
Authorization: Bearer <token>

Body:
{
  "category_ids": ["uuid1", "uuid2", "uuid3", ...] // Ordered list
}

Response 200:
{
  "message": "Categories reordered successfully"
}

Errors:
400 - Invalid input (not all category IDs provided)
404 - Category not found or not in user's household
403 - User is not household member
```

**Business logic:**
- Reorder all categories within household
- Update display_order for each category based on position in array
- Validates all category IDs belong to user's household

### Monthly Budgets Endpoints

#### Get budget for month
```
GET /api/budgets/:month
Authorization: Bearer <token>

Path params:
- month: YYYY-MM format (e.g., "2025-01")

Response 200:
{
  "month": "2025-01",
  "budgets": [
    {
      "id": "uuid",
      "category_id": "uuid",
      "category_name": "Casa - Gastos fijos",
      "category_group": "Casa",
      "amount": 500000,
      "currency": "COP",
      "spent": 350000, // Calculated from movements
      "percentage": 70.0, // (spent / amount) * 100
      "status": "on_track", // "under_budget" | "on_track" | "exceeded"
      "created_at": "timestamp",
      "updated_at": "timestamp"
    },
    ...
  ],
  "totals": {
    "total_budget": 5000000,
    "total_spent": 3500000,
    "percentage": 70.0
  }
}

Errors:
400 - Invalid month format
404 - User has no household
```

**Business logic:**
- Return budget for each category in the specified month
- If no explicit budget for month, look for most recent previous month's budget
- Calculate spent from movements for that month
- Calculate percentage and status
- Status logic:
  - under_budget: percentage < 80%
  - on_track: 80% <= percentage < 100%
  - exceeded: percentage >= 100%

#### Set/update budget for category and month
```
PUT /api/budgets
Authorization: Bearer <token>

Body:
{
  "category_id": "uuid",
  "month": "2025-01",
  "amount": 500000
}

Response 200:
{
  "id": "uuid",
  "household_id": "uuid",
  "category_id": "uuid",
  "month": "2025-01-01",
  "amount": 500000,
  "currency": "COP",
  "created_at": "timestamp",
  "updated_at": "timestamp"
}

Errors:
400 - Invalid input
404 - Category not found or user has no household
403 - User is not household member
```

**Business logic:**
- Upsert: Create if doesn't exist, update if exists
- Only household members can set budgets
- Category must belong to user's household
- Amount must be >= 0

#### Delete budget
```
DELETE /api/budgets/:id
Authorization: Bearer <token>

Response 204: (no content)

Errors:
404 - Budget not found or not in user's household
403 - User is not household member
```

**Business logic:**
- Only household members can delete budgets
- Deletes budget for specific category and month

#### Copy budgets to next month
```
POST /api/budgets/copy
Authorization: Bearer <token>

Body:
{
  "from_month": "2025-01",
  "to_month": "2025-02"
}

Response 200:
{
  "message": "Budgets copied successfully",
  "count": 15 // Number of budgets copied
}

Errors:
400 - Invalid month format or to_month <= from_month
404 - User has no household
403 - User is not household member
409 - Budgets already exist for to_month
```

**Business logic:**
- Copy all budgets from one month to another
- Useful for repeating monthly budgets
- Cannot overwrite existing budgets (return 409)
- Could add option to overwrite in future

---

## 🎨 Frontend UI

### 1. Home Page - Budget Management Section

**New section in home.js after Ingresos/Gastos:**

```
┌─────────────────────────────────────────────────────────┐
│ 💰 Presupuesto del Mes - Enero 2025                    │
│                                           [Copiar Mes] ▼│
├─────────────────────────────────────────────────────────┤
│                                                          │
│ Casa                                      $2,500,000 / 3,000,000 (83%) 🟡 │
│   Casa - Gastos fijos        $1,200,000 / 1,500,000 [Editar]            │
│   Kellys                       $300,000 /   400,000                      │
│   Mercado                    $1,000,000 / 1,100,000                      │
│                                                          │
│ Jose                                      $800,000 / 1,000,000 (80%) 🟡  │
│   Jose - Vida cotidiana        $600,000 /   700,000 [Editar]            │
│   Jose - Gastos fijos          $200,000 /   300,000                      │
│                                                          │
│ [+ Agregar Categoría]                                    │
└─────────────────────────────────────────────────────────┘
```

**Features:**

- Month selector (dropdown or prev/next arrows)
- For each category group:
  - Show total spent / total budget with percentage and color indicator
  - Expand/collapse to show individual categories
  - Each category shows: spent / budget with [Editar] button
  - Click [Editar] opens inline input to change budget amount
- "Copiar Mes" dropdown: copy all budgets from previous month
- "+ Agregar Categoría" button opens modal to create new category

**Color indicators:**
- 🟢 Green (< 80%): Under budget
- 🟡 Yellow (80-99%): On track
- 🔴 Red (≥ 100%): Exceeded

### 2. Budget Edit Modal/Inline Edit

**Option A: Inline edit (simpler)**
```
Casa - Gastos fijos    $1,200,000 / [  1,500,000  ] 💾 ❌
```

**Option B: Modal (more control)**
```
┌─────────────────────────────────────────┐
│ Editar Presupuesto                      │
├─────────────────────────────────────────┤
│ Categoría: Casa - Gastos fijos          │
│ Mes: Enero 2025                         │
│                                          │
│ Presupuesto: [        1,500,000       ] │
│                                          │
│            [Cancelar]  [Guardar]        │
└─────────────────────────────────────────┘
```

### 3. Category Management Modal

```
┌──────────────────────────────────────────────────────┐
│ Gestionar Categorías                         [X]     │
├──────────────────────────────────────────────────────┤
│                                                       │
│ Casa                                   [+ Agregar]   │
│   ☰ Casa - Gastos fijos         🏠 #4CAF50 [✏️] [🗑️] │
│   ☰ Kellys                      👩 #2196F3 [✏️] [🗑️] │
│   ☰ Mercado                     🛒 #FF9800 [✏️] [🗑️] │
│                                                       │
│ Jose                                   [+ Agregar]   │
│   ☰ Jose - Vida cotidiana       👨 #9C27B0 [✏️] [🗑️] │
│   ☰ Jose - Gastos fijos         💼 #3F51B5 [✏️] [🗑️] │
│                                                       │
│ [+ Nuevo Grupo]                                      │
│                                                       │
│                            [Cerrar]                   │
└──────────────────────────────────────────────────────┘
```

**Features:**

- Drag and drop to reorder (☰ icon)
- Edit icon/color for each category
- Delete category (with confirmation)
- Add new category to group
- Create new group

### 4. Gastos Tab - Budget Indicators

**Modify existing Gastos tab to show budget indicators:**

```
┌─────────────────────────────────────────────────────────┐
│ Gastos - Enero 2025                                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│ Casa                              $2,500,000 / $3,000,000│
│ ████████████████░░░░ 83% 🟡                             │
│   21 Ene - Kellys                          $300,000     │
│   18 Ene - Mercado Éxito                   $450,000     │
│   15 Ene - Casa - Gastos fijos (Netflix)   $50,000      │
│   ...                                                    │
│                                                          │
│ Jose                                $800,000 / $1,000,000│
│ ██████████████████░░ 80% 🟡                             │
│   22 Ene - Jose - Vida cotidiana (Almuerzo) $35,000    │
│   ...                                                    │
│                                                          │
│ Carro (sin presupuesto)                      $450,000   │
│   20 Ene - Uber                                $85,000  │
│   ...                                                    │
└─────────────────────────────────────────────────────────┘
```

**Features:**

- For each category group with budget:
  - Show progress bar (spent / budget)
  - Show percentage and color indicator
- For categories without budget:
  - Show "(sin presupuesto)" and total spent only
- Progress bar visual:
  - Green when under budget
  - Yellow when on track
  - Red when exceeded

---

## 📋 Implementation Steps

### Phase 6A: Database & Backend (Estimated: 16 hours)

**Step 1: Database migrations** (3 hours)
- [ ] Create migration `018_create_categories.up.sql`
- [ ] Create migration `019_create_monthly_budgets.up.sql`
- [ ] Create migration `020_add_category_id_to_movements.up.sql`
- [ ] Create migration `021_migrate_movement_categories.up.sql` (data migration)
- [ ] Test migrations up and down

**Step 2: Backend models and types** (2 hours)
- [ ] Create `internal/categories/types.go` (Category, CreateCategoryInput, etc.)
- [ ] Create `internal/budgets/types.go` (MonthlyBudget, BudgetWithSpent, etc.)
- [ ] Add validation logic

**Step 3: Repository layer** (3 hours)
- [ ] Implement `internal/categories/repository.go` (CRUD operations)
- [ ] Implement `internal/budgets/repository.go` (CRUD operations)
- [ ] Add method to calculate spent for month/category
- [ ] Write repository tests

**Step 4: Service layer** (4 hours)
- [ ] Implement `internal/categories/service.go` (business logic, authorization)
- [ ] Implement `internal/budgets/service.go` (business logic, budget lookup)
- [ ] Add logic to create default categories on household creation
- [ ] Write service tests (30+ test cases)

**Step 5: API handlers** (3 hours)
- [ ] Implement `internal/categories/handler.go` (REST endpoints)
- [ ] Implement `internal/budgets/handler.go` (REST endpoints)
- [ ] Register routes in `cmd/api/main.go`
- [ ] Update `movements` handler to use category_id

**Step 6: Integration testing** (1 hour)
- [ ] Write API integration tests
- [ ] Test budget calculation logic
- [ ] Test category deletion validation

### Phase 6B: Frontend (Estimated: 12 hours)

**Step 1: Budget section in home page** (4 hours)
- [ ] Add budget section HTML structure
- [ ] Fetch budget data from API
- [ ] Display grouped categories with spent/budget
- [ ] Add month selector
- [ ] Add expand/collapse for groups

**Step 2: Budget editing** (3 hours)
- [ ] Add inline budget edit UI
- [ ] Implement save budget API call
- [ ] Add copy budget from previous month

**Step 3: Category management** (4 hours)
- [ ] Create category management modal
- [ ] Add create/edit/delete category UI
- [ ] Implement drag-and-drop reordering
- [ ] Add icon/color picker

**Step 4: Gastos tab indicators** (1 hour)
- [ ] Modify Gastos tab to show budget indicators
- [ ] Add progress bars
- [ ] Add color coding

### Phase 6C: Testing & Polish (Estimated: 4 hours)

**Step 1: E2E testing** (2 hours)
- [ ] Test full budget workflow
- [ ] Test category management
- [ ] Test budget indicators in Gastos tab

**Step 2: Documentation** (1 hour)
- [ ] Update API documentation
- [ ] Add user guide for budgets

**Step 3: Deployment** (1 hour)
- [ ] Run migrations in production
- [ ] Deploy backend
- [ ] Deploy frontend
- [ ] Smoke tests

---

## 🚦 Definition of Done

### Backend Complete When:
- [x] All migrations created and tested
- [x] Categories and budgets models implemented
- [x] Repository layer with full CRUD
- [x] Service layer with business logic and authorization
- [x] API endpoints working (categories, budgets)
- [x] Default categories created on household creation
- [x] Category deletion validation (cannot delete if used)
- [x] Budget calculation logic working
- [x] All unit tests passing (30+ tests)
- [x] All integration tests passing

### Frontend Complete When:
- [x] Budget section visible in home page
- [x] Month selector working
- [x] Spent/budget display with color indicators
- [x] Inline budget editing working
- [x] Copy budget from previous month working
- [x] Category management modal working
- [x] Create/edit/delete categories working
- [x] Reorder categories working
- [x] Budget indicators in Gastos tab
- [x] Progress bars with correct colors
- [x] Responsive design

### Phase 6 Complete When:
- [x] All backend and frontend features working
- [x] E2E tests passing
- [x] Documentation updated
- [x] Deployed to production
- [x] No breaking changes to existing features
- [x] Existing movements still display correctly

---

## 🗓️ Timeline Estimate

| Task | Effort | Dependencies |
|------|--------|--------------|
| Database migrations | 3 hours | None |
| Backend models | 2 hours | Migrations |
| Repository layer | 3 hours | Models |
| Service layer | 4 hours | Repository |
| API handlers | 3 hours | Service |
| Integration tests | 1 hour | All backend |
| Budget section UI | 4 hours | API ready |
| Budget editing UI | 3 hours | API ready |
| Category mgmt UI | 4 hours | API ready |
| Gastos indicators | 1 hour | API ready |
| E2E testing | 2 hours | All complete |
| Documentation | 1 hour | All complete |
| Deployment | 1 hour | All complete |
| **Total** | **~32 hours** | **~4-5 days** |

---

## 📝 Notes

### Migration Strategy for Existing Data

For existing households with movements using hardcoded categories:

1. Create categories table
2. For each existing household:
   - Insert default categories
3. Add category_id column to movements (nullable)
4. For each movement with category string:
   - Find matching category by name in same household
   - Set category_id
5. Verify all movements have category_id (where required)
6. Can keep category string for backwards compatibility

### Future Enhancements (Phase 7+)

- [ ] Budget templates (save and reuse budget configurations)
- [ ] Budget alerts/notifications when approaching limit
- [ ] Category icons library (predefined icons)
- [ ] Category colors from palette
- [ ] Budget history/trends (compare months)
- [ ] Budget vs actual reports
- [ ] Shared categories across households (optional)
- [ ] Category merge/split functionality

---

**Last Updated:** 2026-01-10  
**Status:** 📋 Planning Phase  
**Next Action:** Review and approve design, then start implementation
