#!/usr/bin/env bash
# =============================================================================
# Caetutti Dynamics - Setup Script para Home Server (Ubuntu 22.04/24.04)
# Roda como teu user (NÃO root):  ./setup-home.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuração
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/miceluttigabriel-design/caetutti-dynamics.git"
PROJECT_DIR="$HOME/caetutti-dynamics"
DATA_DIR="$HOME/caetutti-data"
LOG_DIR="$HOME/caetutti-logs"
BACKUP_DIR="$HOME/caetutti-backups"
UID_GID=$(id -u):$(id -g)

# Cores
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
# Verificações iniciais
# -----------------------------------------------------------------------------
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        error "NÃO rode como root! Rode como teu user normal: ./setup-home.sh"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        warn "Testado em Ubuntu 22.04/24.04. Continuando..."
    fi
    log "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
}

check_docker_group() {
    if ! groups | grep -q docker; then
        error "Teu user não está no grupo 'docker'. Rode: sudo usermod -aG docker \$USER && logout/login"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Instalar dependências de sistema (requer sudo)
# -----------------------------------------------------------------------------
install_system_deps() {
    log "Instalando dependências de sistema (sudo)..."
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        docker.io \
        docker-compose-v2 \
        git \
        curl \
        jq \
        htop \
        ncdu \
        ufw \
        fail2ban \
        chromium-browser \
        fonts-liberation \
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
        libatspi2.0-0

    # Habilita Docker
    sudo systemctl enable --now docker

    # Configura Docker daemon
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "userland-proxy": false
}
EOF
    sudo systemctl restart docker

    log "Dependências instaladas"
}

# -----------------------------------------------------------------------------
# Configurar firewall (apenas SSH local)
# -----------------------------------------------------------------------------
setup_firewall() {
    log "Configurando firewall (UFW)..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp comment 'SSH'
    # Cloudflare Tunnel faz saída, não precisa abrir 80/443
    sudo ufw --force enable
    log "Firewall configurado (apenas porta 22 aberta)"
}

# -----------------------------------------------------------------------------
# Configurar fail2ban
# -----------------------------------------------------------------------------
setup_fail2ban() {
    log "Configurando fail2ban..."
    sudo tee /etc/fail2ban/jail.d/caetutti.conf > /dev/null <<'EOF'
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
EOF
    sudo systemctl enable --now fail2ban
    log "fail2ban configurado"
}

# -----------------------------------------------------------------------------
# Criar diretórios
# -----------------------------------------------------------------------------
setup_directories() {
    log "Criando diretórios persistentes..."
    mkdir -p "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
    chmod 750 "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
    log "Diretórios criados em $HOME"
}

# -----------------------------------------------------------------------------
# Clonar/atualizar repositório
# -----------------------------------------------------------------------------
setup_repo() {
    log "Configurando repositório em $PROJECT_DIR..."

    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        git clone "$REPO_URL" "$PROJECT_DIR"
        log "Repositório clonado"
    else
        cd "$PROJECT_DIR"
        git fetch origin
        git reset --hard origin/main
        log "Repositório atualizado"
    fi
}

# -----------------------------------------------------------------------------
# Configurar .env
# -----------------------------------------------------------------------------
setup_env() {
    log "Configurando variáveis de ambiente..."
    cd "$PROJECT_DIR"

    if [[ ! -f .env ]]; then
        cp .env.example .env
        warn "Arquivo .env criado. EDITE com suas credenciais REAIS:"
        warn "  nano $PROJECT_DIR/.env"
    else
        log ".env já existe"
    fi

    if [[ ! -f .cloudflare.env ]]; then
        cp .cloudflare.env.example .cloudflare.env
        warn "Arquivo .cloudflare.env criado. EDITE com TUNNEL_TOKEN:"
        warn "  nano $PROJECT_DIR/.cloudflare.env"
    else
        log ".cloudflare.env já existe"
    fi
}

