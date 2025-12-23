# Guía de Testing E2E con Playwright

Esta guía documenta cómo ejecutar tests end-to-end usando Playwright para la aplicación de gastos.

## Prerequisitos

### 1. Base de Datos PostgreSQL

La base de datos debe estar corriendo usando Docker Compose:

```bash
cd backend
docker-compose up -d
```

**Verificar que está corriendo:**

```bash
docker-compose ps
# Debería mostrar el contenedor de postgres corriendo

# O verificar la conexión directamente
docker-compose exec postgres psql -U gastos -d gastos
```

### 2. Backend Go

El backend debe estar corriendo en el puerto 8080:

```bash
cd backend
go run ./cmd/api/main.go
```

**Verificar que está corriendo:**

- El backend debería mostrar: `Server listening on :8080`
- Puedes verificar con: `curl http://localhost:8080`

**Variables de entorno:**

- El backend usa las variables definidas en el archivo `.env`
- Asegúrate de tener configurado: `DATABASE_URL`, `N8N_WEBHOOK_URL`, `SESSION_COOKIE_SECURE`, `STATIC_DIR`

### 3. n8n (Servicio externo)

⚠️ **IMPORTANTE**: n8n debe estar corriendo para que los movimientos se guarden en Google Sheets.

**Verificar que n8n está disponible:**
```bash
curl -I <URL_DEL_WEBHOOK_N8N>
# Verificar la URL configurada en tu archivo .env
```

**Si hay errores relacionados con n8n:**
- El backend retornará status 500 con mensaje: "Failed to record movement"
- El frontend mostrará: "No se pudo conectar con n8n para guardar el movimiento en Google Sheets"
- **Solución**: Asegúrate que n8n está corriendo antes de continuar con los tests

## Instalación de Playwright

```bash
cd backend
npx playwright install chrome
```

## Tests E2E

⚠️ **IMPORTANTE - Valores de tipos de movimiento:**
- En el HTML, los valores (value) de los tipos son: `FAMILIAR`, `COMPARTIDO`, `PAGO_DEUDA`
- Los textos mostrados son: "Gasto del hogar", "Dividir gasto", "Pago de deuda"
- Al usar Playwright con `selectOption()`, debes usar los **valores** (FAMILIAR, COMPARTIDO, PAGO_DEUDA), NO los textos mostrados

### Test 1: Registro de Usuario

**Objetivo**: Crear un nuevo usuario y verificar en la base de datos.

**Pasos:**
1. Navegar a `http://localhost:8080/login`
2. Verificar que muestra el formulario de login (no registro)
3. Hacer clic en "Registrarse"
4. Llenar el formulario:
   - Nombre: `Usuario Test Playwright`
   - Email: `test-playwright@example.com`
   - Contraseña: `TestPass123!`
5. Enviar el formulario
6. Verificar redirección a `/registrar-movimiento`

**Verificación en base de datos:**
```sql
-- Verificar que el usuario fue creado
SELECT id, name, email, created_at 
FROM users 
WHERE email = 'test-playwright@example.com';

-- Verificar que hay una sesión activa
SELECT s.id, s.user_id, s.expires_at, s.created_at
FROM sessions s
JOIN users u ON s.user_id = u.id
WHERE u.email = 'test-playwright@example.com';
```

### Test 2: Login y Logout

**Objetivo**: Verificar el flujo de autenticación.

**Login:**
1. Navegar a `http://localhost:8080/login`
2. Llenar credenciales
3. Hacer clic en "Iniciar sesión"
4. Verificar redirección a `/registrar-movimiento`

**Logout:**
1. Hacer clic en "Salir"
2. Verificar redirección a `/login`
3. **IMPORTANTE**: Verificar que muestra el formulario de LOGIN (no registro)
   - Bug anterior: se mostraba el formulario de registro
   - Fix: `currentForm = 'login'` se resetea en `render()`

