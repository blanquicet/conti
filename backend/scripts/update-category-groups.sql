-- Update category_group field based on category names
-- This script assigns groups to existing categories that were migrated without groups
-- Based on GetDefaultCategoryGroups() in backend/internal/movements/types.go
--
-- Usage:
--   psql $DATABASE_URL -f scripts/update-category-groups.sql
--
-- Or with explicit connection:
--   PGPASSWORD=password psql -h localhost -U gastos -d gastos -f scripts/update-category-groups.sql

BEGIN;

-- Casa group
UPDATE categories 
SET category_group = 'Casa'
WHERE category_group IS NULL 
  AND name IN (
    'Casa - Gastos fijos',
    'Casa - Provisionar mes entrante',
    'Casa - Cositas para casa',
    'Casa - Imprevistos',
    'Kellys',
    'Mercado',
    'Regalos'
  );

-- Jose group
UPDATE categories 
SET category_group = 'Jose'
WHERE category_group IS NULL 
  AND name IN (
    'Jose - Vida cotidiana',
    'Jose - Gastos fijos',
    'Jose - Imprevistos'
  );

-- Caro group
UPDATE categories 
SET category_group = 'Caro'
WHERE category_group IS NULL 
  AND name IN (
    'Caro - Vida cotidiana',
    'Caro - Gastos fijos',
    'Caro - Imprevistos'
  );

-- Carro group
UPDATE categories 
SET category_group = 'Carro'
WHERE category_group IS NULL 
  AND name IN (
    'Uber/Gasolina/Peajes/Parqueaderos',
    'Pago de SOAT/impuestos/mantenimiento',
    'Carro - Seguro',
    'Carro - Imprevistos'
  );

-- Ahorros group
UPDATE categories 
SET category_group = 'Ahorros'
WHERE category_group IS NULL 
  AND name IN (
    'Ahorros para SOAT/impuestos/mantenimiento',
    'Ahorros para cosas de la casa',
    'Ahorros para vacaciones',
    'Ahorros para regalos'
  );

-- Inversiones group
UPDATE categories 
SET category_group = 'Inversiones'
WHERE category_group IS NULL 
  AND name IN (
    'Inversiones Caro',
    'Inversiones Jose',
    'Inversiones Juntos'
  );

-- Diversión group
UPDATE categories 
SET category_group = 'Diversión'
WHERE category_group IS NULL 
  AND name IN (
    'Vacaciones',
    'Salidas juntos'
  );

-- Update category_group_icon based on category_group
-- (This should be run after migration 022 has been applied)
UPDATE categories SET category_group_icon = '🏠' WHERE category_group = 'Casa';
UPDATE categories SET category_group_icon = '🤴🏾' WHERE category_group = 'Jose';
UPDATE categories SET category_group_icon = '👸' WHERE category_group = 'Caro';
UPDATE categories SET category_group_icon = '🏎️' WHERE category_group = 'Carro';
UPDATE categories SET category_group_icon = '🏦' WHERE category_group = 'Ahorros';
UPDATE categories SET category_group_icon = '📈' WHERE category_group = 'Inversiones';
UPDATE categories SET category_group_icon = '🎉' WHERE category_group = 'Diversión';
UPDATE categories SET category_group_icon = '📦' WHERE category_group = 'Otros' OR category_group IS NULL;

-- Show results
SELECT 
  category_group, 
  COUNT(*) as count,
  string_agg(name, ', ' ORDER BY name) as categories
FROM categories
GROUP BY category_group
ORDER BY 
  CASE category_group
    WHEN 'Casa' THEN 1
    WHEN 'Jose' THEN 2
    WHEN 'Caro' THEN 3
    WHEN 'Carro' THEN 4
    WHEN 'Ahorros' THEN 5
    WHEN 'Inversiones' THEN 6
    WHEN 'Diversión' THEN 7
    ELSE 999
  END;

COMMIT;
