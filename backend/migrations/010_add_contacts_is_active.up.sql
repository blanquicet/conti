-- Add is_active column to contacts table
ALTER TABLE contacts
ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Index for active contacts
CREATE INDEX IF NOT EXISTS idx_contacts_active ON contacts(is_active) WHERE is_active = TRUE;