**Verificación en base de datos:**
```sql
-- Después de logout, la sesión debe ser eliminada
SELECT COUNT(*) FROM sessions 
WHERE user_id = (SELECT id FROM users WHERE email = 'test-playwright@example.com');
-- Debería retornar 0

-- Después de login, debe haber una nueva sesión
SELECT id, expires_at FROM sessions 
WHERE user_id = (SELECT id FROM users WHERE email = 'test-playwright@example.com');
-- Debería retornar 1 registro con expires_at = now() + 30 days
```

### Test 3: Registro de Movimientos

⚠️ **Antes de ejecutar**: Preguntar al usuario si n8n está corriendo.

#### 3.1 Movimiento FAMILIAR

**Pasos:**
1. Seleccionar tipo: "Gasto del hogar"
2. Descripción: `Mercado semanal del hogar`
3. Categoría: `Mercado`
4. Monto total: `150000` (se formatea automáticamente a `150,000.00`)
5. Método de pago: `Débito Caro` (aparece automáticamente para tipo FAMILIAR)
6. Hacer clic en "Registrar"

**Resultado esperado:**
- Mensaje: "Movimiento registrado correctamente."
- Formulario se limpia
- Movimiento aparece en Google Sheets

**Payload enviado:**
```json
{
  "fecha": "2025-12-23",
  "tipo": "FAMILIAR",
  "descripcion": "Mercado semanal del hogar",
  "categoria": "Mercado",
  "valor": 150000,
  "pagador": "",
  "contraparte": "",
  "metodo_pago": "Débito Caro",
  "participantes": []
}
```

#### 3.2 Movimiento PAGO_DEUDA

**Pasos:**
1. Seleccionar tipo: "Pago de deuda"
2. Descripción: `Pago de préstamo personal`
3. Categoría: `Préstamo`
4. Monto total: `50000` (se formatea a `50,000.00`)
5. ¿Quién pagó?: `Jose`
6. ¿Quién recibió?: `Caro`
7. Método de pago: `MasterCard Oro Jose`
8. Hacer clic en "Registrar"

**Resultado esperado:**
- Mensaje: "Movimiento registrado correctamente."
- Formulario se limpia
- Movimiento aparece en Google Sheets

**Payload enviado:**
```json
{
  "fecha": "2025-12-23",
  "tipo": "PAGO_DEUDA",
  "descripcion": "Pago de préstamo personal",
  "categoria": "Préstamo",
  "valor": 50000,
  "pagador": "Jose",
  "contraparte": "Caro",
  "metodo_pago": "MasterCard Oro Jose",
  "participantes": []
}
```

#### 3.3 Movimiento COMPARTIDO (3 participantes)

**Pasos:**
1. Seleccionar tipo: "Dividir gasto"
2. Descripción: `Cena compartida con amigos`
3. Categoría: `Salidas juntos`
4. Monto total: `90000` (se formatea a `90,000.00`)
5. ¿Quién pagó?: `Jose`
6. Método de pago: `MasterCard Oro Jose`
7. **Participantes** (se crea automáticamente Jose con 100%):
   - Hacer clic en "Agregar participante" (2 veces)
   - Aparecen: Jose (33.33%), Caro (33.33%), Maria Isabel (33.34%)
8. **Verificar toggle "Mostrar como valor"**:
   - Activar checkbox
   - Valores deben mostrar: `COP 30,000.00` (o similar según distribución)
   - Formato con comas y prefijo COP
9. Hacer clic en "Registrar"

**Resultado esperado:**
- Mensaje: "Movimiento registrado correctamente."
- Formulario se limpia
- Movimiento aparece en Google Sheets con los 3 participantes

