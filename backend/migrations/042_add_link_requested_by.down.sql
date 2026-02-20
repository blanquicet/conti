DROP INDEX IF EXISTS idx_contacts_link_requested_by;
ALTER TABLE contacts DROP COLUMN IF EXISTS link_requested_by_user_id;
