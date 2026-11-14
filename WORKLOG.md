# Worklog — Caetutti Dynamics

## Estado: FUNCIONANDO EN LOCAL (modo prueba) — falta pasar a envío real

### Servicios
- Backend: http://localhost:4000 (Express + TypeScript + SQLite/sql.js + Playwright)
- Frontend: http://localhost:3000 (Next.js App Router + Tailwind)
- BD: `backend/data/caetutti.db` (~5.700 productos visibles, ~6.200 totales)

### Logros de esta sesión
1. **Descubierto el bloqueo real del botón “Enviar al cliente”**: no era un problema de
   selectores, era que Dropi exige **ganancia positiva**. El precio que se escribe es el
   total que paga el cliente; Dropi descuenta costo de proveedor, envío real y una
   comisión del 5% sobre `(total − envío)`. Con el precio anterior (costo + 35%) la ganancia
   era negativa y el botón quedaba deshabilitado.
   - Fórmula verificada: `ganancia = total − costo − envío − 5% × (total − envío)`
   - Precio mínimo de Dropi ≈ `envío + costo / 0.95`.
2. **Flujo de creación en Dropi automatizado de punta a punta** (`dropi-navigator.ts`):
   - autocomplete con teclado (`ArrowDown` + `Enter`); el clic no confirma el valor
   - hay que pulsar **“Agregar producto”** para que el costo real entre en el resumen
   - **no** pulsar la opción de tasa: borra la ciudad seleccionada
   - la transportadora se elige con `dispatchEvent('click')` (un carrusel tapa el área)
   - el checkbox de notas está fuera del viewport: se activa por DOM
3. **Envío por zona** (decisión del usuario): el producto conserva su precio (costo + 35%)
   y el checkout suma el envío del departamento/ciudad. El total que paga el cliente es
   el mismo que se setea en Dropi.
4. **Carritos con varios productos**: Dropi acepta un solo producto por orden, así que el
   pedido se divide en una orden de Dropi por producto y el envío se cobra por producto.
   Verificado con un pedido de 2 productos (uno con cantidad 2): ambas órdenes con ganancia
   positiva (`simulada`, `createDisabled=false`).
5. **Filtro sex shop / adultos** (`src/safe-filter.ts`): 3 capas (sync, catálogo, checkout).
   59 productos bloqueados, 0 visibles. “Unisex”/“Unissex” siguen visibles (no son adultos).
6. **Deduplicación por proveedor** (`src/dedupe.ts`): se muestra un solo producto por
   título, priorizando proveedor preferido → verificado por Dropi → plan → confiabilidad
   → mejor precio → más stock. 170 repetidos ocultos.
7. **Panel admin protegido**: login con token (`x-admin-token`); el listado de pedidos ya
   no es público.
8. **Cotizaciones de envío reales** por departamento (`quote-shipping.ts`) + endpoint
   `POST /api/admin/shipping-rates`.

### Estado de las pruebas
| Prueba | Resultado |
|---|---|
| Pedido simple (1 producto) en seco | ✅ `simulada`, `createDisabled=false`, ganancia ₲2.861 |
| Pedido con 2 productos (uno x2) en seco | ✅ 2 órdenes en Dropi, ambas con ganancia positiva |
| Checkout web (carrito → checkout → pedido) | ✅ envío ₲40.000, total ₲80.500 |
| Página `/pedido/[id]` | ✅ muestra productos, envío y total |
| Auditoría sex shop (24 términos) | ✅ 0 resultados adultos |
| Pedido real en Dropi | ⏳ **pendiente de aprobación del usuario** |

### Pendiente
1. Pedir aprobación y enviar **un** pedido real de prueba (con `ORDER_DRY_RUN=false`).
2. Aplicar las cotizaciones reales de envío (`data/shipping-quotes.json` → endpoint admin).
3. Revisar que las tarifas por zona cubran el envío real (si no, la ganancia se come el margen).
4. Deploy en VPS (4–6 USD/mes) con Chromium + Xvfb + Nginx (ver README).

### Archivos clave
- `backend/src/dropi-navigator.ts` — navegador Playwright (login, catálogo, cajón de orden)
- `backend/src/order-creator.ts` — divide pedidos en órdenes de Dropi y las crea
- `backend/src/safe-filter.ts` — bloqueo de contenido sex shop / adultos
- `backend/src/dedupe.ts` — repetidos por proveedor
- `backend/src/sync-worker.ts` — sincronización cada 10 min + filtros
- `backend/src/routes.ts` — API REST + auth admin
- `backend/maintenance.ts`, `backend/quote-shipping.ts` — tareas de mantenimiento

### Credenciales
- Solo en `backend/.env`. Nunca subirlas al repositorio.
