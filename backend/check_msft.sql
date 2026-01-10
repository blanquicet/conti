-- Check MSFT movement participants
SELECT 
  m.id,
  m.description,
  m.amount,
  m.payer_name,
  p.participant_name,
  p.percentage
FROM movements m
LEFT JOIN participants p ON p.movement_id = m.id
WHERE m.description = 'MSFT'
  AND EXTRACT(MONTH FROM m.movement_date) = 1
  AND EXTRACT(YEAR FROM m.movement_date) = 2026;
