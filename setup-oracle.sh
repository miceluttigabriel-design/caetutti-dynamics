#!/usr/bin/env bash
# =============================================================================
# Caetutti Dynamics - Setup Script para Oracle Cloud Free Tier (Ubuntu 22.04/24.04)
# Ejecutar como: curl -fsSL https://raw.githubusercontent.com/tu-usuario/caetutti-dynamics/main/setup-oracle.sh | bash
# O clonar repo y: chmod +x setup-oracle.sh && ./setup-oracle.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/tu-usuario/caetutti-dynamics.git"  # CAMBIAR
PROJECT_DIR="/home/appuser/caetutti-dynamics"
DATA_DIR="/data"
LOG_DIR="/var/log/caetutti"
BACKUP_DIR="/data/backups"
APP_USER="appuser"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $*"; }

# -----------------------------------------------------------------------------
# Verificaciones iniciales
# -----------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse como root (sudo)."
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        warn "Este script está probado en Ubuntu 22.04/24.04. Continuando..."
    fi
    log "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
}

# -----------------------------------------------------------------------------
# Crear usuario de aplicación
# -----------------------------------------------------------------------------
setup_user() {
    log "Configurando usuario $APP_USER..."
    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -m -d "/home/$APP_USER" -s /bin/bash "$APP_USER"
        usermod -aG docker "$APP_USER" 2>/dev/null || true
        log "Usuario $APP_USER creado"
    else
        log "Usuario $APP_USER ya existe"
    fi

    # Passwordless sudo para comandos específicos
    cat > /etc/sudoers.d/caetutti <<EOF
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx, /usr/bin/docker compose *, /usr/bin/docker pull *, /bin/cp /data/caetutti.db /data/backups/*
EOF
    chmod 440 /etc/sudoers.d/caetutti
}

# -----------------------------------------------------------------------------
# Instalar dependencias de sistema
# -----------------------------------------------------------------------------
install_system_deps() {
    log "Actualizando paquetes e instalando dependencias..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        git \
        gnupg2 \
        ca-certificates \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        ufw \
        fail2ban \
        htop \
        ncdu \
        jq \
        cron \
        logrotate \
        nginx \
        certbot \
        python3-certbot-nginx

    log "Dependencias base instaladas"
}

# -----------------------------------------------------------------------------
# Instalar Docker + Docker Compose
# -----------------------------------------------------------------------------
install_docker() {
    log "Instalando Docker..."

    # Repositorio oficial Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Configurar Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "metrics-addr": "127.0.0.1:9323"
}
EOF

    systemctl enable --now docker
    log "Docker instalado y configurado"
}

# -----------------------------------------------------------------------------
# Configurar firewall (UFW)
# -----------------------------------------------------------------------------
setup_firewall() {
    log "Configurando firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    # ufw allow from 10.0.0.0/8 to any port 3000 comment 'Frontend internal'  # opcional
    # ufw allow from 10.0.0.0/8 to any port 4000 comment 'Backend internal'   # opcional
    ufw --force enable
    log "Firewall configurado (puertos 22, 80, 443 abiertos)"
}

# -----------------------------------------------------------------------------
# Configurar fail2ban
# -----------------------------------------------------------------------------
setup_fail2ban() {
    log "Configurando fail2ban..."
    cat > /etc/fail2ban/jail.d/caetutti.conf <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 3600
EOF
    systemctl enable --now fail2ban
    log "fail2ban configurado"
}

# -----------------------------------------------------------------------------
# Clonar/actualizar repositorio
# -----------------------------------------------------------------------------
setup_repo() {
    log "Configurando repositorio en $PROJECT_DIR..."

    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        sudo -u "$APP_USER" git clone "$REPO_URL" "$PROJECT_DIR"
        log "Repositorio clonado"
    else
        cd "$PROJECT_DIR"
        sudo -u "$APP_USER" git fetch origin
        sudo -u "$APP_USER" git reset --hard origin/main
        log "Repositorio actualizado"
    fi
}

# -----------------------------------------------------------------------------
# Configurar directorios y permisos
# -----------------------------------------------------------------------------
setup_directories() {
    log "Creando directorios persistentes..."
    mkdir -p "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR" "/home/$APP_USER/certbot/conf" "/home/$APP_USER/certbot/www"
    chown -R "$APP_USER:$APP_USER" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR" "/home/$APP_USER/certbot"
    chmod 750 "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
    log "Directorios creados"
}

# -----------------------------------------------------------------------------
# Configurar .env
# -----------------------------------------------------------------------------
setup_env() {
    log "Configurando variables de entorno..."
    cd "$PROJECT_DIR"

    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            warn "Archivo .env creado desde .env.example. ¡EDÍTALO con tus credenciales!"
        else
            cat > .env <<'EOF'
# =============================================================================
# Caetutti Dynamics - Variables de Entorno
# COPIA ESTE ARCHIVO A .env Y EDITA LOS VALORES
# =============================================================================

# --- Dropi Credenciales (OBLIGATORIO) ---
DROPI_EMAIL=tu@email.com
DROPI_PASSWORD=tu_password_dropi
DROPI_USER_ID=87773
DROPI_LOGIN_URL=https://app.dropi.com.py/

# --- Admin Panel ---
ADMIN_EMAIL=admin@tudominio.com
ADMIN_PASSWORD=cambia_esta_clave_por_una_segura

# --- Tienda ---
STORE_NAME=Caetutti
PRICE_MARGIN_PERCENT=35
CURRENCY=PYG

# --- Sync Worker ---
SYNC_ENABLED=true
SYNC_INTERVAL_MIN=10
SYNC_MAX_PRODUCTS=4000

# --- Envío ---
SHIPPING_DEFAULT_PYG=60000

# --- Runtime ---
NODE_ENV=production
HEADLESS=true
PORT=4000
DATABASE_FILE=/data/caetutti.db

# --- Cloudflare Tunnel (opcional) ---
# TUNNEL_TOKEN=tu_token_de_cloudflare_tunnel
EOF
            chown "$APP_USER:$APP_USER" .env
            chmod 600 .env
            warn "Archivo .env creado con valores por defecto. ¡EDÍTALO!"
        fi
    else
        log ".env ya existe, saltando..."
    fi
}

# -----------------------------------------------------------------------------
# Build y deploy con Docker Compose
# -----------------------------------------------------------------------------
deploy_app() {
    log "Construyendo y desplegando aplicación..."
    cd "$PROJECT_DIR"

    # Build imágenes
    sudo -u "$APP_USER" docker compose build --pull

    # Levantar servicios
    sudo -u "$APP_USER" docker compose up -d

    # Esperar healthchecks
    log "Esperando healthchecks..."
    sleep 10

    # Verificar estado
    sudo -u "$APP_USER" docker compose ps

    log "Aplicación desplegada"
}

# -----------------------------------------------------------------------------
# Configurar Nginx en host (proxy para Docker)
# -----------------------------------------------------------------------------
setup_nginx_host() {
    log "Configurando Nginx en host..."

    cat > /etc/nginx/sites-available/caetutti <<'EOF'
# Caetutti - Proxy a Docker containers
upstream frontend {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream backend {
    server 127.0.0.1:4000;
    keepalive 32;
}

# Rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;

server {
    listen 80;
    listen [::]:80;
    server_name _;

    # ACME challenge
    location /.well-known/acme-challenge/ {
        root /home/appuser/certbot/www;
    }

    location /healthz {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    # SSL - Certbot llenará estos paths
    ssl_certificate /etc/letsencrypt/live/caetutti.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/caetutti.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Static assets
    location /_next/static/ {
        proxy_pass http://frontend;
        proxy_cache_valid 200 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # API
    location /api/ {
        limit_req zone=api burst=50 nodelay;
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /api/admin/login {
        limit_req zone=login burst=3 nodelay;
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Frontend
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    ln -sf /etc/nginx/sites-available/caetutti /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Test config
    nginx -t && systemctl reload nginx
    log "Nginx configurado en host"
}

# -----------------------------------------------------------------------------
# Configurar SSL con Certbot (Let's Encrypt)
# -----------------------------------------------------------------------------
setup_ssl() {
    local DOMAIN="${1:-}"

    if [[ -z "$DOMAIN" ]]; then
        warn "Dominio no proporcionado. Saltando SSL. Ejecuta: sudo certbot --nginx -d tu-dominio.com"
        return
    fi

    log "Obteniendo certificado SSL para $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --redirect

    # Renovación automática
    systemctl enable --now certbot.timer
    log "SSL configurado para $DOMAIN"
}

# -----------------------------------------------------------------------------
# Configurar backups automáticos
# -----------------------------------------------------------------------------
setup_backups() {
    log "Configurando backups automáticos..."

    cat > /etc/cron.d/caetutti-backup <<'EOF'
# Backup diario de SQLite a las 3:00 AM
0 3 * * * appuser /bin/bash -c 'cp /data/caetutti.db /data/backups/caetutti-$(date +\%F).db && find /data/backups -name "caetutti-*.db" -mtime +30 -delete'

# Backup semanal comprimido los domingos a las 4:00 AM
0 4 * * 0 appuser /bin/bash -c 'cd /data && tar -czf backups/caetutti-weekly-$(date +\%F).tar.gz caetutti.db && find /data/backups -name "caetutti-weekly-*.tar.gz" -mtime +90 -delete'
EOF

    chmod 644 /etc/cron.d/caetutti-backup
    log "Backups automáticos configurados (diario + semanal)"
}

# -----------------------------------------------------------------------------
# Configurar logrotate
# -----------------------------------------------------------------------------
setup_logrotate() {
    log "Configurando rotación de logs..."

    cat > /etc/logrotate.d/caetutti <<'EOF'
/var/log/caetutti/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 appuser appuser
    sharedscripts
    postrotate
        docker compose -f /home/appuser/caetutti-dynamics/docker-compose.yml restart frontend backend 2>/dev/null || true
    endscript
}

/var/log/nginx/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 www-data adm
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF

    log "Logrotate configurado"
}

# -----------------------------------------------------------------------------
# Configurar Cloudflare Tunnel (opcional)
# -----------------------------------------------------------------------------
setup_cloudflare_tunnel() {
    local TOKEN="${1:-}"

    if [[ -z "$TOKEN" ]]; then
        info "Cloudflare Tunnel: no token proporcionado. Saltando."
        info "Para activar: crea tunnel en dash.cloudflare.com y ejecuta:"
        info "  sudo ./setup-oracle.sh --cloudflare-token TU_TOKEN"
        return
    fi

    log "Configurando Cloudflare Tunnel..."

    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=appuser
ExecStart=/usr/bin/docker run --rm --name cloudflared \
    --network host \
    cloudflare/cloudflared:latest tunnel --no-autoupdate run --token $TOKEN
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now cloudflared
    log "Cloudflare Tunnel activado"
}

# -----------------------------------------------------------------------------
# Verificación final
# -----------------------------------------------------------------------------
verify_deployment() {
    log "Verificando despliegue..."

    cd "$PROJECT_DIR"
    sudo -u "$APP_USER" docker compose ps

    echo
    info "=== Healthchecks ==="
    curl -sf http://localhost:4000/api/health && echo " ✓ Backend OK" || echo " ✗ Backend FAIL"
    curl -sf http://localhost:3000 >/dev/null && echo " ✓ Frontend OK" || echo " ✗ Frontend FAIL"
    curl -sf http://localhost/healthz >/dev/null && echo " ✓ Nginx OK" || echo " ✗ Nginx FAIL"

    echo
    info "=== URLs ==="
    echo "  Frontend:  http://$(curl -s ifconfig.me 2>/dev/null || echo 'TU_IP')"
    echo "  Backend:   http://$(curl -s ifconfig.me 2>/dev/null || echo 'TU_IP'):4000/api"
    echo "  Admin:     http://$(curl -s ifconfig.me 2>/dev/null || echo 'TU_IP')/admin"
    echo "  Health:    http://$(curl -s ifconfig.me 2>/dev/null || echo 'TU_IP')/healthz"
    echo
    info "=== Próximos pasos ==="
    echo "  1. Edita .env con tus credenciales reales: nano $PROJECT_DIR/.env"
    echo "  2. Reinicia: cd $PROJECT_DIR && docker compose restart"
    echo "  3. Configura dominio: sudo certbot --nginx -d tu-dominio.com"
    echo "  4. (Opcional) Cloudflare Tunnel: sudo ./setup-oracle.sh --cloudflare-token TU_TOKEN"
    echo
    log "¡Setup completado!"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local DOMAIN=""
    local CF_TOKEN=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --cloudflare-token)
                CF_TOKEN="$2"
                shift 2
                ;;
            --help|-h)
                echo "Uso: $0 [--domain TU_DOMINIO] [--cloudflare-token TU_TOKEN]"
                exit 0
                ;;
            *)
                error "Opción desconocida: $1"
                exit 1
                ;;
        esac
    done

    log "=== Caetutti Dynamics - Oracle Cloud Setup ==="
    check_root
    check_ubuntu

    setup_user
    install_system_deps
    install_docker
    setup_firewall
    setup_fail2ban
    setup_directories
    setup_repo
    setup_env
    deploy_app
    setup_nginx_host
    setup_backups
    setup_logrotate

    [[ -n "$DOMAIN" ]] && setup_ssl "$DOMAIN"
    [[ -n "$CF_TOKEN" ]] && setup_cloudflare_tunnel "$CF_TOKEN"

    verify_deployment
}

main "$@"