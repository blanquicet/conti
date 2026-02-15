DROP INDEX IF EXISTS idx_contacts_link_pending;
ALTER TABLE contacts DROP COLUMN IF EXISTS link_responded_at;
ALTER TABLE contacts DROP COLUMN IF EXISTS link_requested_at;
ALTER TABLE contacts DROP COLUMN IF EXISTS link_status;
DROP TYPE IF EXISTS contact_link_status;
