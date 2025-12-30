# Movement Registration with n8n Backend

> **Current Status:** ✅ ACTIVE for movements registration
>
> This phase describes the n8n-based movement registration system.
> This is the **current implementation** for recording movements until Phase 2 migration.

**Architecture:**

- Authentication: PostgreSQL (see `01_AUTH_PHASE.md`)
- Movement storage: n8n → Google Sheets (this document)

**Relationship to other phases:**

- See `01_AUTH_PHASE.md` for authentication implementation
- See `FUTURE_VISION.md` for long-term product direction
- Phase 2 will migrate movements from Google Sheets to PostgreSQL

---

## 🎯 Goals

- Continue improving the frontend at <https://gastos.blanquicet.com.co/registrar-movimiento>
- Ensure end-to-end flow: **Mobile-friendly form → POST to n8n webhook → row appended to "Gastos" table**
- Keep the current data model decisions: payments of debt stay in "Gastos" with `Tipo=PAGO_DEUDA`; direction is inferred using `Pagador` and `Contraparte`

---

## 🏗️ Current Deployment / Infrastructure

**Important:** This describes the n8n integration for movements only.
For authentication infrastructure, see `01_AUTH_PHASE.md`.

### Frontend: Azure Static Web Apps (SWA)

| Setting       | Value                                   |
| ------------- | --------------------------------------- |
| Custom domain | `gastos.blanquicet.com.co`              |
| DNS           | Cloudflare (DNS-only, **not proxied**)  |
| App path      | `/registrar-movimiento`                 |
| Build         | None (pure static HTML/CSS/JS)          |
| Deploy        | GitHub Actions on push                  |

> **Important:** SWA must find `index.html` in `app_location`, so `app_location` is `/registrar-movimiento` and `skip_app_build=true`. The `staticwebapp.config.json` handles route rewrites.

### Backend: n8n on VM behind Caddy

| Setting          | Value                                                             |
| ---------------- | ----------------------------------------------------------------- |
| Domain           | `https://n8n.blanquicet.com.co`                                   |
| Webhook endpoint | `POST https://n8n.blanquicet.com.co/webhook/movimientos/reportar` |
| CORS origin      | `https://gastos.blanquicet.com.co`                                |
| Auth             | Header Auth via `X-API-Key`                                       |

> **Important:** CORS must include `X-API-Key` in `Access-Control-Allow-Headers`, otherwise browser preflight will fail.

---

## ✅ End-to-End Verified

```bash
curl -X POST https://n8n.blanquicet.com.co/webhook/movimientos/reportar \
  -H "X-API-Key: mov-2025-registrar-9f3a7c2d8e41" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
# Returns: {"ok":true,"message":"Movimiento registrado"}
```

