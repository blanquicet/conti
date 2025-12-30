-- Create household_role enum type
CREATE TYPE household_role AS ENUM ('owner', 'member');

-- Create household_members table
-- Links users to households with roles

CREATE TABLE IF NOT EXISTS household_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role household_role NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ensure a user can't be added twice to same household
    UNIQUE(household_id, user_id)
);

-- Index for looking up members by household
CREATE INDEX IF NOT EXISTS idx_household_members_household ON household_members(household_id);

-- Index for looking up households by user
CREATE INDEX IF NOT EXISTS idx_household_members_user ON household_members(user_id);
