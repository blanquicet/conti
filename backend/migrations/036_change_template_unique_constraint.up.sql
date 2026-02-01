-- Change unique constraint from (household_id, name) to (household_id, category_id, name)
-- This allows the same template name in different categories

-- Drop existing constraint
ALTER TABLE recurring_movement_templates 
DROP CONSTRAINT recurring_movement_templates_household_id_name_key;

-- Add new constraint that includes category_id
ALTER TABLE recurring_movement_templates 
ADD CONSTRAINT recurring_movement_templates_household_category_name_key 
UNIQUE (household_id, category_id, name);
