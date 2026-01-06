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

## Archivos

- `migrate_income.py` - Script de migración de ingresos
- `.env.example` - Plantilla de configuración
- `requirements.txt` - Dependencias Python
- `README.md` - Esta guía

## Ver también

- [Guía de migración completa](../../docs/migration_guide.md)
