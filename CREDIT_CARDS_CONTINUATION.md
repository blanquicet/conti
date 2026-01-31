# Continuación: Implementación de Tarjetas de Crédito

**Fecha:** 2026-01-31 (actualizado)  
**Estado:** ✅ Implementación completada y probada

---

## Resumen de lo implementado

### Backend (100% completado)

1. **Migración 034**: Tabla `credit_card_payments` para registrar pagos a tarjetas
   - Archivo: `backend/migrations/034_create_credit_card_payments.up.sql`

2. **Módulo `creditcardpayments`** (`backend/internal/creditcardpayments/`)
   - `types.go`: Estructuras de datos
   - `repository.go`: Queries de BD (Create, List, Delete, GetByID)
   - `service.go`: Lógica de negocio y validaciones
   - `handlers.go`: Endpoints HTTP (POST, GET, DELETE) - **Actualizado con autenticación por cookie**
   - Rutas: `/credit-card-payments`, `/credit-card-payments/{id}`

3. **Módulo `creditcards`** (`backend/internal/creditcards/`)
   - `types.go`: Estructuras para resumen y movimientos
   - `repository.go`: Queries para tarjetas, cargos, pagos, balances
   - `service.go`: Cálculo de ciclo de facturación, agregaciones
   - `handlers.go`: Endpoints HTTP
   - Rutas: `/credit-cards/summary`, `/credit-cards/{id}/movements`

4. **Server.go actualizado**: Todos los servicios y rutas registrados

### Frontend (100% completado)

1. **Tab "Tarjetas de crédito"** en `frontend/pages/home.js`:
   - Variables de estado: `creditCardsData`, `currentBillingCycle`, `selectedCardIds`, `selectedCardOwnerIds`, `isCardsFilterOpen`
   - **Nuevas variables**: `allCreditCards`, `allCardOwners` para mantener lista completa en filtros
   - `loadCreditCardsData()`: Fetch del resumen con filtros
   - `renderCreditCardsMonthSelector()`: Navegador de ciclos (renombrado de `renderBillingCycleSelector`)
   - `renderCreditCards()`: Lista de tarjetas con expand/collapse
   - `renderCardsFilterDropdown()`: Filtro por tarjeta y propietario
   - `loadAndRenderCardMovements()`: Carga lazy de cargos y abonos
   - `setupBillingCycleNavigation()`: Navegación entre ciclos
   - `setupCardsListeners()`: Eventos de expand, filtros, etc.
   - `showCardPaymentModal()`: Modal para registrar abonos
   - `handleDeleteCardPayment()`: Eliminar abonos

2. **CSS** en `frontend/styles.css`:
   - Estilos para `.credit-card-card`, `.card-paid`, `.debt-amount`, `.paid-amount`
   - Estilos para `.card-section`, `.card-net-summary`, `.card-loading`
   - Badges para categoría y cuenta origen
   - **Filtro dropdown**: `.filter-dropdown` con visibilidad controlada por clase `.show`

---

## Cambios realizados el 2026-01-31

### Fixes de UI

1. **Simplificación del resumen superior**:
   - Eliminado cálculo de "Disponible" - solo muestra "Deuda total"
   - Estilo cambiado a usar clase `total-display` (igual que Presupuesto tab)

2. **Totales por tarjeta**:
   - Cambiado de `expense-group-amount-sub` a `expense-group-amount` para consistencia con Gastos tab
   - Muestra el cálculo gastos - abonos directamente debajo del nombre

3. **Filtro dropdown**:
   - Arreglado para que se oculte por defecto (CSS: `display: none`)
   - Solo aparece al hacer click en botón de filtro (toggle clase `.show`)
   - Removido header con "Filtrar tarjetas" y botón X
   - Botones "Todos" y "Limpiar" usan clase `filter-link-btn`
   - Labels usan clase `filter-checkbox-label`
   - Removido emoji 💳 y nombre del propietario de las opciones

4. **Persistencia de opciones en filtro**:
   - Nuevas variables `allCreditCards` y `allCardOwners` almacenan lista completa
   - El dropdown siempre muestra todas las opciones, no solo las filtradas

5. **Estado vacío contextual**:
   - Sin filtros: "No hay tarjetas de crédito o no hay cargos en este ciclo"
   - Con filtros sin matches: "No hay tarjetas que coincidan con los filtros seleccionados" + botón "Mostrar todo"

### Fixes del Modal de Pagos

1. **Fetch de cuentas corregido**:
   - Ahora obtiene cuentas de `/accounts` en paralelo con `/movement-form-config`
   - Filtra solo cuentas tipo `savings` o `cash`

2. **Estilos del modal**:
   - Reescrito HTML para usar patrón de `label.field` (igual que modal de templates)
   - Layout con flexbox y grid

3. **Comportamiento del modal**:
   - Ya no se cierra al hacer click fuera - solo con botón Cancelar

4. **Labels de cuentas**:
   - Removido tipo de cuenta entre paréntesis (ej: ya no muestra "(Ahorros)")

### Fixes de Backend

1. **Autenticación en handler de pagos**:
   - Handler reescrito para usar autenticación por cookie (igual que otros handlers)
   - Agregado método helper `getUserFromSession`
   - Handler struct ahora incluye: `authSvc`, `cookieName`, `logger`
   - `server.go` actualizado para pasar `cfg.SessionCookieName` al handler

