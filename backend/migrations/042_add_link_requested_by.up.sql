-- Add link_requested_by_user_id to track WHO sent the link request
-- Previously we were incorrectly showing the household owner instead of the actual requester

ALTER TABLE contacts ADD COLUMN link_requested_by_user_id UUID REFERENCES users(id);

-- Create index for potential queries
CREATE INDEX idx_contacts_link_requested_by ON contacts(link_requested_by_user_id) WHERE link_requested_by_user_id IS NOT NULL;