**Payload enviado:**
```json
{
  "fecha": "2025-12-23",
  "tipo": "COMPARTIDO",
  "descripcion": "Cena compartida con amigos",
  "categoria": "Salidas juntos",
  "valor": 90000,
  "pagador": "Jose",
  "contraparte": "",
  "metodo_pago": "MasterCard Oro Jose",
  "participantes": [
    {"nombre": "Jose", "porcentaje": 0.3333},
    {"nombre": "Caro", "porcentaje": 0.3333},
    {"nombre": "Maria Isabel", "porcentaje": 0.3334}
  ]
}
```

**Nota sobre porcentajes**: Se envían en formato decimal (0-1), no como enteros (0-100).

#### 3.4 Movimiento COMPARTIDO (2 participantes)

**Pasos:**
1. Seleccionar tipo: "Dividir gasto"
2. Descripción: `Taxi compartido al aeropuerto`
3. Categoría: `Uber/Gasolina/Peajes/Parqueaderos`
4. Monto total: `60000` (se formatea a `60,000.00`)
5. ¿Quién pagó?: `Caro`
6. Método de pago: `Débito Caro`
7. **Participantes**:
   - Hacer clic en "Agregar participante" (1 vez)
   - Aparecen: Caro (50%), Jose (50%)
8. Hacer clic en "Registrar"

**Resultado esperado:**
- Mensaje: "Movimiento registrado correctamente."
- Formulario se limpia
- Movimiento aparece en Google Sheets con los 2 participantes

## Formato de Valores

### Campo "Monto total"
- Input: `150000`
- Al perder foco (blur): se formatea a `150,000.00`
- Prefijo interno: `COP` (dentro del input, color gris)
- Al obtener foco (focus): vuelve a número sin formato para editar

### Participantes - Modo Porcentaje (default)
- Input type: `number`
- Valores: `33.33`, `50`, `100`
- Sufijo: `%` (a la derecha, color gris)
- Ancho columna: `95px`

### Participantes - Modo Valor (toggle activo)
- Input type: `text` (para permitir formato con comas)
- Valores: `30,000.00`, `45,000.00`, etc.
- Prefijo: `COP` (a la izquierda, color gris)
- Formato: con comas para miles
- Ancho columna: `160px`
- Al perder foco: se formatea automáticamente
- Al obtener foco: muestra número sin formato

## Manejo de Errores

### Error: n8n no disponible

**Síntomas:**
- Backend retorna HTTP 500
- Mensaje: "Failed to record movement"
- Frontend muestra: "No se pudo conectar con n8n para guardar el movimiento en Google Sheets"

**Solución:**
1. Preguntar al usuario: "¿Está corriendo n8n?"
2. Esperar confirmación antes de continuar
3. Si no está corriendo, pedir que lo inicie
4. Reintentar el test

### Error: Backend no disponible

**Síntomas:**
- TypeError en fetch
- Frontend muestra: "No se pudo conectar al backend"

**Solución:**
1. Verificar que el backend está corriendo: `curl http://localhost:8080`
2. Verificar logs del backend
3. Reiniciar backend si es necesario

### Error: Base de datos no disponible

**Síntomas:**
- Backend muestra errores de conexión a PostgreSQL
- No se pueden crear usuarios o sesiones

**Solución:**
1. Verificar que PostgreSQL está corriendo: `docker-compose ps`
2. Verificar que el archivo `.env` tiene la configuración correcta de `DATABASE_URL`
3. Verificar que la base de datos `gastos` existe
4. Ejecutar migraciones si es necesario

## Tests de Validación y Casos de Error

### Test 4: Validación de Porcentajes en COMPARTIDO

**Objetivo**: Verificar que el frontend valida correctamente la suma de porcentajes.

#### 4.1 Error: Porcentajes no suman 100%

**Pasos:**
1. Crear movimiento COMPARTIDO con 2 participantes
2. Desactivar checkbox "Dividir equitativamente"
3. Los inputs ahora son editables
4. Editar manualmente los porcentajes:
   - Participante 1: `40`
   - Participante 2: `50` (suma = 90%, no 100%)
5. Intentar hacer clic en "Registrar"

