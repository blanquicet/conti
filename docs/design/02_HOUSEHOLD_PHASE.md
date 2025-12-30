# 02_HOUSEHOLD_PHASE.md — Household & Contacts Management

> **Current Status:** 📋 PLANNED
>
> This phase introduces the concepts of Household (Hogar) and Contacts to enable
> shared expense tracking and multi-person financial management.

**Architecture:**

- Authentication: PostgreSQL (see `01_AUTH_PHASE.md`)
- Movement storage: n8n → Google Sheets (unchanged from `00_N8N_PHASE.md`)
- **NEW:** Household & Contact management → PostgreSQL

**Relationship to other phases:**

- Builds on top of `01_AUTH_PHASE.md` (authentication required)
- Prepares foundation for Phase 3 (shared movements and events)
- See `FUTURE_VISION.md` sections 5, 4.7, 10 for full context

---

## 🎯 Goals

1. **Allow users to create and manage their household**
   - Optional during registration
   - Mandatory before creating shared movements (Phase 3)
   - Editable from user profile

2. **Support household members**
   - Invite other registered users to join household
   - Full visibility of household finances (future phases)
   - Remove members if needed

3. **Support external contacts**
   - Add people with whom you have transactions
   - Track if they have an account (registered) or not (unregistered)
   - Prepare for cross-household synchronization (Phase 3)

4. **Maintain data isolation**
   - Each household owns its data
   - No cross-household visibility (yet)
   - Prepare structure for future bidirectional sync

---

## 📊 Data Model

### New Tables

#### `households`

Represents a group of people who live together and share finances completely.

```sql
CREATE TABLE households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Optional fields for future use
  currency VARCHAR(3) DEFAULT 'COP',
  timezone VARCHAR(50) DEFAULT 'America/Bogota'
);

CREATE INDEX idx_households_created_by ON households(created_by);
```

**Business rules:**
- A user can create multiple households BUT can only be an active member of ONE at a time (enforced in Phase 3)
- Name is free text (examples: "Casa de José y María", "Apartamento 305", "Mi Hogar")
- Creator becomes first household member automatically
- Currency and timezone prepared for internationalization (future)

#### `household_members`

Links users to households with roles.

```sql
CREATE TYPE household_role AS ENUM ('owner', 'member');

CREATE TABLE household_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role household_role NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Ensure a user can't be added twice to same household
  UNIQUE(household_id, user_id)
);

CREATE INDEX idx_household_members_household ON household_members(household_id);
CREATE INDEX idx_household_members_user ON household_members(user_id);
```

**Business rules:**
- `role = 'owner'`: Can delete household, manage members, full permissions
- `role = 'member'`: Can create movements, view all household data
- Creator of household automatically becomes 'owner'
- At least one 'owner' must exist (enforce before deletion)
- Users can leave household unless they're the last owner

#### `contacts`

External people (friends, family not in household) with whom you have transactions.

```sql
CREATE TABLE contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  
  -- Contact identification
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255),
  phone VARCHAR(20),
  
  -- Link to registered user (if they have an account)
  linked_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  
  -- Metadata
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Prevent duplicate contacts in same household
  UNIQUE(household_id, email),
  UNIQUE(household_id, phone)
);

CREATE INDEX idx_contacts_household ON contacts(household_id);
CREATE INDEX idx_contacts_linked_user ON contacts(linked_user_id);
CREATE INDEX idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
```

**Business rules:**
- Contacts belong to a household (created by household members)
- Can be **unregistered** (`linked_user_id = NULL`) or **registered** (`linked_user_id` set)
- Email or phone required (at least one for identification)
- `linked_user_id` populated when:
  - User manually links contact to existing user
  - Contact creates account and system auto-detects (Phase 3)
- Notes field for personal reference ("papá", "amiga del colegio", etc.)

---

## 🔐 Permissions & Authorization

### Household Permissions

