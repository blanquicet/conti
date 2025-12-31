-- Remove bank_account and digital_wallet from payment_method_type enum
-- Note: PostgreSQL doesn't support removing enum values directly,
-- so we need to recreate the enum

-- Step 1: Convert any existing bank_account and digital_wallet to 'other'
UPDATE payment_methods 
SET type = 'other' 
WHERE type IN ('bank_account', 'digital_wallet');

-- Step 2: Create new enum with only 4 types
CREATE TYPE payment_method_type_new AS ENUM (
  'credit_card',
  'debit_card',
  'cash',
  'other'
);

-- Step 3: Alter the column to use the new type
-- First convert to text, then to new enum
ALTER TABLE payment_methods 
  ALTER COLUMN type TYPE TEXT;

ALTER TABLE payment_methods 
  ALTER COLUMN type TYPE payment_method_type_new 
  USING type::payment_method_type_new;

-- Step 4: Drop old enum and rename new one
DROP TYPE payment_method_type;
ALTER TYPE payment_method_type_new RENAME TO payment_method_type;