**Resultado esperado:**
- ❌ Mensaje de error: "Los porcentajes de participantes deben sumar 100%. Actualmente: 90.00%."
- ❌ El formulario NO se envía
- ✅ El usuario puede corregir los valores

**Caso correcto:**
- Cambiar participante 2 a `60`
- Ahora suma 100%
- ✅ El mensaje de error desaparece
- ✅ Puede enviar el formulario

#### 4.2 Edición manual de porcentajes con 3 participantes

**Pasos:**
1. Crear movimiento COMPARTIDO con 3 participantes
2. Desactivar "Dividir equitativamente"
3. Editar manualmente:
   - Participante 1: `25`
   - Participante 2: `25`
   - Participante 3: `55` (suma = 105%, ERROR)
4. Intentar registrar

**Resultado esperado:**
- ❌ Error: "Los porcentajes de participantes deben sumar 100%. Actualmente: 105.00%."
- ❌ No se envía

**Corrección:**
- Cambiar participante 3 a `50`
- ✅ Suma 100%, error desaparece

### Test 5: Validación de Valores en modo "Mostrar como valor"

**Objetivo**: Verificar validación cuando se usa modo valor en COP.

#### 5.1 Error: Valores no suman el monto total

**Pasos:**
1. Crear movimiento COMPARTIDO
2. Monto total: `100000` (se formatea a `100,000.00`)
3. ¿Quién pagó?: `Jose`
4. Agregar 2 participantes (Jose, Caro)
5. **Activar** checkbox "Mostrar como valor"
6. Desactivar "Dividir equitativamente"
7. Los campos ahora muestran: `COP 50,000.00` (editable)
8. Editar manualmente:
   - Jose: `30000` (se formatea a `30,000.00` al perder foco)
   - Caro: `60000` (se formatea a `60,000.00`)
   - Suma: 90,000 (NO es 100,000)
9. Intentar registrar

**Resultado esperado:**
- ❌ Error: Los valores internos se convierten a porcentajes
  - Jose: 30,000 / 100,000 = 30%
  - Caro: 60,000 / 100,000 = 60%
  - Suma: 90% (no 100%)
- ❌ Mensaje: "Los porcentajes de participantes deben sumar 100%. Actualmente: 90.00%."

**Corrección:**
- Cambiar Caro a `70000` (70,000.00)
- Ahora suma 100,000
- ✅ Porcentajes: 30% + 70% = 100%
- ✅ Puede enviar

#### 5.2 Valores exceden el monto total

**Pasos:**
1. Monto total: `50,000.00`
2. 2 participantes en modo valor
3. Editar:
   - Participante 1: `35000`
   - Participante 2: `25000`
   - Suma: 60,000 (excede 50,000)

**Resultado esperado:**
- ❌ Porcentajes resultantes: 70% + 50% = 120%
- ❌ Error: "Los porcentajes de participantes deben sumar 100%. Actualmente: 120.00%."

### Test 6: Validación de Campos Obligatorios

**Objetivo**: Verificar que los campos obligatorios son validados.

#### 6.1 Error: Categoría no seleccionada (COMPARTIDO)

**Pasos:**
1. Tipo: "Dividir gasto"
2. Descripción: "Test sin categoría"
3. Monto: `50000`
4. Pagador: `Jose`
5. Método: `MasterCard Oro Jose`
6. **NO seleccionar categoría** (dejar en "Seleccionar")
7. Intentar registrar

**Resultado esperado:**
- ❌ Error: "Categoría es obligatoria."
- ❌ No se envía

#### 6.2 Error: Método de pago no seleccionado

**Pasos:**
1. Tipo: "Gasto del hogar" (FAMILIAR)
2. Descripción: "Test"
3. Categoría: "Mercado"
4. Monto: `50000`
5. **NO seleccionar método de pago**
6. Intentar registrar

**Resultado esperado:**
- ❌ Error: "Método de pago es obligatorio."

#### 6.3 Error: Monto total inválido