| Action | Owner | Member | Non-member |
|--------|-------|--------|------------|
| View household info | ✅ | ✅ | ❌ |
| Edit household name | ✅ | ❌ | ❌ |
| Add members | ✅ | ❌ | ❌ |
| Remove members | ✅ | ❌ | ❌ |
| Delete household | ✅ | ❌ | ❌ |
| Leave household | ✅* | ✅ | ❌ |
| Add contacts | ✅ | ✅ | ❌ |
| Edit contacts | ✅ | ✅ | ❌ |
| Delete contacts | ✅ | ✅ | ❌ |

*Owner can leave only if another owner exists, or household is deleted

### Data Visibility

**In Phase 2:**
- Users can only see households they belong to
- Users can only see contacts in their household
- No cross-household visibility yet

**In Phase 3:**
- Registered contacts will see movements where they're participants
- Bidirectional debt synchronization enabled
- See `FUTURE_VISION.md` section 5 for details

---

## 🎨 User Experience Flow

### 1. Household Creation

#### During Registration (Optional)

After successful registration, user sees:

```
┌────────────────────────────────────┐
│ ✅ ¡Cuenta creada!                │
├────────────────────────────────────┤
│                                    │
│ ¿Quieres crear tu hogar ahora?    │
│                                    │
│ Un hogar es el grupo de personas   │
│ con las que vives y compartes      │
│ gastos.                            │
│                                    │
│ [Crear mi hogar]                   │
│                                    │
│ [Omitir por ahora]                 │
│                                    │
└────────────────────────────────────┘
```

If user clicks "Crear mi hogar":

```
┌────────────────────────────────────┐
│ Crear Mi Hogar                     │
├────────────────────────────────────┤
│                                    │
│ Nombre de tu hogar                 │
│ ┌────────────────────────────────┐ │
│ │ Mi Casa                        │ │
│ └────────────────────────────────┘ │
│                                    │
│ Ejemplos:                          │
│ • Casa de José y María             │
│ • Apartamento 305                  │
│ • Mi Hogar                         │
│                                    │
│ [Cancelar]  [Crear Hogar]         │
│                                    │
└────────────────────────────────────┘
```

After creation, redirect to dashboard/movements page.

If user clicks "Omitir por ahora":
- Redirect to dashboard/movements
- Show reminder banner: "Necesitas crear un hogar para empezar a registrar gastos compartidos"
- User can create household later from profile

#### From User Profile (Anytime)

User navigates to profile and sees:

**If NO household:**

```
┌────────────────────────────────────┐
│ Mi Perfil                          │
├────────────────────────────────────┤
│ 👤 José Blanquicet                │
│ 📧 jose@example.com                │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ 🏠 Mi Hogar                        │
│                                    │
│ Aún no tienes un hogar             │
│                                    │
│ [+ Crear mi hogar]                 │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ [Cerrar Sesión]                    │
└────────────────────────────────────┘
```

**If household exists:**

```
┌────────────────────────────────────┐
│ Mi Perfil                          │
├────────────────────────────────────┤
│ 👤 José Blanquicet                │
│ 📧 jose@example.com                │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ 🏠 Mi Hogar: Casa de José y María │
│                                    │
│ [Ver detalles del hogar]           │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ [Cerrar Sesión]                    │
└────────────────────────────────────┘
```

### 2. Household Management

When user clicks "Ver detalles del hogar":

```
┌────────────────────────────────────┐
│ Mi Hogar: Casa de José y María    │
├────────────────────────────────────┤
│                                    │
│ Miembros (2)                       │
│ ┌────────────────────────────────┐ │
│ │ 👤 José (tú) - Propietario    │ │
│ │ 👤 María - Miembro            │ │
│ └────────────────────────────────┘ │
│                                    │
│ [+ Invitar miembro]                │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ Contactos (3)                      │
│ ┌────────────────────────────────┐ │
│ │ 👤 Papá                       │ │
│ │ 👤 Mamá                       │ │
│ │ 👤 🔗 Ana - ana@mail.com      │ │
│ │    (tiene cuenta)             │ │
│ └────────────────────────────────┘ │
│                                    │
│ [+ Agregar contacto]               │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ [Editar nombre]                    │
│ [Salir del hogar]                  │
│                                    │
└────────────────────────────────────┘
```

