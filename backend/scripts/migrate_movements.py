#!/usr/bin/env python3
"""
Script de migración: Google Sheets CSV → PostgreSQL (tabla movements + movement_participants)

Uso:
    python migrate_movements.py <gastos_csv> <participantes_csv> [--dry-run]

Ejemplo:
    python migrate_movements.py '/home/jose/Desktop/Casita - Gastos.csv' '/home/jose/Desktop/Casita - GastoParticipantes.csv' --dry-run
    python migrate_movements.py '/home/jose/Desktop/Casita - Gastos.csv' '/home/jose/Desktop/Casita - GastoParticipantes.csv'
"""

import csv
import sys
import os
from datetime import datetime
from decimal import Decimal
import uuid
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv
from collections import defaultdict

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

# IDs de configuración
HOUSEHOLD_ID = os.getenv('HOUSEHOLD_ID')

# Mapeo de nombres a UUIDs de usuarios
USER_MAPPING = {
    'Jose': os.getenv('JOSE_USER_ID'),
    'Caro': os.getenv('CARO_USER_ID'),
}

# Mapeo de nombres a UUIDs de contactos
CONTACT_MAPPING = {
    'Daniel': os.getenv('DANIEL_CONTACT_ID'),
    'Kelly Carolina': os.getenv('KELLY_CONTACT_ID'),
    'Mamá Caro': os.getenv('MAMA_CARO_CONTACT_ID'),
    'Mamá Jose': os.getenv('MAMA_JOSE_CONTACT_ID'),
    'Maria Isabel': os.getenv('MARIA_ISABEL_CONTACT_ID'),
    'Papá Caro': os.getenv('PAPA_CARO_CONTACT_ID'),
    'Papá Jose': os.getenv('PAPA_JOSE_CONTACT_ID'),
    'Prebby': os.getenv('PREBBY_CONTACT_ID'),
    'Prima Diana': os.getenv('PRIMA_DIANA_CONTACT_ID'),
    'Diana': os.getenv('PRIMA_DIANA_CONTACT_ID'),  # Alias
    'Primo Juanda': os.getenv('PRIMO_JUANDA_CONTACT_ID'),
    'Tía Elodia': os.getenv('TIA_ELODIA_CONTACT_ID'),
    'Tia Elodia': os.getenv('TIA_ELODIA_CONTACT_ID'),  # Alias sin acento
    'Yury': os.getenv('YURY_CONTACT_ID'),
}

# Mapeo de nombres de métodos de pago a UUIDs
PAYMENT_METHOD_MAPPING = {
    'AMEX Jose': os.getenv('AMEX_JOSE_ID'),
    'Débito Caro': os.getenv('DEBITO_CARO_ID'),
    'Débito Jose': os.getenv('DEBITO_JOSE_ID'),
    'MasterCard Oro Jose': os.getenv('MASTERCARD_JOSE_ID'),
    'Nu Caro': os.getenv('NU_CARO_ID'),
}

# Mapeo de métodos de pago a sus owners (para inferir pagador en FAMILIAR)
PAYMENT_METHOD_OWNERS = {
    'AMEX Jose': 'Jose',
    'Débito Caro': 'Caro',
    'Débito Jose': 'Jose',
    'MasterCard Oro Jose': 'Jose',
    'Nu Caro': 'Caro',
}

# Mapeo de tipos de movimiento CSV → PostgreSQL
TYPE_MAPPING = {
    'FAMILIAR': 'HOUSEHOLD',
    'COMPARTIDO': 'SPLIT',
    'PAGO_DEUDA': 'DEBT_PAYMENT',
}


def clean_amount(value_str):
    """
    Limpia el formato de monto colombiano a Decimal.
    Ejemplo: "1,094,330.00" -> Decimal('1094330.00')
    """
    cleaned = value_str.replace(',', '').replace('"', '').strip()
    return Decimal(cleaned)


def parse_date(date_str):
    """
    Convierte fecha DD/MM/YYYY a YYYY-MM-DD.
    Ejemplo: "01/12/2025" -> "2025-12-01"
    """
    dt = datetime.strptime(date_str, '%d/%m/%Y')
    return dt.strftime('%Y-%m-%d')