**Pasos:**
1. Crear cualquier movimiento
2. Monto total: dejar vacío o escribir `0`
3. Intentar registrar

**Resultado esperado:**
- ❌ Error: "Monto total debe ser un número mayor a 0."

#### 6.4 Error: Pagador y Tomador iguales (PAGO_DEUDA)

**Pasos:**
1. Tipo: "Pago de deuda"
2. ¿Quién pagó?: `Jose`
3. ¿Quién recibió?: `Jose` (mismo que pagador)
4. Intentar registrar

**Resultado esperado:**
- ❌ Error: "Pagador y Tomador no pueden ser la misma persona."

### Test 7: Validación de Participantes Duplicados

**Objetivo**: Verificar que no se pueden repetir participantes.

**Pasos:**
1. Crear movimiento COMPARTIDO
2. Agregar 3 participantes
3. Seleccionar en dropdown:
   - Participante 1: `Jose`
   - Participante 2: `Caro`
   - Participante 3: Cambiar a `Jose` (duplicado)
4. Observar el comportamiento del sistema

**Resultado esperado:**
- ✅ El sistema **elimina automáticamente** el duplicado mediante `dedupeParticipants()`
- ✅ Queda solo el participante original (Jose) sin duplicar
- ✅ La lista de participantes se reduce automáticamente
- ✅ Esto es comportamiento **correcto**, no un error

**Nota técnica**: La función `dedupeParticipants()` en el código frontend previene duplicados automáticamente al cambiar el valor de un dropdown de participante.

### Test 8: Comportamiento de UI - Campos Dinámicos

**Objetivo**: Verificar que los campos aparecen/desaparecen según el tipo.

#### 8.1 FAMILIAR no muestra pagador ni participantes

**Pasos:**
1. Seleccionar tipo: "Gasto del hogar"
   - ⚠️ **Importante**: Al usar Playwright con `selectOption()`, usa el valor: `['FAMILIAR']`

**Resultado esperado:**

