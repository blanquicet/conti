# Scripts de Migración

Este directorio contiene scripts para migrar datos desde Google Sheets a PostgreSQL.

## Migración de Ingresos

### 1. Configuración

```bash
# Copiar archivo de ejemplo
cp .env.example .env

# Editar .env con tus credenciales y UUIDs
nano .env
```

### 2. Obtener UUIDs necesarios

Conecta a tu base de datos y ejecuta:

```sql
-- ID de tu household
SELECT id, name FROM households;

-- IDs de usuarios
SELECT id, name, email FROM users;

-- ID de cuenta destino (o crear una nueva)
SELECT id, name, type FROM accounts WHERE household_id = '<tu_household_id>';
```

### 3. Instalar dependencias

```bash
pip install -r requirements.txt
```

### 4. Ejecutar migración

```bash
python migrate_income.py '/ruta/a/tu/Casita - Ingresos.csv'
```

---

## Migración de Movimientos (Conti)

### 1. Configuración

Ya tienes el archivo `.env.movements` con todos los IDs necesarios para producción:

```bash
# Usar el archivo de configuración de movimientos
cp .env.movements .env
```

### 2. Dry-run (Validación)

**SIEMPRE ejecuta primero en modo dry-run** para validar los datos:

```bash
python migrate_movements.py \
  '/home/jose/Desktop/Casita - Conti.csv' \
  '/home/jose/Desktop/Casita - GastoParticipantes.csv' \
  --dry-run
```

El dry-run mostrará:
- Total de movimientos a migrar
- Desglose por tipo (HOUSEHOLD, SPLIT, DEBT_PAYMENT)
- Top 10 categorías
- Monto total
- Rango de fechas
- Errores y advertencias

### 3. Ejecutar migración real

Una vez validado con dry-run, ejecuta la migración:

```bash
python migrate_movements.py \
  '/home/jose/Desktop/Casita - Conti.csv' \
  '/home/jose/Desktop/Casita - GastoParticipantes.csv'
```

El script pedirá confirmación antes de insertar.

### 4. Validación post-migración

```sql
-- Contar movimientos migrados
SELECT COUNT(*) FROM movements;

-- Ver resumen por tipo
SELECT type, COUNT(*), SUM(amount) as total
FROM movements
GROUP BY type
ORDER BY type;

-- Ver movimientos SPLIT con participantes
SELECT m.id, m.description, COUNT(mp.id) as participant_count
FROM movements m
LEFT JOIN movement_participants mp ON m.id = mp.movement_id
WHERE m.type = 'SPLIT'
GROUP BY m.id, m.description;

-- Verificar que participantes suman 100%
SELECT movement_id, SUM(percentage) as total_pct
FROM movement_participants
GROUP BY movement_id
HAVING SUM(percentage) NOT BETWEEN 0.9999 AND 1.0001;
```

### Notas importantes

**Mapeos de datos:**
- `FAMILIAR` (CSV) → `HOUSEHOLD` (PostgreSQL)
- `COMPARTIDO` (CSV) → `SPLIT` (PostgreSQL)
- `PAGO_DEUDA` (CSV) → `DEBT_PAYMENT` (PostgreSQL)

**Para movimientos HOUSEHOLD:**
- El pagador se infiere del método de pago (ej: "Débito Jose" → Jose)
- Categoría y método de pago son requeridos

**Para movimientos SPLIT:**
- Requiere participantes en `GastoParticipantes.csv`
- Los porcentajes deben sumar 100%
- El pagador se toma del campo `Pagador` del CSV

**Para movimientos DEBT_PAYMENT:**
- Requiere pagador y contraparte
- Categoría es requerida si el pagador es un household member

## Archivos

- `migrate_income.py` - Script de migración de ingresos
- `migrate_movements.py` - Script de migración de movimientos
- `.env.example` - Plantilla de configuración (para income)
- `.env.movements` - Configuración completa para migración de movimientos (PROD)
- `requirements.txt` - Dependencias Python
- `README.md` - Esta guía

## Ver también

- [Guía de migración completa](../../docs/migration_guide.md)
- [Diseño de Phase 5: Movements](../../docs/design/05_MOVEMENTS_PHASE.md)
