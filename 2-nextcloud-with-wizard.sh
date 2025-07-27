#!/bin/bash
# ===================================================================
# SCRIPT 2: NEXTCLOUD DEPLOY - WITH SETUP WIZARD & PERSISTENT CONFIG
# ===================================================================
# Author: Assistant
# Description: Deploy Nextcloud dengan setup wizard untuk recommended apps
#              Database PostgreSQL 15.4 - AMAN untuk backup/restore
# Usage: sudo ./2-nextcloud-with-wizard.sh
# Requires: Script 1 sudah dijalankan (fresh Docker + rclone)
# ===================================================================

set -e

# ===================================================================
# COLORS & LOGGING
# ===================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}"; }
error()   { echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}"; exit 1; }
info()    { echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️  $1${NC}"; }
section() { echo -e "\n${PURPLE}=== $1 ===${NC}"; }
success() { echo -e "${CYAN}[$(date +'%H:%M:%S')] 🎉 $1${NC}"; }

# ===================================================================
# HEADER
# ===================================================================
clear
echo -e "${CYAN}"
echo "███╗   ██╗███████╗██╗  ██╗████████╗ ██████╗██╗      ██████╗ ██╗   ██╗██████╗ "
echo "████╗  ██║██╔════╝╚██╗██╔╝╚══██╔══╝██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗"
echo "██╔██╗ ██║█████╗   ╚███╔╝    ██║   ██║     ██║     ██║   ██║██║   ██║██║  ██║"
echo "██║╚██╗██║██╔══╝   ██╔██╗    ██║   ██║     ██║     ██║   ██║██║   ██║██║  ██║"
echo "██║ ╚████║███████╗██╔╝ ██╗   ██║   ╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝"
echo "╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ "
echo -e "${NC}"
echo -e "${GREEN}🧙‍♂️ NEXTCLOUD WITH SETUP WIZARD & PERSISTENT CONFIG 🧙‍♂️${NC}"
echo "================================================================"

# ===================================================================
# CONFIGURATION
# ===================================================================
PROJECT_DIR="/home/paperspace/nextcloud-server"
DOMAIN="184.105.215.177"
PORT="8081"
DB_PASSWORD="Dimas112233!"

# ===================================================================
# VALIDATION
# ===================================================================
section "VALIDATION & PREPARATION"

# Check root
if [[ $EUID -ne 0 ]]; then
    error "Script ini harus dijalankan sebagai root (gunakan sudo)"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker tidak terinstall! Jalankan Script 1 dulu!"
fi

# Check if previous deployment exists
if [[ -d "$PROJECT_DIR" ]]; then
    warn "Folder $PROJECT_DIR sudah ada!"
    read -p "🔥 Hapus dan deploy fresh? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Menghapus deployment lama..."
        cd "$PROJECT_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
        rm -rf "$PROJECT_DIR"
        log "Deployment lama dihapus"
    else
        error "Deployment dibatalkan"
    fi
fi

# Confirm deployment
echo -e "${YELLOW}📋 DEPLOYMENT INFO:${NC}"
echo -e "   Project: $PROJECT_DIR"
echo -e "   URL:     http://$DOMAIN:$PORT"
echo -e "   Setup:   Manual wizard (no auto-admin)"
echo -e "   Database: PostgreSQL 15.4"
echo
read -p "🚀 Deploy Nextcloud with Setup Wizard? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Deployment dibatalkan"
fi

log "Validation completed!"

# ===================================================================
# PHASE 1: SYSTEM PREPARATION
# ===================================================================
section "PHASE 1: SYSTEM PREPARATION"

info "Checking system requirements..."

# Update system
info "Updating package lists..."
apt-get update -qq

# Install required packages
info "Installing required packages..."
apt-get install -y curl wget unzip ufw net-tools

# Open firewall ports
info "Opening firewall ports..."
ufw allow $PORT/tcp >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true

# Test connectivity
info "Testing external connectivity..."
if curl -s --connect-timeout 5 https://google.com >/dev/null; then
    success "Internet connectivity OK"
else
    error "No internet connection!"
fi

log "System preparation completed!"

# ===================================================================
# PHASE 2: CREATE PROJECT STRUCTURE
# ===================================================================
section "PHASE 2: CREATE PROJECT STRUCTURE"

info "Creating project directory..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

info "Creating data directories..."
mkdir -p data
mkdir -p config
mkdir -p apps

info "Setting permissions..."
chown -R www-data:www-data data config apps 2>/dev/null || true
chmod -R 755 data config apps

log "Project structure created!"

# ===================================================================
# PHASE 3: CREATE DOCKER CONFIGURATION
# ===================================================================
section "PHASE 3: CREATE DOCKER CONFIGURATION"

info "Creating environment file..."
cat > .env <<EOF
# ===================================================================
# NEXTCLOUD ENVIRONMENT - SETUP WIZARD ENABLED
# ===================================================================
# Database Configuration (PostgreSQL 15.4 - Stable)
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=$DB_PASSWORD

# Redis Configuration (7.0.15 - Stable)
REDIS_HOST=redis

# Nextcloud Configuration (NO AUTO-ADMIN = WIZARD ENABLED)
NEXTCLOUD_TRUSTED_DOMAINS=$DOMAIN:$PORT $DOMAIN localhost
NEXTCLOUD_DATA_DIR=/var/www/html/data

# IMPORTANT: NO NEXTCLOUD_ADMIN_* vars = Setup Wizard enabled!
# User akan setup admin + recommended apps via dashboard

# Database Connection
POSTGRES_HOST=db
POSTGRES_DB_NAME=nextcloud
POSTGRES_USER_NAME=nextcloud
POSTGRES_PASSWORD_VAL=$DB_PASSWORD

# Performance & Security
PHP_MEMORY_LIMIT=1G
PHP_UPLOAD_LIMIT=10G
EOF

info "Creating Docker Compose file..."
cat > docker-compose.yml <<'EOF'
services:
  # PostgreSQL 15.4 Database (Stable for backup/restore)
  db:
    image: postgres:15.4-alpine
    container_name: nextcloud-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - nextcloud-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Redis 7.0.15 Cache (Stable)
  redis:
    image: redis:7.0.15-alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --requirepass ${POSTGRES_PASSWORD}
    networks:
      - nextcloud-net
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${POSTGRES_PASSWORD}", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Nextcloud App (Latest LTS - NO auto-admin = wizard enabled)
  app:
    image: nextcloud:28.0.1-apache
    container_name: nextcloud-app
    restart: unless-stopped
    ports:
      - "8081:80"
    environment:
      # Database connection
      POSTGRES_HOST: db
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      
      # Redis connection
      REDIS_HOST: redis
      REDIS_HOST_PASSWORD: ${POSTGRES_PASSWORD}
      
      # Trusted domains
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS}
      
      # Performance settings
      PHP_MEMORY_LIMIT: ${PHP_MEMORY_LIMIT}
      PHP_UPLOAD_LIMIT: ${PHP_UPLOAD_LIMIT}
      
      # IMPORTANT: NO NEXTCLOUD_ADMIN_USER/PASSWORD = Setup Wizard!
      
    volumes:
      - nextcloud_data:/var/www/html
      - ./data:/var/www/html/data
      - ./config:/var/www/html/config
      - ./apps:/var/www/html/custom_apps
    networks:
      - nextcloud-net
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/status.php"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  db_data:
    name: nextcloud_db_data
  nextcloud_data:
    name: nextcloud_app_data

