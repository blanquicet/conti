# Household & Contacts Management

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
- Name is free text (examples: "Casa de Jose y Caro", "Apartamento 305", "Mi Hogar")
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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contacts_household ON contacts(household_id);
CREATE INDEX idx_contacts_linked_user ON contacts(linked_user_id);
CREATE INDEX idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
CREATE INDEX idx_contacts_phone ON contacts(phone) WHERE phone IS NOT NULL;
```

**Business rules:**
- Contacts belong to a household (created by household members)
- Can be **unregistered** (`linked_user_id = NULL`) or **registered** (`linked_user_id` set)
- Email and phone are **optional** (useful for quick additions like "Papá", "Ana")
- Email or phone **required only for linking** to registered users
- `linked_user_id` populated when:
  - User manually links contact to existing user via email/phone
  - Contact creates account and system auto-detects (Phase 3)
- Notes field for personal reference ("papá", "amiga del colegio", etc.)
- Can be edited later to add email/phone for linking purposes

---

## 🔐 Permissions & Authorization

### Household Permissions

| Action | Owner | Member | Non-member |
|--------|-------|--------|------------|
| View household info | ✅ | ✅ | ❌ |
| Edit household name | ✅ | ✅ | ❌ |
| Add members | ✅ | ✅ | ❌ |
| Remove members | ✅ | ✅ | ❌ |
| Change member role | ✅ | ❌ | ❌ |
| Promote contact to member | ✅ | ❌ | ❌ |
| Delete household | ✅ | ❌ | ❌ |
| Leave household | ✅* | ✅ | ❌ |
| Add contacts | ✅ | ✅ | ❌ |
| Edit contacts | ✅ | ✅ | ❌ |
| Delete contacts | ✅ | ✅ | ❌ |

*Owner can leave only if another owner exists, or household is deleted

### Role Management

**Changing member roles:**
- Owners can promote members to owner
- Owners can demote other owners to member
- Cannot demote yourself if you're the last owner
- Members cannot change roles

**Promoting contacts to members:**
- Only owners can promote contacts to household members
- Contact must have a linked user account (registered)
- Contact becomes a member with role='member'
- Can be promoted to owner later

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
│ • Casa de Jose y Caro             │
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
│ 👤 Jose Blanquicet                │
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
│ 👤 Jose Blanquicet                │
│ 📧 jose@example.com                │
│                                    │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                    │
│ 🏠 Mi Hogar: Casa de Jose y Caro │
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
│ Mi Hogar: Casa de Jose y Caro    │
├────────────────────────────────────┤
│                                    │
│ Miembros (2)                       │
│ ┌────────────────────────────────┐ │
│ │ 👤 José (tú) - Propietario    │ │
│ │ 👤 Caro - Miembro            │ │
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
│ │ 👤 🔗 Maria - maria@mail.com      │ │
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
│ │ caro@example.com               │ │
│ └────────────────────────────────┘ │
│                                    │
│ ℹ️  Si el usuario no tiene cuenta,│
│    recibirá un link de invitación │
│    para registrarse.               │
│                                    │
│ [Cancelar]  [Enviar invitación]   │
│                                    │
└────────────────────────────────────┘
```

**Backend flow:**

**Case 1: User already has account**
1. Check if email exists in `users` table
2. Check user not already in household
3. Create `household_members` entry with role='member'
4. Send email notification with direct link to household
5. User sees household immediately in their dashboard

**Case 2: User doesn't have account**
1. Generate invitation token (store in new `household_invitations` table)
2. Send email with registration link + invitation token
3. Registration page detects token and shows invitation context
4. After successful registration, user is automatically added to household

**Phase 2 implementation:**
- Auto-accept for existing users (no confirmation needed)
- Email notification with link to login
- New users register via invite link
- No invitation expiration (Phase 3 will add 7-day expiry)

