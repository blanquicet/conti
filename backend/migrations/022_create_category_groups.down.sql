-- Restore old columns
ALTER TABLE categories ADD COLUMN icon VARCHAR(10);
ALTER TABLE categories ADD COLUMN category_group VARCHAR(100);

-- Restore category_group from category_groups
UPDATE categories c
SET category_group = cg.name
FROM category_groups cg
WHERE c.category_group_id = cg.id;

-- Drop foreign key and index
DROP INDEX IF EXISTS idx_categories_group;
ALTER TABLE categories DROP COLUMN category_group_id;

-- Drop category_groups table
DROP TABLE IF EXISTS category_groups CASCADE;
