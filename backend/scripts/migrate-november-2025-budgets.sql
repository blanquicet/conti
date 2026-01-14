-- Script to migrate November 2025 budgets from Google Sheets
-- These are the budget values that were being tracked manually
--
-- Usage:
--   psql $DATABASE_URL -f scripts/migrate-november-2025-budgets.sql

BEGIN;

-- Get household ID for blanquicet@gmail.com
DO $$
DECLARE
    v_household_id UUID;
    v_month DATE := '2025-11-01';
BEGIN
    -- Get household ID
    SELECT hm.household_id INTO v_household_id
    FROM household_members hm
    JOIN users u ON u.id = hm.user_id
    WHERE u.email = 'blanquicet@gmail.com'
    LIMIT 1;

    IF v_household_id IS NULL THEN
        RAISE EXCEPTION 'Household not found for blanquicet@gmail.com';
    END IF;

    RAISE NOTICE 'Migrating November 2025 budgets for household %', v_household_id;

    -- Insert budgets using category names (only categories with budget > 0)
    -- The UPSERT will update if budget already exists for that month
    
    -- Carro group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 800000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Pago de SOAT/impuestos/mantenimiento'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 254000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Carro - Seguro'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 300000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Uber/Gasolina/Peajes/Parqueaderos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Casa group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 3809891.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Casa - Gastos fijos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 327000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Kellys'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 1000000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Mercado'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Ahorros group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 350175.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Ahorros para SOAT/impuestos/mantenimiento'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 1094331.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Ahorros para cosas de la casa'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 911942.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Ahorros para vacaciones'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 383333.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Ahorros para regalos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Diversión group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 800000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Salidas juntos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 11000000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Vacaciones'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Inversiones group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 1094331.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Inversiones Caro'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 1094331.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Inversiones Jose'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 1094331.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Inversiones Juntos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Caro group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 406800.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Caro - Gastos fijos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 500000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Caro - Vida cotidiana'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    -- Jose group
    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 7518200.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Jose - Gastos fijos'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    INSERT INTO monthly_budgets (household_id, category_id, month, amount, currency)
    SELECT v_household_id, c.id, v_month, 500000.00, 'COP'
    FROM categories c
    WHERE c.household_id = v_household_id AND c.name = 'Jose - Vida cotidiana'
    ON CONFLICT (household_id, category_id, month) 
    DO UPDATE SET amount = EXCLUDED.amount, updated_at = NOW();

    RAISE NOTICE 'November 2025 budgets migrated successfully';
END $$;

-- Show summary of migrated budgets
SELECT 
    cg.name as group_name,
    c.name as category_name,
    mb.amount,
    mb.currency,
    mb.month
FROM monthly_budgets mb
JOIN categories c ON c.id = mb.category_id
JOIN category_groups cg ON cg.id = c.category_group_id
WHERE mb.household_id = (
    SELECT hm.household_id 
    FROM household_members hm 
    JOIN users u ON u.id = hm.user_id 
    WHERE u.email = 'blanquicet@gmail.com' 
    LIMIT 1
)
AND mb.month = '2025-11-01'
ORDER BY cg.display_order, c.display_order, c.name;

-- Show total budget for November 2025
SELECT 
    TO_CHAR(SUM(mb.amount), 'FM999,999,999.00') as total_budget,
    COUNT(*) as categories_with_budget
FROM monthly_budgets mb
WHERE mb.household_id = (
    SELECT hm.household_id 
    FROM household_members hm 
    JOIN users u ON u.id = hm.user_id 
    WHERE u.email = 'blanquicet@gmail.com' 
    LIMIT 1
)
AND mb.month = '2025-11-01';

COMMIT;
