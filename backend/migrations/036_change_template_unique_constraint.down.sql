-- Revert: change unique constraint back to (household_id, name)

-- Drop the new constraint
ALTER TABLE recurring_movement_templates 
DROP CONSTRAINT recurring_movement_templates_household_category_name_key;

-- Add back original constraint
ALTER TABLE recurring_movement_templates 
ADD CONSTRAINT recurring_movement_templates_household_id_name_key 
UNIQUE (household_id, name);