### 3. Adding Household Members

When user clicks "+ Invitar miembro":

```
┌────────────────────────────────────┐
│ Invitar Miembro al Hogar           │
├────────────────────────────────────┤
│                                    │
│ Email del miembro                  │
│ ┌────────────────────────────────┐ │
│ │ maria@example.com              │ │
│ └────────────────────────────────┘ │
│                                    │
│ ⚠️  El usuario debe tener una     │
│    cuenta registrada.              │
│                                    │
│ [Cancelar]  [Enviar invitación]   │
│                                    │
└────────────────────────────────────┘
```

**Backend flow:**
1. Validate email exists in `users` table
2. Check user not already in household
3. Create invitation (Phase 2: auto-accept, Phase 3: require confirmation)
4. Add to `household_members` with role='member'
5. Send email notification (Phase 3)

**Phase 2 simplification:**
- Auto-accept invitations (no confirmation needed)
- User appears in household immediately
- Email notification optional

**Phase 3 enhancement:**
- Invitation system with accept/reject
- User receives in-app notification
- Invitation expires after 7 days

### 4. Adding Contacts

When user clicks "+ Agregar contacto":

```
┌────────────────────────────────────┐
│ Agregar Contacto                   │
├────────────────────────────────────┤
│                                    │
│ Nombre *                           │
│ ┌────────────────────────────────┐ │
│ │ Papá                           │ │
│ └────────────────────────────────┘ │
│                                    │
│ Email                              │
│ ┌────────────────────────────────┐ │
│ │ papa@example.com               │ │
│ └────────────────────────────────┘ │
│                                    │
│ Teléfono                           │
│ ┌────────────────────────────────┐ │
│ │ +57 300 123 4567               │ │
│ └────────────────────────────────┘ │
│                                    │
│ Notas (opcional)                   │
│ ┌────────────────────────────────┐ │
│ │ Familia - padre                │ │
│ └────────────────────────────────┘ │
│                                    │
│ ℹ️  Email o teléfono requerido    │
│                                    │
│ [Cancelar]  [Agregar]             │
│                                    │
└────────────────────────────────────┘
```

**Backend flow:**
1. Validate at least email OR phone provided
2. Check if email matches existing user → auto-link `linked_user_id`
3. Create contact in `contacts` table
4. Return contact with linkage status

**UI feedback:**
- If linked to user: Show 🔗 icon + "(tiene cuenta)"
- If unregistered: Show regular icon
- Show success message: "Contacto agregado: Papá"

### 5. Contact Auto-Linking

When a contact creates an account (Phase 3 enhancement):

```
┌────────────────────────────────────┐
│ 🔗 Contacto Vinculado             │
├────────────────────────────────────┤
│                                    │
│ Papá (papa@example.com) ahora     │
│ tiene una cuenta en Gastos.        │
│                                    │
│ ¿Quieres compartir el historial    │
│ de movimientos con él?             │
│                                    │
│ [No, mantener privado]             │
│ [Sí, compartir historial]          │
│                                    │
└────────────────────────────────────┘
```

**Phase 2:** Auto-linking only, no notification
**Phase 3:** Add confirmation flow and historical data sharing

---

## 🔌 API Endpoints

### Household Endpoints

#### `POST /households`
Create a new household (authenticated)

**Request:**
```json
{
  "name": "Casa de José y María"
}
```

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "name": "Casa de José y María",
  "created_by": "user-uuid",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

#### `GET /households`
Get all households where user is a member

**Response:** `200 OK`
```json
{
  "households": [
    {
      "id": "uuid",
      "name": "Casa de José y María",
      "role": "owner",
      "member_count": 2,
      "contact_count": 3
    }
  ]
}
```