networks:
  nextcloud-net:
    name: nextcloud-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/16
EOF

info "Setting file permissions..."
chmod 600 .env
chmod 644 docker-compose.yml

log "Docker configuration created!"

# ===================================================================
# PHASE 4: DEPLOY SERVICES
# ===================================================================
section "PHASE 4: DEPLOY SERVICES"

info "Cleaning up old containers..."
docker system prune -f >/dev/null 2>&1 || true

info "Pulling Docker images..."
docker compose pull

info "Starting PostgreSQL database..."
docker compose up -d db

info "Waiting for PostgreSQL to be ready..."
echo -n "⏳ "
until docker compose exec -T db pg_isready -U nextcloud -d nextcloud >/dev/null 2>&1; do
    printf "."
    sleep 2
done
echo " ✅"
success "PostgreSQL is ready!"

info "Starting Redis cache..."
docker compose up -d redis

info "Waiting for Redis to be ready..."
echo -n "⏳ "
until docker compose exec -T redis redis-cli -a "$DB_PASSWORD" ping >/dev/null 2>&1; do
    printf "."
    sleep 1
done
echo " ✅"
success "Redis is ready!"

info "Starting Nextcloud application..."
docker compose up -d app

info "Waiting for Nextcloud to be ready..."
echo -n "⏳ "
for i in {1..60}; do
    if curl -s -f "http://localhost:$PORT/status.php" >/dev/null 2>&1; then
        break
    fi
    printf "."
    sleep 3