**New table needed:**
```sql
CREATE TABLE household_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token TEXT NOT NULL UNIQUE,
  invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ,  -- NULL for now, Phase 3 will set to 7 days
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(household_id, email)
);

CREATE INDEX idx_household_invitations_token ON household_invitations(token);
CREATE INDEX idx_household_invitations_email ON household_invitations(email);
```

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
│ Email (opcional)                   │
│ ┌────────────────────────────────┐ │
│ │ papa@example.com               │ │
│ └────────────────────────────────┘ │
│                                    │
│ Teléfono (opcional)                │
│ ┌────────────────────────────────┐ │
│ │ +57 300 123 4567               │ │
│ └────────────────────────────────┘ │
│                                    │
│ Notas (opcional)                   │
│ ┌────────────────────────────────┐ │
│ │ Familia - padre                │ │
│ └────────────────────────────────┘ │
│                                    │
│ ℹ️  Email o teléfono solo son     │
│    necesarios para vincular con   │
│    una cuenta registrada.         │
│                                    │
│ [Cancelar]  [Agregar]             │
│                                    │
└────────────────────────────────────┘
```

**Backend flow:**
1. Validate name is provided
2. Email and phone are **optional** (can be NULL)
3. If email provided, check if it matches existing user → auto-link `linked_user_id`
4. Create contact in `contacts` table
5. Return contact with linkage status

**UI feedback:**
- If linked to user: Show 🔗 icon + "(tiene cuenta)"
- If unregistered: Show regular icon
- Show success message: "Contacto agregado: Papá"

**Later editing:**
- User can add/update email or phone to enable linking
- When email is added, system auto-checks for existing user account
- Contact can be promoted to household member if they have a linked account

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
  "name": "Casa de Jose y Caro"
}
```

**Response:** `201 Created`
```json
{
  "id": "uuid",
  "name": "Casa de Jose y Caro",
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
      "name": "Casa de Jose y Caro",
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
  "name": "Casa de Jose y Caro",
  "created_by": "user-uuid",
  "created_at": "2025-01-01T00:00:00Z",
  "members": [
    {
      "id": "member-uuid",
      "user_id": "user-uuid",
      "name": "Jose Blanquicet",
      "email": "jose@example.com",
      "role": "owner",
      "joined_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "member-uuid-2",
      "user_id": "user-uuid-2",
      "name": "Caro Salazar",
      "email": "caro@example.com",
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
      "name": "Maria",
      "email": "maria@example.com",
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
  "email": "caro@example.com"
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

#### `PATCH /households/:household_id/members/:member_id/role`
Change member role (owner only)

**Request:**
```json
{
  "role": "owner"  // or "member"
}
```

**Response:** `200 OK`
```json
{
  "id": "member-uuid",
  "household_id": "household-uuid",
  "user_id": "user-uuid",
  "role": "owner",
  "joined_at": "2025-01-01T00:00:00Z"
}
```

**Business rules:**
- Only owners can change roles
- Cannot demote yourself if you're the last owner
- Can promote members to owner
- Can demote owners to member

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

#### `POST /households/:household_id/contacts/:contact_id/promote`
Promote contact to household member (owner only)

**Response:** `201 Created`
```json
{
  "id": "member-uuid",
  "household_id": "household-uuid",
  "user_id": "user-uuid-from-contact",
  "role": "member",
  "joined_at": "2025-01-01T00:00:00Z"
}
```

**Business rules:**
- Only owners can promote contacts
- Contact must have `linked_user_id` (must be registered)
- Contact is removed from contacts table
- User is added to household_members with role='member'
- Cannot promote unregistered contacts

**Error cases:**
- `400`: Contact not linked to user account
- `403`: Not authorized (not owner)
- `409`: User already in household

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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contacts_household ON contacts(household_id);
CREATE INDEX idx_contacts_linked_user ON contacts(linked_user_id);
CREATE INDEX idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
CREATE INDEX idx_contacts_phone ON contacts(phone) WHERE phone IS NOT NULL;
```