The app writes rows to the "Gastos" table with computed `Mes` (YYYY-MM) and `Semana` (YYYY-W##).

---

## 📊 Data Model / Business Rules

### Tipos de Movimiento

| Tipo         | Descripción                        | Campos visibles                                                                                  |
| ------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------ |
| `FAMILIAR`   | Gasto familiar                     | Método de pago, Categoría                                                                        |
| `COMPARTIDO` | Gasto dividido entre participantes | Pagador, Método de pago (si Jose/Caro), Participantes                                            |
| `PAGO_DEUDA` | Pago/cobro de deuda entre personas | Pagador + Tomador (lado a lado), Método de pago (si Jose/Caro), Categoría (si Jose/Caro)         |

### Reglas de Deuda (`PAGO_DEUDA`)

- `Pagador=me` + `Contraparte=other` → **cash-out** (yo pago)
- `Pagador=other` + `Contraparte=me` → **cash-in** (me pagan)
- `Pagador ≠ Contraparte` (obligatorio)

### Reglas de Compartido (`COMPARTIDO`)

- Los participantes pueden dividirse **equitativamente** o por **porcentajes**
- La suma de porcentajes debe ser 100%
- Al cambiar pagador, los participantes se resetean completamente

---

## 👥 Usuarios

| Nombre         | Familia |
| -------------- | ------- |
| Jose           | ✅      |
| Caro           | ✅      |
| Maria Isabel   | ❌      |
| Papá Caro      | ❌      |
| Mamá Caro      | ❌      |
| Daniel         | ❌      |
| Yury           | ❌      |
| Prebby         | ❌      |
| Kelly Carolina | ❌      |

> El frontend usa `DEFAULT_USERS` con estos nombres (la ortografía exacta importa).

---

## 🏷️ Categorías

Campo **obligatorio** para:

- `FAMILIAR` (siempre)
- `PAGO_DEUDA` (solo si pagador es Jose o Caro)

Opciones disponibles:

```text
Pago de SOAT/impuestos/mantenimiento
Carro - Seguro
Uber/Gasolina/Peajes/Parqueaderos
Casa - Gastos fijos
Casa - Cositas para casa
Casa - Provisionar mes entrante
Kellys
Mercado
Ahorros para SOAT/impuestos/mantenimiento
Ahorros para cosas de la casa
Ahorros para vacaciones
Ahorros para regalos
Salidas juntos
Vacaciones
Inversiones Caro
Inversiones Jose
Inversiones Juntos
Regalos
Caro - Gastos fijos
Caro - Vida cotidiana
Jose - Gastos fijos
Jose - Vida cotidiana
Gastos médicos
Caro - Imprevistos
Jose - Imprevistos
Casa - Imprevistos
Carro - Imprevistos
Préstamo
```

---

## 💳 Métodos de Pago

**Reglas:**

- `FAMILIAR`: Campo **siempre obligatorio**
- `COMPARTIDO` / `PAGO_DEUDA`: Campo **obligatorio** solo si `Pagador` es Jose o Caro. Si no, se oculta.

| Métodos disponibles (Jose y Caro) |
| --------------------------------- |
| Débito Jose                       |
| AMEX Jose                         |
| MasterCard Oro Jose               |
| Débito Caro                       |
| Nu Caro                           |

> Ambos usuarios pueden seleccionar cualquier método (para pagos cruzados).

---

## 📁 Estructura del Frontend

```text
registrar-movimiento/
├── index.html
├── styles.css
├── app.js
└── staticwebapp.config.json
```

---

## 📱 Responsiveness

- Layout mobile-first: 1 columna por defecto
- Grid de 2 columnas solo en `@media (min-width: 769px)`
- `font-size: 16px` en inputs/selects para evitar zoom en iOS
- Safe-area padding con `max(24px, env(safe-area-inset-*))` para notch/bordes

---

## 🔐 Autenticación

**Note:** This section describes the legacy n8n API key approach.
For the current session-based authentication system, see `01_AUTH_PHASE.md`.

The n8n webhook still uses API key authentication for server-to-server calls.

### En el Frontend

El API key se gestiona mediante **GitHub Secrets** para no exponerlo en el código fuente:

1. En `app.js` se usa un placeholder:

   ```javascript
   const X_API_KEY = "__X_API_KEY__";
   ```

2. El workflow de GitHub Actions reemplaza el placeholder antes del deploy:

   ```yaml
   - name: Replace API Key
     run: |
       sed -i 's/__X_API_KEY__/${{ secrets.N8N_API_KEY }}/g' registrar-movimiento/app.js
   ```

3. Todas las peticiones POST incluyen:

   ```http
   X-API-Key: <valor-del-secret>
   ```

### En n8n

- CORS debe permitir el header `X-API-Key` en `Access-Control-Allow-Headers`
- El webhook valida el header antes de procesar

---

## 🐛 Issues Conocidos / TODO

- [x] ~~Remover feature "Agregar nuevo usuario"~~
- [x] ~~Agregar dropdown de Categoría requerido~~
- [x] ~~Hacer Método de pago requerido si pagador es Jose o Caro~~
- [x] ~~Asegurar layout móvil limpio (una columna)~~
- [x] ~~Mover X_API_KEY a GitHub Secrets~~
- [x] ~~Ocultar pagador para tipo FAMILIAR~~
- [x] ~~Pagador + Tomador lado a lado para PAGO_DEUDA~~
- [x] ~~Evitar `undefined` en columnas: usar fallbacks como `categoria || ""`~~

---

## 🤖 Documentation Context

This document describes **Phase 0: n8n Movement Registration**.

**Current implementation status:**

- ✅ Authentication moved to PostgreSQL (Phase 1)
- ✅ Movement registration still uses n8n → Google Sheets
- ⏳ Movement migration to PostgreSQL pending (Phase 2)

**Related documentation:**

- `01_AUTH_PHASE.md` - Current auth implementation with Go backend + PostgreSQL
- `FUTURE_VISION.md` - Long-term product vision and roadmap
- Phase 2 (planned) - Migrate movements to PostgreSQL, implement families/contacts

**Editing guidelines:**

- Make **minimal and safe** edits
- Maintain exact names, endpoints, and auth headers
- Provide changes as patches or file-by-file edits
- **Do not introduce frameworks**; maintain vanilla HTML/CSS/JS
- Ensure CORS preflight works with `X-API-Key`
- **NEVER** include actual API key values in code; use placeholder `__X_API_KEY__`