def parse_percentage(pct_str):
    """
    Convierte porcentaje string a decimal 0-1.
    Ejemplo: "50.00%" -> 0.5
    """
    cleaned = pct_str.replace('%', '').strip()
    return Decimal(cleaned) / Decimal('100')


def resolve_person(name):
    """
    Resuelve un nombre de persona a (user_id, contact_id).
    Retorna (user_id, None) si es usuario o (None, contact_id) si es contacto.
    """
    name = name.strip()
    
    # Buscar en usuarios primero
    if name in USER_MAPPING:
        user_id = USER_MAPPING[name]
        if user_id:
            return (user_id, None)
    
    # Buscar en contactos
    if name in CONTACT_MAPPING:
        contact_id = CONTACT_MAPPING[name]
        if contact_id:
            return (None, contact_id)
    
    return (None, None)


def validate_config():
    """Valida que todas las variables de configuración estén presentes."""
    missing = []
    
    if not HOUSEHOLD_ID:
        missing.append('HOUSEHOLD_ID')
    if not USER_MAPPING['Jose']:
        missing.append('JOSE_USER_ID')
    if not USER_MAPPING['Caro']:
        missing.append('CARO_USER_ID')
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


def generate_id_mapping(gastos_filepath):
    """Generate a consistent UUID mapping for all movement IDs in CSV."""
    id_mapping = {}
    
    with open(gastos_filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            movement_id_csv = row['ID_Gasto'].strip()
            
            # Check if it's already a valid UUID
            try:
                uuid.UUID(movement_id_csv)
                # It's already a UUID, use as-is
                id_mapping[movement_id_csv] = movement_id_csv
            except ValueError:
                # Not a valid UUID, generate one deterministically
                if movement_id_csv not in id_mapping:
                    id_mapping[movement_id_csv] = str(uuid.uuid4())
    
    return id_mapping


def read_participants_csv(filepath, id_mapping):
    """Lee el CSV de participantes y retorna un dict: movement_uuid -> [(person, percentage), ...]"""
    participants_map = defaultdict(list)
    
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for i, row in enumerate(reader, start=2):
            try:
                movement_id_csv = row['ID_Gasto'].strip()
                # Map CSV ID to UUID
                movement_id_uuid = id_mapping.get(movement_id_csv, movement_id_csv)
                
                person = row['Persona'].strip()
                percentage = parse_percentage(row['Porcentaje'])
                
                participants_map[movement_id_uuid].append((person, percentage))
                
            except Exception as e:
                print(f"⚠️  WARNING línea {i} en GastoParticipantes: {e}")
                continue
    
    return participants_map


def read_movements_csv(gastos_filepath, participants_map, id_mapping):
    """Lee el CSV de gastos y retorna lista de registros procesados."""
    records = []
    warnings = []
    errors = []
    
    with open(gastos_filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for i, row in enumerate(reader, start=2):
            try:
                # Parsear campos comunes
                movement_id_csv = row['ID_Gasto'].strip()
                
                # Use the pre-generated UUID mapping
                movement_id = id_mapping.get(movement_id_csv, movement_id_csv)
                
                fecha = parse_date(row['Fecha'])
                tipo_csv = row['Tipo de gasto'].strip()
                valor = clean_amount(row['Valor'])
                categoria = row['Categoría'].strip() or None
                descripcion = row['Descripción'].strip()
                medio_pago = row['Medio de pago'].strip()
                pagador_csv = row['Pagador'].strip()
                contraparte_csv = row['Contraparte'].strip()
                
                # Mapear tipo
                tipo_pg = TYPE_MAPPING.get(tipo_csv)
                if not tipo_pg:
                    errors.append(f"Línea {i}: Tipo desconocido '{tipo_csv}'")
                    continue
                
                # Determinar payer
                payer_user_id = None
                payer_contact_id = None
                payment_method_id = None
                
                if tipo_pg == 'HOUSEHOLD':
                    # Para FAMILIAR, inferir pagador del método de pago
                    if not medio_pago:
                        errors.append(f"Línea {i}: FAMILIAR sin medio de pago")
                        continue
                    
                    # Limpiar nombre del medio de pago (quitar espacios)
                    medio_pago_clean = medio_pago.strip()
                    
                    # Obtener owner del método de pago
                    payer_name = PAYMENT_METHOD_OWNERS.get(medio_pago_clean)
                    if not payer_name:
                        errors.append(f"Línea {i}: Método de pago desconocido '{medio_pago_clean}'")
                        continue
                    
                    # Resolver payer
                    payer_user_id, payer_contact_id = resolve_person(payer_name)
                    if not payer_user_id and not payer_contact_id:
                        errors.append(f"Línea {i}: Pagador '{payer_name}' no encontrado")
                        continue
                    
                    # Obtener payment method ID
                    payment_method_id = PAYMENT_METHOD_MAPPING.get(medio_pago_clean)
                    if not payment_method_id:
                        errors.append(f"Línea {i}: Payment method ID no encontrado para '{medio_pago_clean}'")
                        continue
                    
                    # Validar categoría requerida
                    if not categoria:
                        errors.append(f"Línea {i}: HOUSEHOLD requiere categoría")
                        continue
                
                elif tipo_pg == 'SPLIT':
                    # Para COMPARTIDO, obtener pagador del CSV
                    if not pagador_csv:
                        errors.append(f"Línea {i}: SPLIT sin pagador")
                        continue
                    
                    payer_user_id, payer_contact_id = resolve_person(pagador_csv)
                    if not payer_user_id and not payer_contact_id:
                        errors.append(f"Línea {i}: Pagador '{pagador_csv}' no encontrado")
                        continue
                    
                    # Payment method es opcional para SPLIT
                    if medio_pago:
                        medio_pago_clean = medio_pago.strip()
                        payment_method_id = PAYMENT_METHOD_MAPPING.get(medio_pago_clean)
                    
                    # Validar participantes
                    if movement_id not in participants_map:
                        errors.append(f"Línea {i}: SPLIT sin participantes en GastoParticipantes.csv (ID: {movement_id_csv})")
                        continue
                    
                    # Validar porcentajes suman 100%
                    total_pct = sum(pct for _, pct in participants_map[movement_id])
                    if not (Decimal('0.9999') <= total_pct <= Decimal('1.0001')):
                        errors.append(f"Línea {i}: Participantes no suman 100% (suma: {total_pct*100}%)")
                        continue
                
                elif tipo_pg == 'DEBT_PAYMENT':
                    # Para PAGO_DEUDA, obtener pagador y contraparte
                    if not pagador_csv:
                        errors.append(f"Línea {i}: DEBT_PAYMENT sin pagador")
                        continue
                    if not contraparte_csv:
                        errors.append(f"Línea {i}: DEBT_PAYMENT sin contraparte")
                        continue
                    
                    payer_user_id, payer_contact_id = resolve_person(pagador_csv)
                    if not payer_user_id and not payer_contact_id:
                        errors.append(f"Línea {i}: Pagador '{pagador_csv}' no encontrado")
                        continue
                    
                    # Payment method opcional para DEBT_PAYMENT
                    if medio_pago:
                        medio_pago_clean = medio_pago.strip()
                        payment_method_id = PAYMENT_METHOD_MAPPING.get(medio_pago_clean)
                
                # Construir registro
                record = {
                    'id': movement_id,
                    'household_id': HOUSEHOLD_ID,
                    'type': tipo_pg,
                    'description': descripcion,
                    'amount': valor,
                    'category': categoria,
                    'movement_date': fecha,
                    'currency': 'COP',
                    'payer_user_id': payer_user_id,
                    'payer_contact_id': payer_contact_id,
                    'payment_method_id': payment_method_id,
                    'counterparty_user_id': None,
                    'counterparty_contact_id': None,
                    'participants': [],
                }
                
                # Agregar contraparte para DEBT_PAYMENT
                if tipo_pg == 'DEBT_PAYMENT':
                    counterparty_user_id, counterparty_contact_id = resolve_person(contraparte_csv)
                    if not counterparty_user_id and not counterparty_contact_id:
                        errors.append(f"Línea {i}: Contraparte '{contraparte_csv}' no encontrada")
                        continue
                    record['counterparty_user_id'] = counterparty_user_id
                    record['counterparty_contact_id'] = counterparty_contact_id
                
                # Agregar participantes para SPLIT
                if tipo_pg == 'SPLIT':
                    for person_name, percentage in participants_map[movement_id]:
                        participant_user_id, participant_contact_id = resolve_person(person_name)
                        if not participant_user_id and not participant_contact_id:
                            errors.append(f"Línea {i}: Participante '{person_name}' no encontrado")
                            continue
                        
                        record['participants'].append({
                            'participant_user_id': participant_user_id,
                            'participant_contact_id': participant_contact_id,
                            'percentage': percentage,
                        })
                
                records.append(record)
                
            except Exception as e:
                errors.append(f"Línea {i}: Error procesando: {e}")
                continue
    
    return records, warnings, errors


def print_dry_run_summary(records):
    """Imprime resumen de dry-run."""
    print("\n" + "="*80)
    print("DRY RUN - RESUMEN DE MIGRACIÓN")
    print("="*80)
    
    print(f"\n📊 Total de movimientos a migrar: {len(records)}")
    
    # Por tipo
    by_type = defaultdict(int)
    for r in records:
        by_type[r['type']] += 1
    
    print("\nPor tipo:")
    for tipo, count in sorted(by_type.items()):
        print(f"  {tipo}: {count}")
    
    # Por categoría (top 10)
    by_category = defaultdict(int)
    for r in records:
        if r['category']:
            by_category[r['category']] += 1
    
    print("\nTop 10 categorías:")
    for cat, count in sorted(by_category.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"  {cat}: {count}")
    
    # Total amount
    total = sum(r['amount'] for r in records)
    print(f"\n💰 Monto total: ${total:,.2f} COP")
    
    # Fechas
    dates = [r['movement_date'] for r in records]
    print(f"\n📅 Rango de fechas: {min(dates)} a {max(dates)}")
    
    # Participantes en SPLIT
    split_count = sum(1 for r in records if r['type'] == 'SPLIT')
    total_participants = sum(len(r['participants']) for r in records if r['type'] == 'SPLIT')
    if split_count > 0:
        print(f"\n👥 Movimientos SPLIT: {split_count} con {total_participants} participantes totales")
    
    print("\n" + "="*80)
    print("Para proceder con la migración, ejecuta sin --dry-run")
    print("="*80 + "\n")


def insert_records(records, dry_run=False):
    """Inserta registros en PostgreSQL."""
    if not records:
        print("⚠️  No hay registros para insertar")
        return
    
    if dry_run:
        print_dry_run_summary(records)
        return
    
    conn = None
    try:
        # Conectar a la base de datos
        print(f"📡 Conectando a {DB_CONFIG['host']}...")
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        
        inserted_movements = 0
        inserted_participants = 0
        
        # Insertar movimientos uno por uno (para manejar participantes)
        for r in records:
            try:
                # Insertar movement
                cur.execute("""
                    INSERT INTO movements (
                        id, household_id, type, description, amount, category,
                        movement_date, currency, payer_user_id, payer_contact_id,
                        counterparty_user_id, counterparty_contact_id, payment_method_id
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    r['id'], r['household_id'], r['type'], r['description'], r['amount'],
                    r['category'], r['movement_date'], r['currency'], r['payer_user_id'],
                    r['payer_contact_id'], r['counterparty_user_id'], r['counterparty_contact_id'],
                    r['payment_method_id']
                ))
                inserted_movements += 1
                
                # Insertar participantes si es SPLIT
                if r['type'] == 'SPLIT' and r['participants']:
                    for p in r['participants']:
                        cur.execute("""
                            INSERT INTO movement_participants (
                                movement_id, participant_user_id, participant_contact_id, percentage
                            ) VALUES (%s, %s, %s, %s)
                        """, (
                            r['id'], p['participant_user_id'], p['participant_contact_id'], p['percentage']
                        ))
                        inserted_participants += 1
                
            except Exception as e:
                print(f"❌ Error insertando movimiento {r['id']}: {e}")
                conn.rollback()
                raise
        
        # Commit
        conn.commit()
        print(f"✅ Migración exitosa:")
        print(f"   - {inserted_movements} movimientos insertados")
        print(f"   - {inserted_participants} participantes insertados")
        
        # Mostrar resumen
        cur.execute("""
            SELECT type, COUNT(*), SUM(amount)
            FROM movements
            WHERE household_id = %s
            GROUP BY type
            ORDER BY type
        """, (HOUSEHOLD_ID,))
        
        print("\n📊 Resumen por tipo de movimiento:")
        print(f"{'Tipo':<15} {'Cantidad':<10} {'Total':>20}")
        print("-" * 47)
        for row in cur.fetchall():
            tipo, count, total = row
            print(f"{tipo:<15} {count:<10} ${total:>19,.2f}")
        
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
    print("🚀 Migración de Movimientos: Google Sheets → PostgreSQL\n")
    
    # Validar argumentos
    if len(sys.argv) < 3:
        print("Uso: python migrate_movements.py <gastos_csv> <participantes_csv> [--dry-run]")
        print("Ejemplo: python migrate_movements.py '/home/jose/Desktop/Casita - Gastos.csv' '/home/jose/Desktop/Casita - GastoParticipantes.csv' --dry-run")
        sys.exit(1)
    
    gastos_csv = sys.argv[1]
    participantes_csv = sys.argv[2]
    dry_run = '--dry-run' in sys.argv
    
    # Validar archivos
    if not os.path.exists(gastos_csv):
        print(f"❌ ERROR: Archivo no encontrado: {gastos_csv}")
        sys.exit(1)
    
    if not os.path.exists(participantes_csv):
        print(f"❌ ERROR: Archivo no encontrado: {participantes_csv}")
        sys.exit(1)
    
    # Validar configuración
    validate_config()
    
    # Generate ID mapping first (for consistent UUIDs)
    print(f"🔑 Generando mapeo de IDs...")
    id_mapping = generate_id_mapping(gastos_csv)
    print(f"✅ Mapeados {len(id_mapping)} IDs únicos")
    
    # Leer participantes
    print(f"📖 Leyendo participantes desde {participantes_csv}...")
    participants_map = read_participants_csv(participantes_csv, id_mapping)
    print(f"✅ Leídos participantes para {len(participants_map)} movimientos")
    
    # Leer movimientos
    print(f"📖 Leyendo movimientos desde {gastos_csv}...")
    records, warnings, errors = read_movements_csv(gastos_csv, participants_map, id_mapping)
    
    # Mostrar errores y warnings
    if warnings:
        print(f"\n⚠️  {len(warnings)} advertencias:")
        for w in warnings[:10]:  # Mostrar solo las primeras 10
            print(f"   {w}")
        if len(warnings) > 10:
            print(f"   ... y {len(warnings) - 10} más")
    
    if errors:
        print(f"\n❌ {len(errors)} errores encontrados:")
        for e in errors:
            print(f"   {e}")
        print(f"\n⚠️  {len(records)} registros válidos de {len(records) + len(errors)} totales")
        if not dry_run:
            response = input("\n¿Continuar con los registros válidos? (s/N): ").strip().lower()
            if response != 's':
                print("❌ Migración cancelada")
                sys.exit(1)
    else:
        print(f"✅ Leídos {len(records)} registros válidos\n")
    
    # Confirmar antes de insertar (si no es dry-run)
    if not dry_run:
        print(f"⚠️  Estás a punto de insertar {len(records)} movimientos en la base de datos.")
        print(f"   Base de datos: {DB_CONFIG['host']}/{DB_CONFIG['database']}")
        print(f"   Household ID: {HOUSEHOLD_ID}")
        
        response = input("\n¿Continuar? (s/N): ").strip().lower()
        if response != 's':
            print("❌ Migración cancelada")
            sys.exit(0)
    
    # Insertar registros
    insert_records(records, dry_run=dry_run)
    
    if not dry_run:
        print("\n🎉 ¡Migración completada!")
    

if __name__ == '__main__':
    main()
