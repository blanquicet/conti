-- Rollback: Remove cutoff_day and linked_account_id from payment_methods

DROP INDEX IF EXISTS idx_payment_methods_linked_account;

ALTER TABLE payment_methods DROP COLUMN IF EXISTS linked_account_id;
ALTER TABLE payment_methods DROP COLUMN IF EXISTS cutoff_day;