#### `GET /households/:id`
Get household details (if user is member)

**Response:** `200 OK`
```json
{
  "id": "uuid",
  "name": "Casa de José y María",
  "created_by": "user-uuid",
  "created_at": "2025-01-01T00:00:00Z",
  "members": [
    {
      "id": "member-uuid",
      "user_id": "user-uuid",
      "name": "José Blanquicet",
      "email": "jose@example.com",
      "role": "owner",
      "joined_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "member-uuid-2",
      "user_id": "user-uuid-2",
      "name": "María García",
      "email": "maria@example.com",
      "role": "member",
      "joined_at": "2025-01-02T00:00:00Z"
    }
  ],
  "contacts": [
    {
      "id": "contact-uuid",
      "name": "Papá",
      "email": "papa@example.com",
      "phone": "+57 300 123 4567",
      "is_registered": false,
      "linked_user_id": null,
      "notes": "Familia - padre"
    },
    {
      "id": "contact-uuid-2",
      "name": "Ana",
      "email": "ana@example.com",
      "phone": null,
      "is_registered": true,
      "linked_user_id": "user-uuid-3",
      "notes": "Amiga del colegio"
    }
  ]
}
```

#### `PATCH /households/:id`
Update household name (owner only)

**Request:**
```json
{
  "name": "Nueva Casa"
}
```

**Response:** `200 OK`

#### `DELETE /households/:id`
Delete household (owner only, requires confirmation)

**Response:** `204 No Content`

### Household Member Endpoints

#### `POST /households/:id/members`
Add member to household (owner only)

**Request:**
```json
{
  "email": "maria@example.com"
}
```

**Response:** `201 Created`
```json
{
  "id": "member-uuid",
  "household_id": "household-uuid",
  "user_id": "user-uuid",
  "role": "member",
  "joined_at": "2025-01-01T00:00:00Z"
}
```

**Error cases:**
- `404`: User not found
- `409`: User already in household
- `403`: Not authorized (not owner)

#### `DELETE /households/:household_id/members/:member_id`
Remove member from household (owner only, or self)

**Response:** `204 No Content`

**Business rules:**
- Owner can remove any member
- Members can remove themselves
- Cannot remove last owner

#### `POST /households/:id/leave`
Leave household (authenticated member)

**Response:** `204 No Content`

**Business rules:**
- Owner can leave only if another owner exists
- Last owner must delete household instead

### Contact Endpoints

#### `POST /households/:id/contacts`
Add contact to household (member or owner)

**Request:**
```json
{
  "name": "Papá",
  "email": "papa@example.com",
  "phone": "+57 300 123 4567",
  "notes": "Familia - padre"
}
```

**Response:** `201 Created`
```json
{
  "id": "contact-uuid",
  "household_id": "household-uuid",
  "name": "Papá",
  "email": "papa@example.com",
  "phone": "+57 300 123 4567",
  "linked_user_id": null,
  "is_registered": false,
  "notes": "Familia - padre",
  "created_at": "2025-01-01T00:00:00Z"
}
```

**Auto-linking:**
If email matches existing user, `linked_user_id` is set automatically.

#### `GET /households/:id/contacts`
List all contacts in household

**Response:** `200 OK`
```json
{
  "contacts": [...]
}
```

#### `PATCH /households/:household_id/contacts/:contact_id`
Update contact details

**Request:**
```json
{
  "name": "Papa Juan",
  "notes": "Padre"
}
```

**Response:** `200 OK`

#### `DELETE /households/:household_id/contacts/:contact_id`
Delete contact

**Response:** `204 No Content`

**Business rules:**
- Cannot delete if contact has associated movements (Phase 3)
- Phase 2: Allow deletion freely

---

## 🗄️ Migration Strategy

### Database Migrations