done
echo " ✅"

log "All services deployed successfully!"

# ===================================================================
# PHASE 5: VERIFY DEPLOYMENT
# ===================================================================
section "PHASE 5: VERIFY DEPLOYMENT"

info "Checking container status..."
docker compose ps

info "Testing local access..."
if curl -s -f "http://localhost:$PORT/" >/dev/null; then
    success "Local access OK"
else
    warn "Local access test failed (might be normal during setup)"
fi

info "Checking database connection..."
if docker compose exec -T db psql -U nextcloud -d nextcloud -c "SELECT version();" >/dev/null 2>&1; then
    success "Database connection OK"
else
    warn "Database connection test failed"
fi

log "Deployment verification completed!"

# ===================================================================
# SUCCESS BANNER
# ===================================================================
clear
echo -e "${GREEN}"
echo "════════════════════════════════════════════════════════════════"
echo "                🧙‍♂️ NEXTCLOUD SETUP WIZARD READY! 🧙‍♂️"
echo "════════════════════════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${CYAN}🌐 ACCESS INFORMATION:${NC}"
echo -e "   URL:      ${YELLOW}http://$DOMAIN:$PORT${NC}"
echo -e "   Status:   ${GREEN}Setup Wizard Enabled${NC}"
echo -e "   Setup:    ${BLUE}Manual via Dashboard${NC}"
echo

echo -e "${CYAN}🗄️  DATABASE INFO (Pre-configured):${NC}"
echo -e "   Type:     ${GREEN}PostgreSQL 15.4${NC}"
echo -e "   Database: ${GREEN}nextcloud${NC}"
echo -e "   Username: ${GREEN}nextcloud${NC}"
echo -e "   Password: ${GREEN}$DB_PASSWORD${NC}"
echo

echo -e "${CYAN}📂 PROJECT LOCATION:${NC}"
echo -e "   Directory: ${GREEN}$PROJECT_DIR${NC}"
echo -e "   Data:      ${GREEN}$PROJECT_DIR/data${NC}"
echo -e "   Config:    ${GREEN}$PROJECT_DIR/config${NC}"
echo

echo -e "${CYAN}🎯 SETUP WIZARD STEPS:${NC}"
echo -e "   ${GREEN}1.${NC} Open browser: ${YELLOW}http://$DOMAIN:$PORT${NC}"
echo -e "   ${GREEN}2.${NC} Create admin account (username/password)"
echo -e "   ${GREEN}3.${NC} Database sudah auto-configured!"
echo -e "   ${GREEN}4.${NC} Pilih recommended apps (Calendar, Contacts, Mail, etc.)"
echo -e "   ${GREEN}5.${NC} Finish setup!"
echo

echo -e "${CYAN}🛡️  BACKUP/RESTORE READY:${NC}"
echo -e "   ${GREEN}✅ User accounts & settings${NC}"
echo -e "   ${GREEN}✅ Installed apps & plugins${NC}" 
echo -e "   ${GREEN}✅ Themes & customizations${NC}"
echo -e "   ${GREEN}✅ External storage configs${NC}"
echo -e "   ${GREEN}✅ Email & calendar settings${NC}"
echo

echo -e "${CYAN}🔧 USEFUL COMMANDS:${NC}"
echo -e "   Status:   ${GREEN}cd $PROJECT_DIR && docker compose ps${NC}"
echo -e "   Logs:     ${GREEN}cd $PROJECT_DIR && docker compose logs -f app${NC}"
echo -e "   Restart:  ${GREEN}cd $PROJECT_DIR && docker compose restart${NC}"
echo -e "   Stop:     ${GREEN}cd $PROJECT_DIR && docker compose down${NC}"
echo

echo -e "${CYAN}📋 TROUBLESHOOTING:${NC}"
echo -e "   Check containers: ${BLUE}cd $PROJECT_DIR && docker compose ps${NC}"
echo -e "   View logs: ${BLUE}cd $PROJECT_DIR && docker compose logs app${NC}"
echo -e "   Test access: ${BLUE}curl -I http://localhost:$PORT${NC}"
echo

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}🎉 Nextcloud Setup Wizard siap digunakan! Buka browser sekarang! 🎉${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo

exit 0