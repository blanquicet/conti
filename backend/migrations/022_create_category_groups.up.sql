-- Create category_groups table for customizable category grouping per household
CREATE TABLE category_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    
    -- Group info
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(10), -- Emoji or icon identifier
    
    -- UI metadata
    display_order INT NOT NULL DEFAULT 0,
    
    -- Lifecycle
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraints
    UNIQUE(household_id, name),
    CHECK (name != '')
);

-- Indexes
CREATE INDEX idx_category_groups_household ON category_groups(household_id);
CREATE INDEX idx_category_groups_household_active ON category_groups(household_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_category_groups_display_order ON category_groups(household_id, display_order);

-- Comments
COMMENT ON TABLE category_groups IS 'Customizable category groups per household (Casa, Jose, Caro, etc.)';
COMMENT ON COLUMN category_groups.icon IS 'Emoji or icon identifier for the group (e.g., 🏠, 🤴🏾, 👸)';
COMMENT ON COLUMN category_groups.display_order IS 'Order for displaying groups in UI (lower numbers first)';

-- Migrate existing category groups from categories table to category_groups
-- Create groups based on existing category_group values
INSERT INTO category_groups (household_id, name, icon, display_order)
SELECT DISTINCT
    c.household_id,
    c.category_group,
    CASE c.category_group
        WHEN 'Casa' THEN '🏠'
        WHEN 'Jose' THEN '🤴🏾'
        WHEN 'Caro' THEN '👸'
        WHEN 'Carro' THEN '🏎️'
        WHEN 'Ahorros' THEN '🏦'
        WHEN 'Inversiones' THEN '📈'
        WHEN 'Diversión' THEN '🎉'
        ELSE '📦'
    END as icon,
    CASE c.category_group
        WHEN 'Casa' THEN 1
        WHEN 'Jose' THEN 2
        WHEN 'Caro' THEN 3
        WHEN 'Carro' THEN 4
        WHEN 'Ahorros' THEN 5
        WHEN 'Inversiones' THEN 6
        WHEN 'Diversión' THEN 7
        ELSE 999
    END as display_order
FROM categories c
WHERE c.category_group IS NOT NULL;

-- Create "Otros" group for categories without a group
INSERT INTO category_groups (household_id, name, icon, display_order)
SELECT DISTINCT
    c.household_id,
    'Otros',
    '📦',
    999
FROM categories c
WHERE c.category_group IS NULL
ON CONFLICT (household_id, name) DO NOTHING;

-- Add foreign key column to categories
ALTER TABLE categories ADD COLUMN category_group_id UUID REFERENCES category_groups(id) ON DELETE SET NULL;

-- Update categories to reference category_groups
UPDATE categories c
SET category_group_id = cg.id
FROM category_groups cg
WHERE c.household_id = cg.household_id
  AND c.category_group = cg.name;

-- Update categories without a group to reference "Otros"
UPDATE categories c
SET category_group_id = cg.id
FROM category_groups cg
WHERE c.household_id = cg.household_id
  AND cg.name = 'Otros'
  AND c.category_group IS NULL;

-- Drop old columns (icon was never used, category_group is now replaced by category_group_id)
ALTER TABLE categories DROP COLUMN icon;
ALTER TABLE categories DROP COLUMN category_group;

-- Add index for the new foreign key
CREATE INDEX idx_categories_group ON categories(category_group_id);

-- Add comment
COMMENT ON COLUMN categories.category_group_id IS 'Reference to category group (customizable per household)';
