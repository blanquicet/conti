-- Restore individual icon field
ALTER TABLE categories ADD COLUMN icon VARCHAR(10);

-- Remove category_group_icon field
ALTER TABLE categories DROP COLUMN category_group_icon;
