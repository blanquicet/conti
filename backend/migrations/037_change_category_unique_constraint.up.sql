-- Change unique constraint from (household_id, name) to (household_id, category_group_id, name)
-- This allows categories with the same name in different groups within the same household

-- Drop old constraint
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_household_id_name_key;

-- Add new constraint: unique per group within household
ALTER TABLE categories ADD CONSTRAINT categories_household_group_name_key 
  UNIQUE (household_id, category_group_id, name);
