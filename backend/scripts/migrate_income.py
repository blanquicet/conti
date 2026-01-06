#!/usr/bin/env python3
"""
Script de migración: Google Sheets CSV → PostgreSQL (tabla income)

Uso:
    python migrate_income.py <ruta_al_csv>

Ejemplo:
    python migrate_income.py '/home/jose/Desktop/Casita - Ingresos.csv'
"""

import csv
import sys
import os
from datetime import datetime
from decimal import Decimal
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

# Cargar variables de entorno
load_dotenv()

# Configuración de base de datos
DB_CONFIG = {
    'host': os.getenv('DB_HOST'),
    'database': os.getenv('DB_NAME'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'port': os.getenv('DB_PORT', 5432),
}

# IDs de configuración (obtener de la base de datos primero)
HOUSEHOLD_ID = os.getenv('HOUSEHOLD_ID')
JOSE_USER_ID = os.getenv('JOSE_USER_ID')
CARO_USER_ID = os.getenv('CARO_USER_ID')
JOSE_ACCOUNT_ID = os.getenv('JOSE_ACCOUNT_ID')
CARO_ACCOUNT_ID = os.getenv('CARO_ACCOUNT_ID')

# Mapeo de nombres a UUIDs
USER_MAPPING = {
    'Jose': JOSE_USER_ID,
    'Caro': CARO_USER_ID,
}

# Mapeo de nombres a cuentas
ACCOUNT_MAPPING = {
    'Jose': JOSE_ACCOUNT_ID,
    'Caro': CARO_ACCOUNT_ID,
}

# Mapeo de tipos de ingreso del CSV a PostgreSQL enum
TYPE_MAPPING = {
    'Sueldo': 'salary',
    'salary': 'salary',
    'savings_withdrawal': 'savings_withdrawal',
    'previous_balance': 'previous_balance',
    'adjustment': 'adjustment',
    'reimbursement': 'reimbursement',
    'Bolsillo': 'savings_withdrawal',  # Conversión
    'Sobrante del anterior': 'previous_balance',  # Conversión
}


def clean_amount(value_str):
    """
    Limpia el formato de monto colombiano a Decimal.
    Ejemplo: "1,094,330.00" -> Decimal('1094330.00')
    """
    # Remover comas
    cleaned = value_str.replace(',', '').replace('"', '').strip()
    return Decimal(cleaned)


def parse_date(date_str):
    """
    Convierte fecha DD/MM/YYYY a YYYY-MM-DD.
    Ejemplo: "01/12/2025" -> "2025-12-01"
    """
    dt = datetime.strptime(date_str, '%d/%m/%Y')
    return dt.strftime('%Y-%m-%d')


def map_income_type(origen):
    """
    Mapea el valor del CSV 'Origen' al enum income_type de PostgreSQL.
    """
    income_type = TYPE_MAPPING.get(origen)
    if not income_type:
        print(f"⚠️  WARNING: Tipo de ingreso desconocido '{origen}', usando 'other_income'")
        return 'other_income'
    return income_type


def validate_config():
    """Valida que todas las variables de configuración estén presentes."""
    missing = []
    
    if not HOUSEHOLD_ID:
        missing.append('HOUSEHOLD_ID')
    if not JOSE_USER_ID:
        missing.append('JOSE_USER_ID')
    if not CARO_USER_ID:
        missing.append('CARO_USER_ID')
    if not JOSE_ACCOUNT_ID:
        missing.append('JOSE_ACCOUNT_ID')
    if not CARO_ACCOUNT_ID:
        missing.append('CARO_ACCOUNT_ID')
    if not DB_CONFIG['host']:
        missing.append('DB_HOST')
    if not DB_CONFIG['database']:
        missing.append('DB_NAME')
    if not DB_CONFIG['user']:
        missing.append('DB_USER')
    if not DB_CONFIG['password']:
        missing.append('DB_PASSWORD')
    
    if missing:
        print("❌ ERROR: Faltan variables de entorno:")
        for var in missing:
            print(f"   - {var}")
        print("\nConfigura estas variables en un archivo .env o en el entorno.")
        sys.exit(1)


def read_csv(filepath):
    """Lee el CSV y retorna lista de registros procesados."""
    records = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for i, row in enumerate(reader, start=2):  # Start at 2 (header is line 1)
            try:
                # Parsear campos
                income_date = parse_date(row['Fecha'])
                amount = clean_amount(row['Valor'])
                member_name = row['A quién le entraron?'].strip()
                origen = row['Origen'].strip()
                concepto = row['Concepto'].strip()
                
                # Validar member
                member_id = USER_MAPPING.get(member_name)
                if not member_id:
                    print(f"⚠️  WARNING línea {i}: Usuario desconocido '{member_name}', saltando...")
                    continue
                
                # Obtener cuenta correspondiente al miembro
                account_id = ACCOUNT_MAPPING.get(member_name)
                if not account_id:
                    print(f"⚠️  WARNING línea {i}: Cuenta no encontrada para '{member_name}', saltando...")
                    continue
                
                # Mapear tipo
                income_type = map_income_type(origen)
                
                # Descripción: usar concepto o tipo como fallback
                description = concepto if concepto else f"{income_type} - {member_name}"
                
                # Preparar registro
                record = {
                    'household_id': HOUSEHOLD_ID,
                    'member_id': member_id,
                    'account_id': account_id,
                    'type': income_type,
                    'amount': amount,
                    'description': description,
                    'income_date': income_date,
                }
                
                records.append(record)
                
            except Exception as e:
                print(f"❌ ERROR procesando línea {i}: {e}")
                print(f"   Datos: {row}")
                continue
    
    return records


def insert_records(records):
    """Inserta registros en PostgreSQL."""
    if not records:
        print("⚠️  No hay registros para insertar")
        return
    
    conn = None
    try:
        # Conectar a la base de datos
        print(f"📡 Conectando a {DB_CONFIG['host']}...")
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        
        # Preparar datos para inserción
        values = [
            (
                r['household_id'],
                r['member_id'],
                r['account_id'],
                r['type'],
                r['amount'],
                r['description'],
                r['income_date'],
            )
            for r in records
        ]
        
        # Insertar con execute_values (más eficiente)
        insert_query = """
            INSERT INTO income (
                household_id,
                member_id,
                account_id,
                type,
                amount,
                description,
                income_date
            ) VALUES %s
        """
        
        print(f"💾 Insertando {len(records)} registros...")
        execute_values(cur, insert_query, values)
        
        # Commit
        conn.commit()
        print(f"✅ Migración exitosa: {len(records)} registros insertados")
        
        # Mostrar resumen
        cur.execute("""
            SELECT type, COUNT(*), SUM(amount)
            FROM income
            WHERE household_id = %s
            GROUP BY type
            ORDER BY SUM(amount) DESC
        """, (HOUSEHOLD_ID,))
        
        print("\n📊 Resumen por tipo de ingreso:")
        print(f"{'Tipo':<25} {'Cantidad':<10} {'Total':>15}")
        print("-" * 52)
        for row in cur.fetchall():
            income_type, count, total = row
            print(f"{income_type:<25} {count:<10} ${total:>14,.2f}")
        
    except psycopg2.Error as e:
        print(f"❌ Error de base de datos: {e}")
        if conn:
            conn.rollback()
        sys.exit(1)
    
    finally:
        if conn:
            conn.close()


def main():
    """Función principal."""
    print("🚀 Migración de Ingresos: Google Sheets → PostgreSQL\n")
    
    # Validar argumentos
    if len(sys.argv) != 2:
        print("Uso: python migrate_income.py <ruta_al_csv>")
        print("Ejemplo: python migrate_income.py '/home/jose/Desktop/Casita - Ingresos.csv'")
        sys.exit(1)
    
    csv_path = sys.argv[1]
    
    # Validar archivo
    if not os.path.exists(csv_path):
        print(f"❌ ERROR: Archivo no encontrado: {csv_path}")
        sys.exit(1)
    
    # Validar configuración
    validate_config()
    
    # Leer CSV
    print(f"📖 Leyendo {csv_path}...")
    records = read_csv(csv_path)
    print(f"✅ Leídos {len(records)} registros válidos\n")
    
    # Confirmar antes de insertar
    print(f"⚠️  Estás a punto de insertar {len(records)} registros en la base de datos.")
    print(f"   Base de datos: {DB_CONFIG['host']}/{DB_CONFIG['database']}")
    print(f"   Household ID: {HOUSEHOLD_ID}")
    print(f"   Jose Account ID: {JOSE_ACCOUNT_ID}")
    print(f"   Caro Account ID: {CARO_ACCOUNT_ID}")
    
    response = input("\n¿Continuar? (s/N): ").strip().lower()
    if response != 's':
        print("❌ Migración cancelada")
        sys.exit(0)
    
    # Insertar registros
    insert_records(records)
    
    print("\n🎉 ¡Migración completada!")


if __name__ == '__main__':
    main()
