-- Create household_invitations table
-- Tracks invitations for users to join households

CREATE TABLE IF NOT EXISTS household_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    token TEXT NOT NULL UNIQUE,
    invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ,  -- NULL for now, Phase 3 will set to 7 days
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ensure one pending invitation per email per household
    UNIQUE(household_id, email)
);

-- Index for token lookups
CREATE INDEX IF NOT EXISTS idx_household_invitations_token ON household_invitations(token);

-- Index for email lookups
CREATE INDEX IF NOT EXISTS idx_household_invitations_email ON household_invitations(email);

-- Index for looking up invitations by household
CREATE INDEX IF NOT EXISTS idx_household_invitations_household ON household_invitations(household_id);
