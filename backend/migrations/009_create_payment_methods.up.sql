-- Create payment_method_type enum
CREATE TYPE payment_method_type AS ENUM (
  'credit_card',
  'debit_card',
  'cash',
  'other'
);

-- Create payment_methods table
CREATE TABLE IF NOT EXISTS payment_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  name VARCHAR(100) NOT NULL,
  type payment_method_type NOT NULL,
  
  -- Sharing
  is_shared_with_household BOOLEAN NOT NULL DEFAULT FALSE,
  
  -- Optional metadata
  last4 VARCHAR(4), -- Last 4 digits of card/account
  institution VARCHAR(100), -- Bank name, card issuer
  notes TEXT,
  
  -- Lifecycle
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Unique constraint: prevent duplicate names per household
  UNIQUE(household_id, name)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_payment_methods_household ON payment_methods(household_id);
CREATE INDEX IF NOT EXISTS idx_payment_methods_owner ON payment_methods(owner_id);
CREATE INDEX IF NOT EXISTS idx_payment_methods_active ON payment_methods(is_active) WHERE is_active = TRUE;
