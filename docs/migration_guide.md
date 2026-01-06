# Guía de Migración: Google Sheets → PostgreSQL

## 📊 Estructura de Datos Actual

### CSV: Casita - Ingresos.csv

**Columnas:**
- `Fecha`: Fecha del ingreso (formato DD/MM/YYYY)
- `Valor`: Monto con formato colombiano (comas para miles)
- `A quién le entraron?`: Jose o Caro
- `Origen`: Tipo de ingreso
- `Concepto`: Descripción/nota del ingreso
- `Fuente`: Siempre "Manual"
- `Mes`: YYYY-MM
- `Semana`: YYYY-WXX

**Total registros:** 23 ingresos (diciembre 2025 - enero 2026)

## 🎯 Mapeo a PostgreSQL

### Tabla Destino: `income`

```sql
CREATE TABLE income (
    id UUID PRIMARY KEY,
    household_id UUID NOT NULL,
    member_id UUID NOT NULL,
    account_id UUID NOT NULL,
    type income_type NOT NULL,
    amount DECIMAL(15, 2) NOT NULL,
    description VARCHAR(255) NOT NULL,
    income_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
```

### Mapeo de Campos

| CSV Column | PostgreSQL Column | Transformación |
|------------|-------------------|----------------|
| `Fecha` | `income_date` | Convertir DD/MM/YYYY → YYYY-MM-DD |
| `Valor` | `amount` | Remover comas, convertir a DECIMAL |
| `A quién le entraron?` | `member_id` | Mapear nombre → UUID del usuario |
| `Origen` | `type` | Mapear a enum `income_type` |
| `Concepto` | `description` | Texto directo (vacío → usar tipo) |
| - | `household_id` | **CONFIGURAR**: UUID del hogar |
| - | `account_id` | **CONFIGURAR**: UUID de cuenta destino |

## 🔄 Mapeo de Tipos de Ingreso

### Tipos del CSV → income_type enum

| Valor CSV | Tipo PostgreSQL | Notas |
|-----------|-----------------|-------|
| `Sueldo` | `salary` | ✅ Match directo |
| `salary` | `salary` | ✅ Match directo |
| `savings_withdrawal` | `savings_withdrawal` | ✅ Match directo |
| `previous_balance` | `previous_balance` | ✅ Match directo |
| `adjustment` | `adjustment` | ✅ Match directo |
| `reimbursement` | `reimbursement` | ✅ Match directo |
| `Bolsillo` | `savings_withdrawal` | 💡 Conversión |
| `Sobrante del anterior` | `previous_balance` | 💡 Conversión |

### Tipos Disponibles en PostgreSQL

```sql
CREATE TYPE income_type AS ENUM (
    -- Real Income (aumenta patrimonio)
    'salary',              -- Sueldo mensual
    'bonus',               -- Bono, prima, aguinaldo
    'freelance',           -- Trabajo independiente
    'reimbursement',       -- Reembolso de gastos
    'gift',                -- Regalo en dinero
    'sale',                -- Venta de algo
    'other_income',        -- Otro ingreso real
    
    -- Internal Movements (no aumenta patrimonio)
    'savings_withdrawal',  -- Retiro de ahorros (bolsillos, CDT)
    'previous_balance',    -- Sobrante del mes anterior
    'debt_collection',     -- Cobro de deuda
    'account_transfer',    -- Transferencia entre cuentas
    'adjustment'           -- Ajuste contable
);
```

## 📝 Pasos de Migración

### 1. Preparar Información Base

Antes de migrar, necesitas obtener estos UUIDs de tu base de datos:

```sql
-- 1. ID de tu household
SELECT id, name FROM households;

-- 2. IDs de usuarios (Jose y Caro)
SELECT id, name, email FROM users;

-- 3. ID de cuenta destino (o crear una nueva)
SELECT id, name, type FROM accounts WHERE household_id = '<tu_household_id>';
```

### 2. Crear Cuenta si No Existe

Si no tienes una cuenta configurada:

```sql
-- Ejemplo: crear cuenta principal del hogar
INSERT INTO accounts (household_id, name, type, initial_balance)
VALUES (
    '<tu_household_id>',
    'Cuenta Principal',
    'checking',
    0
);
```

### 3. Ejecutar Script de Migración

Usa el script Python generado (ver siguiente sección).

## 🐍 Script de Migración Python

Ver archivo: `migrate_income.py`

### Uso:

```bash
# 1. Instalar dependencias
pip install psycopg2-binary python-dotenv

# 2. Configurar variables de entorno (.env)
DB_HOST=tu-servidor.postgres.database.azure.com
DB_NAME=gastos
DB_USER=tu_usuario
DB_PASSWORD=tu_password
DB_PORT=5432
HOUSEHOLD_ID=uuid-de-tu-hogar
JOSE_USER_ID=uuid-de-jose
CARO_USER_ID=uuid-de-caro
ACCOUNT_ID=uuid-de-cuenta-destino

# 3. Ejecutar migración
python migrate_income.py '/home/jose/Desktop/Casita - Ingresos.csv'
```

## ✅ Validación Post-Migración

```sql
-- Contar registros migrados
SELECT COUNT(*) FROM income;

-- Ver resumen por tipo
SELECT type, COUNT(*), SUM(amount) as total
FROM income
GROUP BY type
ORDER BY total DESC;

-- Ver ingresos por miembro
SELECT u.name, COUNT(*) as registros, SUM(i.amount) as total
FROM income i
JOIN users u ON i.member_id = u.id
GROUP BY u.name;

-- Ver ingresos por mes
SELECT 
    TO_CHAR(income_date, 'YYYY-MM') as mes,
    COUNT(*) as registros,
    SUM(amount) as total
FROM income
GROUP BY mes
ORDER BY mes;
```

## 🚨 Consideraciones Importantes

1. **Valores con "Bolsillo"**: En el CSV aparece "Bolsillo" como origen. Estos probablemente son `savings_withdrawal` (retiro de ahorros).

2. **Valores sin Concepto**: Algunos registros no tienen concepto. El script usa el tipo de ingreso como descripción por defecto.

3. **Fechas**: El CSV usa formato DD/MM/YYYY, el script convierte a formato ISO (YYYY-MM-DD).

4. **Decimales**: Los valores tienen comas para miles y punto para decimales. El script limpia estos formatos.

5. **Timezone**: Todas las fechas se insertan en UTC con hora 00:00:00.

## 📦 Próximos Pasos

Después de migrar ingresos:

1. ✅ Migrar **gastos/expenses**
2. ✅ Migrar **payment_methods** existentes
3. ✅ Revisar y corregir tipos de ingreso si es necesario
4. ✅ Configurar validaciones en el frontend
5. ✅ Deprecar Google Sheets gradualmente
