# Caetutti Dynamics — Dropshipping Storefront (Paraguay)

> **Stack:** Next.js 14 + Express + Playwright + sql.js (SQLite) + Docker
> **Infra:** Oracle Cloud Free Tier (ARM 24GB RAM, 200GB SSD) — **$0/mes para siempre**

---

## 🎯 Qué hace

- **Catálogo sincronizado** desde Dropi cada 10 min (Playwright headless)
- **Filtros de seguridad**: bloquea contenido adulto, productos sin imagen, stock 0, precios irreales
- **Precios automáticos**: margen configurable + ofertas rotativas 24h (5% sobre costo)
- **Checkout contra entrega**: crea orden en Dropi vía UI automatizada
- **Admin panel**: logs de sync, proveedores, envío, stats, sync manual
- **Geografía PY**: departamentos/ciudades con tarifas de envío editables

---

## 🏗 Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│  Oracle Cloud Free Tier (VM.Standard.A1.Flex - São Paulo)      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Nginx      │  │  Frontend    │  │     Backend          │  │
│  │  :80/:443    │◄─┤  Next.js     │  │  Express + Playwright│  │
│  │  SSL/Proxy   │  │  :3000       │◄─┤  :4000               │  │
│  └──────────────┘  └──────────────┘  │  - Sync Worker       │  │
│         ▲                              │  - SQLite (/data)    │  │
│         │                              └──────────────────────┘  │
│         │                                      ▲                │
│         │                                      │                │
│  ┌──────┴──────┐                      ┌─────────┴────────┐     │
│  │  Cloudflare │                      │   Dropi API      │     │
│  │  Tunnel     │                      │   (scraping)     │     │
│  │  (opcional) │                      │                  │     │
│  └─────────────┘                      └──────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Deploy en 15 min (Oracle Cloud Free Tier)

