# =============================================================================
# Caetutti Dynamics - Dockerfile multi-stage para Oracle Cloud Free Tier
# Frontend (Next.js) + Backend (Express + Playwright) + SQLite persistente
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: Build Frontend (Next.js standalone)
# -----------------------------------------------------------------------------
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Cache de dependencias
COPY frontend/package*.json ./
RUN npm ci --prefer-offline --no-audit --no-fund

# Build
COPY frontend/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# -----------------------------------------------------------------------------
# STAGE 2: Build Backend (TypeScript -> JS)
# -----------------------------------------------------------------------------
FROM node:20-alpine AS backend-builder

WORKDIR /app/backend

COPY backend/package*.json ./
RUN npm ci --prefer-offline --no-audit --no-fund

COPY backend/ ./
RUN npm run build

# -----------------------------------------------------------------------------
# STAGE 3: Runtime - Imagen final ligera con Chromium deps
# -----------------------------------------------------------------------------
FROM node:20-slim AS runtime

# ---- Dependencias de sistema para Playwright/Chromium headless ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Chromium deps
    chromium \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    # Utilidades
    ca-certificates \
    curl \
    tini \
    # Limpieza
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Playwright usa Chromium del sistema
ENV PLAYWRIGHT_BROWSERS_PATH=0
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium

# ---- Usuario no-root para seguridad ----
RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser -s /bin/bash appuser

# ---- Directorio de trabajo ----
WORKDIR /app

# ---- Copiar builds ----
COPY --from=frontend-builder /app/frontend/next.config.js ./frontend/
COPY --from=frontend-builder /app/frontend/public ./frontend/public
COPY --from=frontend-builder /app/frontend/.next/standalone ./frontend/
COPY --from=frontend-builder /app/frontend/.next/static ./frontend/.next/static

COPY --from=backend-builder /app/backend/dist ./backend/dist
COPY --from=backend-builder /app/backend/package*.json ./backend/
COPY --from=backend-builder /app/backend/node_modules ./backend/node_modules

# ---- Directorio de datos persistente (SQLite) ----
RUN mkdir -p /data /data/backups && chown -R appuser:appuser /data /app

# ---- Cambiar a usuario no-root ----
USER appuser

# ---- Exponer puertos ----
EXPOSE 3000 4000

# ---- Healthcheck ----
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:4000/api/health || exit 1

# ---- Entry point con tini (manejo de señales) ----
ENTRYPOINT ["tini", "--"]

# ---- Comando por defecto (overridden por docker-compose) ----
CMD ["node", "backend/dist/index.js"]