-- Migration: Create credit_card_payments table
-- Phase 9: Credit Cards
-- Tracks payments made TO credit cards (paying off the balance)

CREATE TABLE credit_card_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  
  -- Which credit card is being paid
  credit_card_id UUID NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  
  -- Payment details
  amount DECIMAL(15, 2) NOT NULL CHECK (amount > 0),
  payment_date DATE NOT NULL,
  notes TEXT,
  
  -- Source of payment (must be a savings account - enforced in application)
  source_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);

-- Indexes for common queries
CREATE INDEX idx_cc_payments_household ON credit_card_payments(household_id);
CREATE INDEX idx_cc_payments_credit_card ON credit_card_payments(credit_card_id);
CREATE INDEX idx_cc_payments_date ON credit_card_payments(payment_date);
CREATE INDEX idx_cc_payments_source ON credit_card_payments(source_account_id);

-- Composite index for billing cycle queries (card + date range)
CREATE INDEX idx_cc_payments_card_date ON credit_card_payments(credit_card_id, payment_date);

-- Add comments
COMMENT ON TABLE credit_card_payments IS 
  'Payments made to credit cards to reduce the balance. Source must be a savings account.';
