-- Check movements for Prebby and Caro Test
SELECT 
  m.id,
  m.type,
  m.description,
  m.amount,
  m.payer_name,
  m.counterparty_name,
  m.movement_date
FROM movements m
WHERE m.household_id = '0743465f-7f5a-4762-ae84-5cfaab0150e8'
  AND (
    (m.payer_name LIKE '%Prebby%' OR m.payer_name LIKE '%Caro Test%')
    OR (m.counterparty_name LIKE '%Prebby%' OR m.counterparty_name LIKE '%Caro Test%')
  )
  AND EXTRACT(MONTH FROM m.movement_date) = EXTRACT(MONTH FROM CURRENT_DATE)
  AND EXTRACT(YEAR FROM m.movement_date) = EXTRACT(YEAR FROM CURRENT_DATE)
ORDER BY m.movement_date DESC;