**Migration 001: Create households table**
```sql
-- backend/migrations/004_create_households.up.sql
CREATE TABLE households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  currency VARCHAR(3) DEFAULT 'COP',
  timezone VARCHAR(50) DEFAULT 'America/Bogota'
);

CREATE INDEX idx_households_created_by ON households(created_by);
```

**Migration 002: Create household_members table**
```sql
-- backend/migrations/005_create_household_members.up.sql
CREATE TYPE household_role AS ENUM ('owner', 'member');

CREATE TABLE household_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role household_role NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(household_id, user_id)
);

CREATE INDEX idx_household_members_household ON household_members(household_id);
CREATE INDEX idx_household_members_user ON household_members(user_id);
```

**Migration 003: Create contacts table**
```sql
-- backend/migrations/006_create_contacts.up.sql
CREATE TABLE contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255),
  phone VARCHAR(20),
  linked_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- At least email or phone required (enforced in app logic)
  CONSTRAINT email_or_phone_required CHECK (
    email IS NOT NULL OR phone IS NOT NULL
  )
);

CREATE INDEX idx_contacts_household ON contacts(household_id);
CREATE INDEX idx_contacts_linked_user ON contacts(linked_user_id);
CREATE INDEX idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;

-- Add unique constraints separately for better control
ALTER TABLE contacts ADD CONSTRAINT contacts_household_email_unique 
  UNIQUE(household_id, email) WHERE email IS NOT NULL;
  
ALTER TABLE contacts ADD CONSTRAINT contacts_household_phone_unique 
  UNIQUE(household_id, phone) WHERE phone IS NOT NULL;
```

### Rollback Migrations

```sql
-- backend/migrations/006_create_contacts.down.sql
DROP TABLE IF EXISTS contacts;

-- backend/migrations/005_create_household_members.down.sql
DROP TABLE IF EXISTS household_members;
DROP TYPE IF EXISTS household_role;

-- backend/migrations/004_create_households.down.sql
DROP TABLE IF EXISTS households;
```

---

## 🏗️ Backend Implementation Plan

### Project Structure

```
backend/
├── internal/
│   ├── auth/           # existing
│   ├── users/          # existing
│   ├── households/     # NEW
│   │   ├── households.go        # household CRUD
│   │   ├── members.go           # member management
│   │   ├── contacts.go          # contact management
│   │   ├── handlers.go          # HTTP handlers
│   │   └── models.go            # data models
│   ├── middleware/     # existing
│   └── httpserver/     # existing - add new routes
└── migrations/
    ├── 004_create_households.up.sql
    ├── 004_create_households.down.sql
    ├── 005_create_household_members.up.sql
    ├── 005_create_household_members.down.sql
    ├── 006_create_contacts.up.sql
    └── 006_create_contacts.down.sql
```

### Implementation Steps

**Step 1: Database Layer**
- [ ] Create migration files
- [ ] Run migrations on dev database
- [ ] Verify schema with `psql`

**Step 2: Backend Models**
- [ ] Create `internal/households/models.go`
- [ ] Define structs: `Household`, `HouseholdMember`, `Contact`
- [ ] Add validation methods

**Step 3: Backend Logic**
- [ ] `households.go`: CRUD operations
- [ ] `members.go`: Member management + authorization
- [ ] `contacts.go`: Contact CRUD + auto-linking
- [ ] Add tests for each module

**Step 4: API Handlers**
- [ ] Register routes in `httpserver`
- [ ] Implement handlers with auth middleware
- [ ] Add request validation
- [ ] Error handling

**Step 5: Integration**
- [ ] Test API with curl/Postman
- [ ] Verify permissions work correctly
- [ ] Test edge cases (delete last owner, duplicate members, etc.)

---

## 🎨 Frontend Implementation Plan

### Project Structure

```
frontend/
├── pages/
│   ├── login.js                    # existing
│   ├── registrar-movimiento.js     # existing
│   ├── profile.js                  # NEW - user profile
│   ├── household.js                # NEW - household management
│   ├── household-create.js         # NEW - household creation
│   └── contact-form.js             # NEW - add/edit contact
├── components/                      # NEW directory
│   ├── household-card.js           # Display household summary
│   ├── member-list.js              # List household members
│   └── contact-list.js             # List contacts
├── app.js                          # Update routes
├── router.js                       # existing
└── styles.css                      # Add new styles
```

