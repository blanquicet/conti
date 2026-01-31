-- Migration: Add cutoff_day and linked_account_id to payment_methods
-- Phase 9: Credit Cards

-- Add cutoff_day for credit cards (billing cycle cut-off day)
-- NULL means "last day of month" (default behavior)
-- 1-28: specific day (safe for all months)
-- 29-31: will use last day if month is shorter
ALTER TABLE payment_methods
ADD COLUMN cutoff_day INTEGER CHECK (cutoff_day >= 1 AND cutoff_day <= 31);

-- Add linked_account_id for debit cards
-- Required for debit cards so we can track account balance accurately
-- Must reference a savings account (enforced in application logic)
ALTER TABLE payment_methods
ADD COLUMN linked_account_id UUID REFERENCES accounts(id) ON DELETE RESTRICT;

-- Add comments for documentation
COMMENT ON COLUMN payment_methods.cutoff_day IS 
  'Credit card billing cycle cut-off day. NULL = last day of month. Only applicable for credit_card type.';

COMMENT ON COLUMN payment_methods.linked_account_id IS 
  'For debit cards: the savings account this card draws from. Required for debit_card type, NULL for others.';

-- Index for linked account lookups (for balance calculation queries)
CREATE INDEX idx_payment_methods_linked_account ON payment_methods(linked_account_id) 
  WHERE linked_account_id IS NOT NULL;
