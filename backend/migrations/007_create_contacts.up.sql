-- Create contacts table
-- External people (friends, family not in household) with whom you have transactions

CREATE TABLE IF NOT EXISTS contacts (
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

-- Index for looking up contacts by household
CREATE INDEX IF NOT EXISTS idx_contacts_household ON contacts(household_id);

-- Index for looking up contacts by linked user
CREATE INDEX IF NOT EXISTS idx_contacts_linked_user ON contacts(linked_user_id);

-- Partial indexes for email and phone lookups (only when not null)
CREATE INDEX IF NOT EXISTS idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_phone ON contacts(phone) WHERE phone IS NOT NULL;
