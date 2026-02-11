-- Revert to original constraint (household_id, name)
-- WARNING: This will fail if there are duplicate names across groups

-- Drop new constraint
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_household_group_name_key;

-- Restore old constraint
ALTER TABLE categories ADD CONSTRAINT categories_household_id_name_key 
  UNIQUE (household_id, name);