**Migration 004: Create household_invitations table**
```sql
-- backend/migrations/007_create_household_invitations.up.sql
CREATE TABLE household_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  token TEXT NOT NULL UNIQUE,
  invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ,  -- NULL in Phase 2
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(household_id, email)
);

CREATE INDEX idx_household_invitations_token ON household_invitations(token);
CREATE INDEX idx_household_invitations_email ON household_invitations(email);
CREATE INDEX idx_household_invitations_household ON household_invitations(household_id);
```

### Rollback Migrations

```sql
-- backend/migrations/007_create_household_invitations.down.sql
DROP TABLE IF EXISTS household_invitations;

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

### Phase 2A: Backend Only (Implement & Validate First)

**Goal:** Complete and test all backend functionality before touching frontend.

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
│   │   ├── invitations.go       # invitation flow
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
    ├── 006_create_contacts.down.sql
    ├── 007_create_household_invitations.up.sql
    └── 007_create_household_invitations.down.sql
```

### Backend Implementation Steps (Sequential)

**Step 1: Database Schema**
- [ ] Write all 4 migration files (up & down)
- [ ] Review schema with team
- [ ] Run migrations on local dev database
- [ ] Verify schema with `\d` commands in psql
- [ ] Test rollback migrations work correctly

**Step 2: Data Models**
- [ ] Create `internal/households/models.go`
- [ ] Define structs: `Household`, `HouseholdMember`, `Contact`, `Invitation`
- [ ] Add JSON tags for API responses
- [ ] Add validation methods (e.g., `Validate()`)
- [ ] Document business rules in comments

**Step 3: Repository Layer (Database Logic)**
- [ ] `households.go`: 
  - [ ] `CreateHousehold()`
  - [ ] `GetHousehold()`
  - [ ] `UpdateHousehold()`
  - [ ] `DeleteHousehold()`
  - [ ] `ListUserHouseholds()`
- [ ] `members.go`:
  - [ ] `AddMember()`
  - [ ] `RemoveMember()`
  - [ ] `UpdateMemberRole()`
  - [ ] `GetHouseholdMembers()`
  - [ ] `CheckMemberPermissions()`
- [ ] `contacts.go`:
  - [ ] `CreateContact()`
  - [ ] `UpdateContact()`
  - [ ] `DeleteContact()`
  - [ ] `GetHouseholdContacts()`
  - [ ] `AutoLinkContact()` (check email against users)
  - [ ] `PromoteContactToMember()`
- [ ] `invitations.go`:
  - [ ] `CreateInvitation()`
  - [ ] `GetInvitationByToken()`
  - [ ] `AcceptInvitation()`
  - [ ] `ListPendingInvitations()`

**Step 4: Unit Tests (Critical)**
- [ ] Test household CRUD operations
- [ ] Test member management with different roles
- [ ] Test permission checks (owner vs member)
- [ ] Test contact auto-linking logic
- [ ] Test contact promotion (registered vs unregistered)
- [ ] Test invitation flow
- [ ] Test edge cases:
  - [ ] Cannot remove last owner
  - [ ] Cannot promote unregistered contact
  - [ ] Cannot demote yourself as last owner
  - [ ] Duplicate member prevention
  - [ ] Data isolation between households

**Step 5: API Handlers**
- [ ] Register all routes in `httpserver`
- [ ] Implement handlers with proper error handling
- [ ] Add authentication middleware to all routes
- [ ] Add authorization checks (owner-only actions)
- [ ] Add request validation (validate input JSON)
- [ ] Return proper HTTP status codes

**Step 6: API Integration Testing**
- [ ] Test with `curl` or Postman
- [ ] Create test collection with all endpoints
- [ ] Test happy paths
- [ ] Test error cases (401, 403, 404, 409, etc.)
- [ ] Test concurrent operations
- [ ] Verify database state after operations

