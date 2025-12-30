-- Create households table
-- Represents a group of people who live together and share finances completely

CREATE TABLE IF NOT EXISTS households (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optional fields for future use
    currency VARCHAR(3) DEFAULT 'COP',
    timezone VARCHAR(50) DEFAULT 'America/Bogota'
);

-- Index for looking up households by creator
CREATE INDEX IF NOT EXISTS idx_households_created_by ON households(created_by);