### Otros cambios

1. **Template modal** (`showTemplateModal`):
   - Agregado campo "Cuenta donde recibe" para DEBT_PAYMENT cuando receptor es miembro
   - Fetch de cuentas desde `/accounts`
   - Filtrado de cuentas por `owner_id` del receptor

2. **registrar-movimiento.js**:
   - Removido tipo de cuenta de labels en dropdown de "Cuenta donde recibe"
   - Removidos hints "Solo cuentas tipo savings o cash" (4 ubicaciones)

---

## Testing completado ✅

- [x] Tab "Tarjetas de crédito" carga correctamente
- [x] Ciclo de facturación se calcula bien
- [x] Navegación entre ciclos funciona
- [x] Expandir tarjeta carga cargos y abonos
- [x] Filtros por tarjeta funcionan
- [x] Filtro retiene opciones después de aplicar
- [x] Estado vacío muestra mensaje correcto
- [x] Modal de abono abre correctamente
- [x] Modal obtiene cuentas disponibles
- [x] Crear abono funciona (después de fix de auth)

---

## Archivos modificados

```
backend/
├── internal/creditcardpayments/handlers.go  # Reescrito con auth por cookie
├── internal/creditcardpayments/service_test.go  # NUEVO - 9 unit tests
├── internal/creditcards/service_test.go     # NUEVO - 12 unit tests
└── internal/httpserver/server.go            # Actualizado NewHandler call

frontend/
├── pages/home.js           # Múltiples fixes de UI y funcionalidad
├── pages/registrar-movimiento.js  # Removidos hints, labels simplificados
└── styles.css              # Reglas de visibilidad para filtro
```

---

## Notas técnicas importantes

### Patrón de autenticación en handlers
```go
// Correcto (usado ahora):
cookie, err := r.Cookie(h.cookieName)
user, err := h.authSvc.GetUserBySession(ctx, cookie.Value)
userID := user.ID

// Incorrecto (causaba 500):
userID := r.Context().Value("userID").(string)  // nil, no existe
```

### Persistencia de opciones en filtros
```javascript
// Variables globales para mantener lista completa
let allCreditCards = [];
let allCardOwners = [];

// Se llenan en loadCreditCardsData() cuando no hay filtros
if (selectedCardIds.length === 0 && selectedCardOwnerIds.length === 0) {
  allCreditCards = creditCardsData.cards || [];
  allCardOwners = [...new Set(cards.map(c => ({ id: c.owner_id, name: c.owner_name })))];
}

// El dropdown siempre usa estas variables, no creditCardsData.cards
```

### Visibilidad de filtro dropdown
```css
.filter-dropdown { display: none; }
.filter-dropdown.show { display: block; }
```

---

## Prompt para continuar

```
La implementación de "Tarjetas de crédito" está completa.

Próximos pasos opcionales:
1. Agregar campo cutoff_day al formulario de métodos de pago en Hogar
2. Mostrar "Disponible" calculando balance real de cuentas
3. Tests de integración automatizados

Ver archivo CREDIT_CARDS_CONTINUATION.md para detalles técnicos.
```

---

## Unit Tests

Se agregaron tests unitarios para los módulos del backend:

### `creditcards/service_test.go` (12 tests)

Tests para cálculo de ciclo de facturación:
- `TestCalculateBillingCycle_NilCutoff`: Cuando no hay día de corte, usa último día del mes
- `TestCalculateBillingCycle_BeforeCutoff`: Día actual antes del día de corte
- `TestCalculateBillingCycle_AfterCutoff`: Día actual después del día de corte
- `TestCalculateBillingCycle_OnCutoffDay`: Día actual es el día de corte
- `TestCalculateBillingCycle_EndOfYear`: Ciclo que cruza fin de año
- `TestCalculateBillingCycle_February`: Manejo de febrero y meses cortos
- `TestCalculateBillingCycle_Label`: Formato del label del ciclo

Tests para funciones auxiliares:
- `TestLastDayOfMonth`: Cálculo del último día de cada mes

Tests para filtros:
- `TestApplyFilters_NoFilters`: Sin filtros retorna todos
- `TestApplyFilters_ByCardID`: Filtro por ID de tarjeta
- `TestApplyFilters_ByOwnerID`: Filtro por propietario
- `TestApplyFilters_CombinedFilters`: Filtros combinados

### `creditcardpayments/service_test.go` (9 tests)

Tests de validación de input:
- `TestCreateInput_Validate`: Validación de campos requeridos y montos

Tests de creación de pagos:
- `TestCreate_Success`: Creación exitosa
- `TestCreate_CreditCardNotFound`: Tarjeta no existe
- `TestCreate_NotACreditCard`: Método de pago no es tarjeta de crédito
- `TestCreate_SourceAccountNotSavings`: Cuenta origen no es savings/cash
- `TestCreate_NotAuthorized_DifferentHousehold`: Sin autorización en otro household

Tests de eliminación:
- `TestDelete_Success`: Eliminación exitosa
- `TestDelete_NotAuthorized`: Sin autorización para eliminar

Tests de listado:
- `TestList_FilterByCreditCard`: Filtro por tarjeta retorna resultados correctos

### Ejecución

```bash
cd backend && go test ./internal/creditcards/... ./internal/creditcardpayments/... -v
```

Resultado: **21 tests passing** (12 + 9)
