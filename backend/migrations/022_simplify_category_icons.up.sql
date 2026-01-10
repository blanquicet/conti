-- Remove individual category icon field (not used, groups have icons instead)
ALTER TABLE categories DROP COLUMN icon;

-- Add category_group_icon field to store the group's icon
ALTER TABLE categories ADD COLUMN category_group_icon VARCHAR(10);

-- Update existing categories with group icons based on category_group
UPDATE categories 
SET category_group_icon = '🏠' 
WHERE category_group = 'Casa';

UPDATE categories 
SET category_group_icon = '🤴🏾' 
WHERE category_group = 'Jose';

UPDATE categories 
SET category_group_icon = '👸' 
WHERE category_group = 'Caro';

UPDATE categories 
SET category_group_icon = '🏎️' 
WHERE category_group = 'Carro';

UPDATE categories 
SET category_group_icon = '🏦' 
WHERE category_group = 'Ahorros';

UPDATE categories 
SET category_group_icon = '📈' 
WHERE category_group = 'Inversiones';

UPDATE categories 
SET category_group_icon = '🎉' 
WHERE category_group = 'Diversión';

UPDATE categories 
SET category_group_icon = '📦' 
WHERE category_group = 'Otros' OR category_group IS NULL;

-- Add comment
COMMENT ON COLUMN categories.category_group_icon IS 'Emoji icon for the category group (e.g., 🏠 for Casa, 🤴🏾 for Jose)';