### Implementation Steps

**Step 1: Post-Registration Flow**
- [ ] Add optional household creation after registration
- [ ] "Crear mi hogar" dialog
- [ ] "Omitir por ahora" → show reminder banner

**Step 2: User Profile Page**
- [ ] Create `pages/profile.js`
- [ ] Show user info + household status
- [ ] Link to household management
- [ ] Logout button

**Step 3: Household Management**
- [ ] Create `pages/household.js`
- [ ] Show household details
- [ ] Member list with roles
- [ ] Contact list with linkage status
- [ ] Edit/delete actions

**Step 4: Member Management**
- [ ] Invite member form (email input)
- [ ] Remove member confirmation
- [ ] Leave household confirmation

**Step 5: Contact Management**
- [ ] Create `pages/contact-form.js`
- [ ] Add contact form (name, email, phone, notes)
- [ ] Edit contact
- [ ] Delete contact confirmation
- [ ] Show linkage status (🔗 icon)

**Step 6: Navigation**
- [ ] Add "Perfil" link to main menu
- [ ] Add "Mi Hogar" link to main menu
- [ ] Breadcrumbs for navigation

---

## ✅ Definition of Done

This phase is complete when:

**Backend:**
- [ ] All migrations created and tested
- [ ] Household CRUD API working
- [ ] Member management API working
- [ ] Contact management API working
- [ ] Authorization checks implemented
- [ ] Unit tests written and passing
- [ ] API documentation updated

**Frontend:**
- [ ] Post-registration household creation working
- [ ] User profile page showing household status
- [ ] Household management page functional
- [ ] Member invite/remove working
- [ ] Contact add/edit/delete working
- [ ] Contact auto-linking showing correctly
- [ ] Responsive design on mobile

**Integration:**
- [ ] End-to-end flow tested
- [ ] User can create household during/after registration
- [ ] User can manage members and contacts
- [ ] Data isolation verified (can't access other households)
- [ ] Deployed to production

**Documentation:**
- [ ] This design doc updated with learnings
- [ ] API documentation complete
- [ ] User guide created (basic)

---

## 🚫 Out of Scope (Phase 3)

The following features are explicitly **NOT** in Phase 2:

- ❌ Cross-household movement synchronization
- ❌ Notifications between households
- ❌ Debt calculation and balances
- ❌ Movement creation with participants
- ❌ Events and shared expenses
- ❌ Bidirectional debt confirmation
- ❌ Payment workflows
- ❌ Contact upgrade flow with historical data
- ❌ Email invitations to household members

**Why defer?**
- Phase 2 focuses on **structure** (households, contacts)
- Phase 3 will add **interactions** (shared movements, sync)
- Simpler to test and validate in isolation

---

## 📚 References

- `FUTURE_VISION.md` - Full product vision
- `01_AUTH_PHASE.md` - Authentication foundation
- `00_N8N_PHASE.md` - Current movement system (unchanged)

---

## 🗓️ Timeline Estimate

| Task | Effort | Dependencies |
|------|--------|--------------|
| Database migrations | 2 hours | None |
| Backend models | 4 hours | Migrations |
| Backend logic + tests | 8 hours | Models |
| API handlers | 4 hours | Logic |
| Frontend profile page | 4 hours | API ready |
| Frontend household mgmt | 8 hours | API ready |
| Frontend contact mgmt | 6 hours | API ready |
| Integration testing | 4 hours | All complete |
| Documentation | 2 hours | All complete |
| **Total** | **~42 hours** | **~1 week** |

---

**Last Updated:** 2025-12-30  
**Status:** 📋 Planning Phase  
**Next Action:** Review and approve design, then start migrations