**Step 7: Backend Documentation**
- [ ] Document all API endpoints (request/response)
- [ ] Add examples for each endpoint
- [ ] Document error responses
- [ ] Update API documentation (e.g., Swagger/OpenAPI if used)

**✅ Backend Validation Checkpoint**

Before proceeding to frontend:
- [ ] All unit tests passing
- [ ] All API endpoints tested manually
- [ ] No regressions in existing functionality
- [ ] Code reviewed
- [ ] Migrations tested (up and down)
- [ ] Performance acceptable (query times, N+1 queries checked)
- [ ] Security reviewed (no SQL injection, proper authorization)

---

## 🎨 Frontend Implementation Plan

### Phase 2B: Frontend (Only After Backend Validated)

**Prerequisites:**
- ✅ All backend functionality working
- ✅ API endpoints tested and validated
- ✅ Backend deployed to dev environment

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
│   ├── navbar.js                   # NEW - hamburger menu navigation
│   ├── household-card.js           # Display household summary
│   ├── member-list.js              # List household members
│   └── contact-list.js             # List contacts
├── app.js                          # Update routes
├── router.js                       # existing
└── styles.css                      # Add new styles
```

### Navigation Menu (Hamburger)

**Location:** Top-right corner of all authenticated pages

**Appearance:**
```
┌─────────────────────────────────┐
│  Gastos               ☰ Menu   │  ← Hamburger icon (☰)
├─────────────────────────────────┤
│                                 │
│  Content here...                │
```

When clicked, shows dropdown menu:
```
┌─────────────────────────────────┐
│  Gastos               ☰ Menu   │
│                   ┌───────────┐ │
│                   │ 🏠 Perfil │ │
│                   │ 📝 Gastos │ │
│                   │ 🚪 Salir  │ │
│                   └───────────┘ │
├─────────────────────────────────┤
```

**Menu items:**
- **Perfil** → `/profile` (user profile + household management)
- **Gastos** → `/registrar-movimiento` (expense tracking)
- **Salir** → Logout action (clears session, redirects to `/`)

**Implementation:**
- Component: `components/navbar.js`
- Visible only when authenticated
- Current page highlighted in menu
- Click outside to close menu
- Responsive: Full width on mobile, dropdown on desktop

### Frontend Implementation Steps (Sequential)

**Step 1: Navigation Infrastructure**
- [ ] Create `components/` directory
- [ ] Create `components/navbar.js`
- [ ] Hamburger icon (☰) in top-right
- [ ] Dropdown menu with Profile, Gastos, Salir
- [ ] Show current user name (from session)
- [ ] Highlight active page
- [ ] Click outside to close functionality
- [ ] Responsive styling
- [ ] Add to `registrar-movimiento.js` page (test)

**Step 2: Profile Page (Read-Only First)**
- [ ] Create `pages/profile.js`
- [ ] Show user info (name, email)
- [ ] Fetch and display household status
- [ ] Show "No household" state
- [ ] Show household name if exists
- [ ] Link to household details
- [ ] Add navbar to this page
- [ ] Test with backend API

**Step 3: Household Creation Flow**
- [ ] Post-registration household creation (optional)
- [ ] Create `pages/household-create.js`
- [ ] Household creation form
- [ ] Handle "skip for now" option
- [ ] Success/error handling
- [ ] Navigate to appropriate page after creation

**Step 4: Household Management (Read-Only First)**
- [ ] Create `pages/household.js`
- [ ] Fetch and display household details
- [ ] Create `components/member-list.js`
- [ ] Display members with roles
- [ ] Create `components/contact-list.js`
- [ ] Display contacts with linkage status (🔗)
- [ ] Test all read operations

**Step 5: Member Management (Write Operations)**
- [ ] Add "Invite member" form
- [ ] Handle invitation submission
- [ ] Display pending invitations
- [ ] Member removal (with confirmation)
- [ ] Leave household (with confirmation)
- [ ] Role change UI (owner only)
- [ ] Test all member operations

**Step 6: Contact Management**
- [ ] Create `pages/contact-form.js`
- [ ] Add contact form (name required, email/phone optional)
- [ ] Edit contact functionality
- [ ] Delete contact (with confirmation)
- [ ] Show linkage status
- [ ] Promote contact to member (owner only, if linked)
- [ ] Test all contact operations

**Step 7: Polish & Edge Cases**
- [ ] Loading states for all async operations
- [ ] Error messages user-friendly
- [ ] Success confirmations
- [ ] Disable buttons during operations
- [ ] Handle network errors gracefully
- [ ] Responsive design on mobile
- [ ] Cross-browser testing

**Step 8: Integration Testing**
- [ ] Complete end-to-end flows
- [ ] Test with different user roles
- [ ] Test permission boundaries
- [ ] Test with slow network
- [ ] Test error scenarios

---

## ✅ Definition of Done

### Phase 2A Complete (Backend) when:

**Database:**
- [ ] All 4 migrations created (households, members, contacts, invitations)
- [ ] Migrations tested (up and down)
- [ ] Schema verified in dev database
- [ ] Data integrity constraints working

**Backend Code:**
- [ ] All models defined with validation
- [ ] Household CRUD API working
- [ ] Member management API working (add, remove, change role)
- [ ] Contact management API working (CRUD + auto-linking)
- [ ] Contact promotion API working
- [ ] Invitation flow API working
- [ ] Authorization checks implemented (owner vs member)
- [ ] Unit tests written and passing (>80% coverage)
- [ ] Integration tests passing

**API Testing:**
- [ ] All endpoints tested with curl/Postman
- [ ] Happy paths validated
- [ ] Error cases handled correctly (401, 403, 404, 409)
- [ ] Edge cases tested:
  - [ ] Cannot remove last owner
  - [ ] Cannot promote unregistered contact
  - [ ] Cannot demote yourself as last owner
  - [ ] Duplicate member prevention
  - [ ] Data isolation between households
- [ ] Performance acceptable (<200ms for read, <500ms for write)
- [ ] No N+1 query issues

**Documentation:**
- [ ] API endpoints documented
- [ ] Request/response examples provided
- [ ] Error codes documented
- [ ] Business rules documented in code comments

**Code Quality:**
- [ ] Code reviewed by peer
- [ ] No security vulnerabilities (SQL injection, unauthorized access)
- [ ] Proper error handling
- [ ] Logging in place for debugging

---

### Phase 2B Complete (Frontend) when:

**Prerequisites:**
- [ ] Phase 2A (Backend) fully complete
- [ ] Backend deployed to dev environment
- [ ] API tested and stable

**UI Components:**
- [ ] Navigation menu (hamburger) implemented
- [ ] Menu shows on all authenticated pages
- [ ] User profile page created
- [ ] Household management page created
- [ ] Member list component created
- [ ] Contact list component created
- [ ] All forms functional

**Features:**
- [ ] Post-registration household creation working
- [ ] User can view their household
- [ ] Member invite/remove working
- [ ] Member role change working (owner only)
- [ ] Contact add/edit/delete working
- [ ] Contact auto-linking displaying correctly (🔗 icon)
- [ ] Contact promotion to member working (owner only)
- [ ] Responsive design on mobile
- [ ] Loading states for all async operations
- [ ] Error messages user-friendly

**Integration:**
- [ ] End-to-end flow tested
- [ ] User can create household during/after registration
- [ ] User can manage members and contacts
- [ ] User can change member roles
- [ ] User can promote contacts to members
- [ ] Data isolation verified (can't access other households)
- [ ] Cross-browser tested (Chrome, Firefox, Safari)

**Deployment:**
- [ ] Frontend deployed to production
- [ ] Backend deployed to production
- [ ] Smoke tests passing in production

**Documentation:**
- [ ] User guide created (basic)
- [ ] Design doc updated with learnings
- [ ] Known issues documented

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