### 1. Crear cuenta Oracle Cloud
- Regístrate en [cloud.oracle.com](https://cloud.oracle.com) (requiere tarjeta para verificación, **no cobran**)
- Selecciona región **São Paulo (sa-saopaulo-1)** — latencia óptima para Paraguay

### 2. Crear instancia VM
```
Shape: VM.Standard.A1.Flex (ARM Ampere)
OCPUs: 4    (máx 4 gratis)
RAM: 24 GB  (máx 24 GB gratis)
Image: Ubuntu 22.04 o 24.04
Boot volume: 200 GB (máx 200 GB gratis)
SSH key: tu clave pública
```
- Abre puertos en **Security List**: 22 (SSH), 80 (HTTP), 443 (HTTPS)

### 3. Conectar y ejecutar setup
```bash
ssh ubuntu@<TU_IP_PUBLICA>

# Opción A: Script automático (recomendado)
curl -fsSL https://raw.githubusercontent.com/TU_USUARIO/caetutti-dynamics/main/setup-oracle.sh | sudo bash -s -- --domain tu-dominio.com

# Opción B: Manual paso a paso
git clone https://github.com/TU_USUARIO/caetutti-dynamics.git
cd caetutti-dynamics
chmod +x setup-oracle.sh
sudo ./setup-oracle.sh --domain tu-dominio.com
```

### 4. Configurar credenciales
```bash
nano /home/appuser/caetutti-dynamics/.env
# Edita: DROPI_EMAIL, DROPI_PASSWORD, ADMIN_EMAIL, ADMIN_PASSWORD, etc.

cd /home/appuser/caetutti-dynamics
docker compose restart
```

### 5. Verificar
- Frontend: `https://tu-dominio.com`
- API Health: `https://tu-dominio.com/api/health`
- Admin: `https://tu-dominio.com/admin` (login con ADMIN_EMAIL/PASSWORD)

---

## ☁️ Cloudflare Tunnel (Opcional - DNS + HTTPS gratis sin IP fija)

Si no quieres manejar Certbot / Let's Encrypt / IP fija:

1. En Cloudflare Dashboard → Zero Trust → Networks → Tunnels → Create Tunnel
2. Copia el **Token** del tunnel
3. Ejecuta:
```bash
sudo ./setup-oracle.sh --cloudflare-token TU_TOKEN_AQUI
```
4. En DNS de Cloudflare: CNAME `caetutti` → `<tunnel-id>.cfargotunnel.com` (Proxy ON)

---

## 📁 Estructura del proyecto

```
caetutti-dynamics/
├── backend/
│   ├── src/
│   │   ├── index.ts           # Entry point Express + worker
│   │   ├── routes.ts          # API routes (productos, órdenes, admin, geo)
│   │   ├── db.ts              # sql.js SQLite + migraciones + seed geo
│   │   ├── dropi-navigator.ts # Playwright scraping + order creation
│   │   ├── sync-worker.ts     # Sync catálogo + dedupe + content filter
│   │   ├── safe-filter.ts     # Filtro sexo/adultos (SQL + JS)
│   │   ├── dedupe.ts          # Elimina duplicados por proveedor/precio
│   │   └── order-creator.ts   # Crea orden en Dropi vía UI
│   └── package.json
├── frontend/
│   ├── app/                   # Next.js 14 App Router
│   │   ├── page.tsx           # Home (hero, categorías, ofertas, editorial)
│   │   ├── productos/         # Listado + filtros
│   │   ├── producto/[slug]/   # Detalle producto
│   │   ├── carrito/           # Carrito persistente
│   │   ├── checkout/          # Formulario orden
│   │   ├── pedido/[id]/       # Confirmación
│   │   └── admin/             # Panel admin
│   ├── components/            # UI components
│   └── package.json
├── Dockerfile                 # Multi-stage build
├── docker-compose.yml         # Orquestación completa
├── nginx.conf                 # Reverse proxy + SSL + cache + rate limit
├── ecosystem.config.js        # PM2 (alternativa sin Docker)
├── setup-oracle.sh            # Setup automatizado VM
├── .env.example               # Plantilla variables entorno
└── .gitignore
```

---

## ⚙️ Variables de entorno clave

| Variable | Requerida | Default | Descripción |
|----------|-----------|---------|-------------|
| `DROPI_EMAIL` | ✅ | - | Email cuenta Dropi vendedor |
| `DROPI_PASSWORD` | ✅ | - | Password cuenta Dropi |
| `DROPI_USER_ID` | ❌ | `87773` | Sub del JWT (opcional) |
| `ADMIN_EMAIL` | ✅ | - | Login panel admin |
| `ADMIN_PASSWORD` | ✅ | - | **Clave fuerte** |
| `PRICE_MARGIN_PERCENT` | ❌ | `35` | Margen sobre costo proveedor |
| `SYNC_INTERVAL_MIN` | ❌ | `10` | Minutos entre syncs |
| `SYNC_MAX_PRODUCTS` | ❌ | `4000` | Límite productos por sync |
| `SHIPPING_DEFAULT_PYG` | ❌ | `60000` | Envío fallback (Gs) |
| `DATABASE_FILE` | ❌ | `/data/caetutti.db` | Path SQLite (volumen Docker) |
| `TUNNEL_TOKEN` | ❌ | - | Cloudflare Tunnel token |

---

## 🔧 Comandos útiles

```bash
# Ver logs
docker compose -f /home/appuser/caetutti-dynamics/docker-compose.yml logs -f backend
docker compose logs -f frontend
docker compose logs -f nginx

# Reiniciar servicios
docker compose restart backend
docker compose restart frontend

# Sync manual catálogo
curl -X POST https://tu-dominio.com/api/admin/sync-now \
  -H "X-Admin-Token: $(docker exec caetutti-backend cat /data/settings | grep admin_session_token)"

# Backup manual DB
cp /data/caetutti.db /data/backups/caetutti-manual-$(date +%F).db

# Actualizar código
cd /home/appuser/caetutti-dynamics
git pull
docker compose build --pull
docker compose up -d

# Ver estado contenedores
docker compose ps

# Entrar a contenedor backend
docker exec -it caetutti-backend bash
```

---

## 🛡 Seguridad

- **Fail2ban**: SSH + nginx rate limits
- **UFW**: Solo puertos 22, 80, 443 abiertos
- **Non-root containers**: Usuario `appuser` (UID 999)
- **Rate limiting**: API 30 req/s, login 5 req/min
- **Security headers**: CSP, HSTS, X-Frame-Options, etc.
- **HTTPS obligatorio**: Let's Encrypt o Cloudflare Tunnel
- **Variables sensibles**: Solo en `.env` (chmod 600, nunca en Git)

---

## 📊 Monitoreo básico

```bash
# Healthchecks
curl https://tu-dominio.com/healthz
curl https://tu-dominio.com/api/health

# Stats admin (requiere token)
curl https://tu-dominio.com/api/admin/stats -H "X-Admin-Token: <token>"

# Sync logs
curl https://tu-dominio.com/api/admin/sync-logs -H "X-Admin-Token: <token>"

# Uso recursos
docker stats
htop
df -h /data
```

---

## 🔄 Flujo de orden (Cliente → Dropi)

1. Usuario agrega productos al carrito (localStorage + contexto React)
2. Checkout: formulario con datos + departamento/ciudad (autocomplete)
3. `POST /api/orders` → Valida stock, precio, seguridad, calcula envío por zona
4. Guarda orden en SQLite (`status: procesando`)
5. **Async**: `createOrderInDropi(orderId)` → Playwright:
   - Login Dropi (si no hay sesión)
   - Busca producto → "Enviar al cliente"
   - Rellena cliente, dirección, departamento, ciudad
   - Selecciona transportadora más barata con cotización válida
   - Envía → Captura `dropiOrderId`
6. Actualiza orden local: `status: enviada_a_dropi`, `dropi_order_id`
7. Usuario ve confirmación con número de orden `CT-XXXXXX`

---

## 🧪 Desarrollo local

```bash
# Requisitos: Node 20, Docker, Docker Compose

# Backend
cd backend
cp .env.example .env   # Edita con tus credenciales Dropi
npm install
npm run dev            # ts-node src/index.ts (puerto 4000)

# Frontend (otra terminal)
cd frontend
npm install
npm run dev            # Next.js (puerto 3000)

# O todo con Docker
docker compose up --build
```

---

## 📝 Licencia

Uso privado — Caetutti Dynamics.

---

## 🤝 Soporte

¿Problemas? Revisa logs:
```bash
docker compose logs -f backend | grep -E "(ERROR|WARN|DROPI|SYNC|ORDER)"
```

Para mejoras: abre issue en el repo o pedime directamente.