- ✅ NO aparece campo "¿Quién pagó?" (#pagadorWrap hidden)
- ✅ NO aparece sección "Participantes" (#participantesWrap hidden)
- ✅ NO aparece "Pagador/Tomador" (#pagadorTomadorRow hidden)
- ✅ SÍ aparece "Método de pago" (obligatorio para FAMILIAR)

#### 8.2 COMPARTIDO muestra campos correctos

**Pasos:**

1. Seleccionar tipo: "Dividir gasto"
   - ⚠️ **Importante**: Al usar Playwright con `selectOption()`, usa el valor: `['COMPARTIDO']`
2. Seleccionar pagador: `Jose` en el campo #pagadorCompartido

**Resultado esperado:**

- ✅ Aparece campo "¿Quién pagó?" (#pagadorWrap visible)
- ✅ Aparece sección "Participantes" (#participantesWrap visible)
- ✅ NO aparece "Pagador/Tomador" (#pagadorTomadorRow hidden)
- ✅ El pagador se agrega automáticamente como primer participante (100%)
- ✅ Aparece "Método de pago" SOLO si el pagador es Jose o Caro (PRIMARY_USERS)

#### 8.3 PAGO_DEUDA muestra pagador y tomador

**Pasos:**

1. Tipo: "Pago de deuda"
   - ⚠️ **Importante**: Al usar Playwright con `selectOption()`, usa el valor: `['PAGO_DEUDA']`
2. Observar los campos que aparecen

**Resultado esperado:**

- ✅ Aparece fila "Pagador/Tomador" (#pagadorTomadorRow visible)
- ✅ Dentro hay dos campos: #pagador y #tomador
- ✅ NO aparece campo #pagadorWrap (hidden)
- ✅ NO aparece sección "Participantes" (#participantesWrap hidden)

**Caso con usuario no primario (método de pago):**

- Si ¿Quién pagó?: `Maria Isabel` (no es Jose ni Caro) → NO aparece campo "Método de pago"
- Si ¿Quién pagó?: `Jose` → SÍ aparece y ES obligatorio

### Test 9: Formato de Números - Comportamiento Focus/Blur

**Objetivo**: Verificar que el formato con comas funciona correctamente.

#### 9.1 Monto total - Ciclo focus/blur

**Pasos:**

1. Hacer clic en campo "Monto total"
2. Campo debe estar vacío (placeholder "0")
3. Escribir: `1234567`
4. Hacer clic fuera (blur)

**Resultado esperado:**

- ✅ Se formatea a: `COP 1,234,567.00`
- ✅ Prefijo COP visible en gris a la izquierda

**Hacer clic de nuevo (focus):**

- ✅ El valor debe mostrar: `1234567` (sin formato, para editar)
- ✅ Al hacer blur de nuevo: vuelve a `1,234,567.00`

#### 9.2 Participantes modo valor - Formato con comas

**Pasos:**

1. COMPARTIDO, monto total: `100000`
2. Activar "Mostrar como valor"
3. 2 participantes automáticos muestran: `COP 50,000.00`
4. Desactivar equitativo
5. Hacer clic en campo de participante 1
6. Debe mostrar: `50000` (sin formato)
7. Cambiar a: `35000`
8. Hacer blur

**Resultado esperado:**

- ✅ Se formatea a: `COP 35,000.00`
- ✅ El otro participante permanece en `50,000.00`
- ❌ Suma no es 100% → error debe aparecer

### Test 10: Casos Edge - Límites y Extremos

#### 10.1 Monto muy grande

**Pasos:**

1. Monto total: `999999999`

**Resultado esperado:**

- ✅ Formatea a: `COP 999,999,999.00`
- ✅ Se puede enviar sin problemas

#### 10.2 Porcentajes con decimales

**Pasos:**

1. COMPARTIDO, 3 participantes
2. Desactivar equitativo
3. Editar porcentajes:
   - P1: `33.33`
   - P2: `33.33`
   - P3: `33.34`

**Resultado esperado:**

- ✅ Suma exacta: 100%
- ✅ No hay error
- ✅ Se puede enviar

#### 10.3 Un solo participante al 100%

**Pasos:**

1. COMPARTIDO
2. Pagador: `Jose`
3. NO agregar más participantes
4. Jose queda al 100%
5. Registrar

**Resultado esperado:**

- ✅ Se puede enviar
- ✅ Payload: `participantes: [{"nombre": "Jose", "porcentaje": 1.0}]`

## Resumen de Validaciones a Verificar

### Validaciones del Frontend

- [ ] Categoría obligatoria para TODOS los tipos
- [ ] Método de pago obligatorio para FAMILIAR y usuarios primarios (Jose/Caro)
- [ ] Monto total > 0
- [ ] Fecha obligatoria
- [ ] Tipo de movimiento obligatorio
- [ ] Para PAGO_DEUDA: tomador diferente de pagador
- [ ] Para COMPARTIDO: porcentajes suman exactamente 100%
- [ ] Para COMPARTIDO: al menos 1 participante
- [ ] Para COMPARTIDO: no duplicar participantes
- [ ] Formato de números con comas funciona en blur
- [ ] Formato se elimina en focus para permitir edición

### Validaciones del Backend (errores esperados)

- [ ] n8n no disponible → HTTP 500 con mensaje específico
- [ ] Base de datos no disponible → error de conexión
- [ ] Sesión expirada → redirección a /login

## Notas para Copilot al Ejecutar Tests

1. **Antes de test de movimientos**: Siempre preguntar si n8n está corriendo
2. **Casos de error son importantes**: No solo probar casos felices
3. **Validar mensajes de error**: Verificar que los mensajes sean claros y útiles
4. **Probar límites**: Números grandes, muchos participantes, porcentajes con decimales
5. **UI responsivo**: Verificar que campos aparecen/desaparecen correctamente
6. **Formato de números**: Probar ciclo focus/blur múltiples veces

## Verificación de Google Sheets

Después de cada movimiento registrado con éxito, verificar en Google Sheets:

**Columnas esperadas:**

- Fecha: `2025-12-23` (o fecha actual)
- Tipo: `FAMILIAR`, `COMPARTIDO`, o `PAGO_DEUDA`
- Descripción: texto ingresado
- Categoría: categoría seleccionada (NO debe ser "undefined")
- Valor: número sin formato (ej: `150000`)
- Pagador: nombre o vacío para FAMILIAR
- Contraparte: nombre para PAGO_DEUDA, vacío para otros
- Método de pago: nombre del método
- Participantes: JSON array para COMPARTIDO, vacío para otros

## Notas Importantes

1. **Categoría es obligatoria para TODOS los tipos** (incluyendo COMPARTIDO)
2. **Los porcentajes se envían como decimales** (0.3333, no 33.33)
3. **El login siempre muestra el formulario de login primero** (bug fix aplicado)
4. **n8n debe estar corriendo** para que los movimientos se guarden en Sheets
5. **Formato de valores con comas** (71,033.90) aplica a monto total y participantes en modo valor
6. **Prefijo COP consistente**: aparece a la izquierda en todos los campos de valor

## Errores Comunes al Usar Playwright

### 1. Valores incorrectos en selectOption()

❌ **INCORRECTO:**
```javascript
await page.getByLabel('Tipo de movimiento').selectOption(['GASTO_HOGAR']);
```

✅ **CORRECTO:**
```javascript
await page.getByLabel('Tipo de movimiento').selectOption(['FAMILIAR']);
await page.getByLabel('Tipo de movimiento').selectOption(['COMPARTIDO']);
await page.getByLabel('Tipo de movimiento').selectOption(['PAGO_DEUDA']);
```

### 2. Selectores ambiguos (strict mode violation)

❌ **INCORRECTO:**
```javascript
// Error: "¿Quién pagó?" aparece dos veces (PAGO_DEUDA y COMPARTIDO)
await page.getByLabel('¿Quién pagó?').selectOption(['Jose']);
```

✅ **CORRECTO:**
```javascript
// Usa IDs específicos
await page.locator('#pagador').selectOption(['Jose']);           // Para PAGO_DEUDA
await page.locator('#pagadorCompartido').selectOption(['Jose']); // Para COMPARTIDO
```

### 3. IDs de elementos importantes

**Campos dinámicos por tipo:**
- `#pagadorWrap` - Pagador para COMPARTIDO (label + #pagadorCompartido)
- `#pagadorTomadorRow` - Fila con pagador y tomador para PAGO_DEUDA (contiene #pagador y #tomador)
- `#participantesWrap` - Sección completa de participantes para COMPARTIDO

**Checkboxes en COMPARTIDO:**
- Acceder con `getByLabel('Dividir equitativamente')` o `getByLabel('Mostrar como valor')`
- NO usar IDs específicos, ya que pueden no estar disponibles

### 4. Esperar por cambios en UI

```javascript
// Después de cambiar tipo de movimiento, esperar un poco para que UI se actualice
await page.getByLabel('Tipo de movimiento').selectOption(['COMPARTIDO']);
await page.waitForTimeout(200); // Permitir que campos dinámicos aparezcan
```

### 5. Manejo de inputs formateados

```javascript
// Al editar campos con formato (monto, participantes en modo valor)
// Usar fill() borra todo y escribe el nuevo valor
await page.getByRole('textbox', { name: 'Monto total COP Obligatorio' }).fill('50000');

// El formato se aplica automáticamente en blur
await page.getByRole('textbox', { name: 'Monto total COP Obligatorio' }).blur();

// El valor formateado será: "50,000.00"
const value = await page.getByRole('textbox', { name: 'Monto total COP Obligatorio' }).inputValue();
// value === "50,000.00"
```