# -----------------------------------------------------------------------------
# Build e deploy
# -----------------------------------------------------------------------------
deploy_app() {
    log "Construindo e deployando aplicação..."
    cd "$PROJECT_DIR"

    # Build imagens
    docker compose -f docker-compose.home.yml build --pull

    # Levantar serviços
    docker compose -f docker-compose.home.yml up -d

    # Esperar healthchecks
    log "Aguardando healthchecks..."
    sleep 15

    # Verificar estado
    docker compose -f docker-compose.home.yml ps

    log "Aplicação deployada"
}

# -----------------------------------------------------------------------------
# Configurar backups automáticos (cron)
# -----------------------------------------------------------------------------
setup_backups() {
    log "Configurando backups automáticos..."

    # Script de backup
    cat > "$HOME/backup-caetutti.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DATA_DIR="$HOME/caetutti-data"
BACKUP_DIR="$HOME/caetutti-backups"
DATE=$(date +%F)

mkdir -p "$BACKUP_DIR"

# Backup diário SQLite
cp "$DATA_DIR/caetutti.db" "$BACKUP_DIR/caetutti-$DATE.db"

# Manter últimos 30 dias
find "$BACKUP_DIR" -name "caetutti-*.db" -mtime +30 -delete

# Backup semanal comprimido (domingos)
if [[ $(date +%u) -eq 7 ]]; then
    tar -czf "$BACKUP_DIR/caetutti-weekly-$DATE.tar.gz" -C "$DATA_DIR" caetutti.db
    find "$BACKUP_DIR" -name "caetutti-weekly-*.tar.gz" -mtime +90 -delete
fi
EOF
    chmod +x "$HOME/backup-caetutti.sh"

    # Cron job (3 AM diário)
    (crontab -l 2>/dev/null | grep -v "backup-caetutti"; echo "0 3 * * * $HOME/backup-caetutti.sh") | crontab -

    log "Backups automáticos configurados (diário 3AM + semanal domingo)"
}

# -----------------------------------------------------------------------------
# Configurar logrotate
# -----------------------------------------------------------------------------
setup_logrotate() {
    log "Configurando rotação de logs..."

    sudo tee /etc/logrotate.d/caetutti > /dev/null <<EOF
$HOME/caetutti-logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 $USER $USER
    sharedscripts
    postrotate
        docker compose -f $PROJECT_DIR/docker-compose.home.yml restart frontend backend 2>/dev/null || true
    endscript
}
EOF

    log "Logrotate configurado"
}

# -----------------------------------------------------------------------------
# Verificação final
# -----------------------------------------------------------------------------
verify_deployment() {
    log "Verificando deploy..."

    cd "$PROJECT_DIR"
    docker compose -f docker-compose.home.yml ps

    echo
    info "=== Healthchecks ==="
    curl -sf http://localhost:4000/api/health && echo " ✓ Backend OK" || echo " ✗ Backend FAIL"
    curl -sf http://localhost:3000 >/dev/null && echo " ✓ Frontend OK" || echo " ✗ Frontend FAIL"
    curl -sf http://localhost/healthz >/dev/null && echo " ✓ Nginx OK" || echo " ✗ Nginx FAIL"

    echo
    info "=== Próximos passos ==="
    echo "  1. Edita credenciais REAIS: nano $PROJECT_DIR/.env"
    echo "  2. Edita Cloudflare token:  nano $PROJECT_DIR/.cloudflare.env"
    echo "  3. Reinicia: cd $PROJECT_DIR && docker compose -f docker-compose.home.yml restart"
    echo "  4. Testa no navegador: https://teu-dominio.com"
    echo "  5. Admin: https://teu-dominio.com/admin"
    echo
    log "Setup completo! 🎉"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    log "=== Caetutti Dynamics - Home Server Setup ==="
    check_not_root
    check_ubuntu
    check_docker_group

    install_system_deps
    setup_firewall
    setup_fail2ban
    setup_directories
    setup_repo
    setup_env
    deploy_app
    setup_backups
    setup_logrotate

    verify_deployment
}

main "$@"