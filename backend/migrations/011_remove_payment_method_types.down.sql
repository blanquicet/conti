-- Restore bank_account and digital_wallet to payment_method_type enum

-- Step 1: Create new enum with 6 types
CREATE TYPE payment_method_type_new AS ENUM (
  'credit_card',
  'debit_card',
  'bank_account',
  'cash',
  'digital_wallet',
  'other'
);

-- Step 2: Alter the column to use the new type
ALTER TABLE payment_methods 
  ALTER COLUMN type TYPE TEXT;

ALTER TABLE payment_methods 
  ALTER COLUMN type TYPE payment_method_type_new 
  USING type::payment_method_type_new;

-- Step 3: Drop old enum and rename new one
DROP TYPE payment_method_type;
ALTER TYPE payment_method_type_new RENAME TO payment_method_type;
