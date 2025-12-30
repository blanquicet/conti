-- Drop index for active contacts
DROP INDEX IF EXISTS idx_contacts_active;

-- Drop is_active column from contacts
ALTER TABLE contacts
DROP COLUMN IF EXISTS is_active;
