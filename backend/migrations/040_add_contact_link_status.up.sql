-- Add link_status to contacts for bidirectional contact linking ("friend request" flow)
-- NONE = regular unlinked contact
-- PENDING = linked_user_id set, waiting for target user to accept
-- ACCEPTED = both sides agreed, cross-household visibility enabled
-- REJECTED = target user declined (can be re-requested)

CREATE TYPE contact_link_status AS ENUM ('NONE', 'PENDING', 'ACCEPTED', 'REJECTED');

ALTER TABLE contacts ADD COLUMN link_status contact_link_status NOT NULL DEFAULT 'NONE';
ALTER TABLE contacts ADD COLUMN link_requested_at TIMESTAMPTZ;
ALTER TABLE contacts ADD COLUMN link_responded_at TIMESTAMPTZ;

-- Index for finding pending requests for a user
CREATE INDEX idx_contacts_link_pending
    ON contacts(linked_user_id, link_status)
    WHERE link_status = 'PENDING';

-- Backfill: existing linked contacts are already accepted (they were linked before this feature)
UPDATE contacts
SET link_status = 'ACCEPTED',
    link_requested_at = created_at,
    link_responded_at = created_at
WHERE linked_user_id IS NOT NULL;
