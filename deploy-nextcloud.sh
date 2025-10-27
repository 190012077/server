#!/bin/bash
# Automated Nextcloud Docker + MySQL + Google Drive Deployment Script
# Author: Assistant
# Description: Deploy Nextcloud with stable Docker versions, MySQL, and Google Drive integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 is not installed. Please install it first."
    fi
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to validate domain
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $domain"
    fi
}

# Main deployment function
main() {
    log "Starting Nextcloud Docker + MySQL + Google Drive deployment..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as regular user with sudo privileges."
    fi
    
    # Get user input
    read -p "Enter your domain name (e.g., nextcloud.example.com): " DOMAIN
    validate_domain "$DOMAIN"
    
    read -p "Enter admin username [admin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    read -s -p "Enter admin password (leave empty for auto-generated): " ADMIN_PASSWORD
    echo
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        ADMIN_PASSWORD=$(generate_password)
        info "Generated admin password: $ADMIN_PASSWORD"
    fi
    
    read -p "Enter your email for SSL certificate: " EMAIL
    
    # Generate passwords
    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_PASSWORD=$(generate_password)
    
    log "Configuration:"
    info "Domain: $DOMAIN"
    info "Admin User: $ADMIN_USER"
    info "Admin Password: $ADMIN_PASSWORD"
    info "Email: $EMAIL"
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Step 1: Update system and install dependencies
    log "Step 1: Installing dependencies..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget nano git htop ufw fail2ban
    
    # Step 2: Install Docker
    log "Step 2: Installing Docker..."
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
    else
        info "Docker already installed"
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        sudo apt install -y docker-compose-plugin
    else
        info "Docker Compose already installed"
    fi
    
    # Step 3: Install rclone
    log "Step 3: Installing rclone..."
    if ! command -v rclone &> /dev/null; then
        curl https://rclone.org/install.sh | sudo bash
    else
        info "rclone already installed"
    fi
    
    # Step 4: Configure Google Drive
    log "Step 4: Configuring Google Drive..."
    warn "You need to configure rclone for Google Drive manually."
    warn "After this script completes, run: rclone config"
    warn "Then create a remote named 'gdrive' for Google Drive"
    
    # Create mount point
    sudo mkdir -p /mnt/gdrive
    sudo chown $USER:$USER /mnt/gdrive
    
    # Step 5: Create project directory
    log "Step 5: Creating project structure..."
    PROJECT_DIR="$HOME/nextcloud-production"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Create directories
    mkdir -p volumes/{nextcloud,mysql,redis}
    mkdir -p {config,nginx,ssl,mysql}
    
    # Step 6: Create configuration files
    log "Step 6: Creating configuration files..."
    
    # Create .env file
    cat > .env << EOF
# MySQL Configuration
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD

# Nextcloud Admin
NEXTCLOUD_ADMIN_USER=$ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_PASSWORD

# Domain Configuration
NEXTCLOUD_TRUSTED_DOMAINS=$DOMAIN

# Timezone
TZ=Asia/Jakarta
EOF
    
    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # MySQL 8.0 - Versi Stabil
  mysql:
    image: mysql:8.0.35
    container_name: nextcloud-mysql
    restart: unless-stopped
    command: --default-authentication-plugin=mysql_native_password
    volumes:
      - ./volumes/mysql:/var/lib/mysql
      - ./mysql/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    ports:
      - "3306:3306"
    networks:
      - nextcloud-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Redis untuk caching
  redis:
    image: redis:7.0.15-alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    volumes:
      - ./volumes/redis:/data
    networks:
      - nextcloud-network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Nextcloud - Versi Stabil LTS
  nextcloud:
    image: nextcloud:28.0.1-apache
    container_name: nextcloud-app
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./volumes/nextcloud:/var/www/html
      - /mnt/gdrive:/var/www/html/data/gdrive:rshared
      - ./config/custom.ini:/usr/local/etc/php/conf.d/custom.ini:ro
    environment:
      MYSQL_HOST: mysql
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS}
      OVERWRITEPROTOCOL: https
      OVERWRITECLIURL: https://${NEXTCLOUD_TRUSTED_DOMAINS}
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - nextcloud-network

  # Nginx Reverse Proxy
  nginx:
    image: nginx:1.24.0-alpine
    container_name: nextcloud-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/nextcloud.conf:/etc/nginx/conf.d/default.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./volumes/nextcloud:/var/www/html:ro
    depends_on:
      - nextcloud
    networks:
      - nextcloud-network

networks:
  nextcloud-network:
    driver: bridge
EOF
    
    # Create MySQL init script
    cat > mysql/init.sql << 'EOF'
-- MySQL optimization for Nextcloud
SET GLOBAL innodb_buffer_pool_size = 128M;
SET GLOBAL innodb_buffer_pool_instances = 1;
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
SET GLOBAL innodb_log_buffer_size = 32M;
SET GLOBAL innodb_max_dirty_pages_pct = 90;
SET GLOBAL query_cache_type = 1;
SET GLOBAL query_cache_limit = 2M;
SET GLOBAL query_cache_size = 64M;

-- Create optimized database
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
    
    # Create PHP config
    cat > config/custom.ini << 'EOF'
; PHP Configuration for Nextcloud with Google Drive
memory_limit = 2G
upload_max_filesize = 10G
post_max_size = 10G
max_input_time = 3600
max_execution_time = 3600
max_input_vars = 3000

; OPcache Configuration
opcache.enable = 1
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.memory_consumption = 256
opcache.save_comments = 1
opcache.revalidate_freq = 1

; File handling
file_uploads = On
allow_url_fopen = On

; Session
session.cookie_httponly = 1
session.cookie_secure = 1
EOF
    
    # Create Nginx config
    cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 10G;
    client_body_buffer_size 400M;
    client_body_timeout 120s;

    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    # Create Nginx site config
    cat > nginx/nextcloud.conf << EOF
upstream nextcloud-app {
    server nextcloud:80;
}

server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy no-referrer always;

    # Upload limits
    client_max_body_size 10G;
    client_body_buffer_size 400M;
    client_body_timeout 120s;

    location / {
        proxy_pass http://nextcloud-app;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Upload timeout
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 8 8k;
        proxy_busy_buffers_size 16k;
    }
}
EOF
    
    # Step 7: Generate SSL certificate
    log "Step 7: Generating SSL certificate..."
    
    # Install certbot
    sudo apt install -y certbot
    
    # Generate self-signed certificate first (for initial setup)
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout ssl/key.pem \
        -out ssl/cert.pem \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Nextcloud/CN=$DOMAIN"
    
    # Step 8: Create utility scripts
    log "Step 8: Creating utility scripts..."
    
    # Mount script
    cat > mount-gdrive.sh << 'EOF'
#!/bin/bash
# mount-gdrive.sh

MOUNT_POINT="/mnt/gdrive"
RCLONE_CONFIG="gdrive:nextcloud-data"

# Unmount jika sudah mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo "Unmounting existing mount..."
    fusermount -u "$MOUNT_POINT"
fi

# Mount Google Drive
echo "Mounting Google Drive..."
rclone mount "$RCLONE_CONFIG" "$MOUNT_POINT" \
    --allow-other \
    --allow-non-empty \
    --vfs-cache-mode writes \
    --vfs-cache-max-size 1G \
    --vfs-cache-max-age 1h \
    --buffer-size 64M \
    --dir-cache-time 12h \
    --poll-interval 15s \
    --umask 002 \
    --uid $(id -u) \
    --gid $(id -g) \
    --daemon

echo "Google Drive mounted at $MOUNT_POINT"
EOF
    chmod +x mount-gdrive.sh
    
    # Health check script
    cat > health-check.sh << 'EOF'
#!/bin/bash
# Health check for Nextcloud with Google Drive

echo "=== Nextcloud Health Check - $(date) ==="

# Check if Google Drive is mounted
if mountpoint -q /mnt/gdrive; then
    echo "✅ Google Drive mounted successfully"
    echo "   Space available: $(df -h /mnt/gdrive | tail -1 | awk '{print $4}')"
else
    echo "❌ Google Drive NOT mounted"
fi

# Check Docker containers
echo -e "\n=== Docker Container Status ==="
docker compose ps

# Check Nextcloud status
echo -e "\n=== Nextcloud Application Status ==="
docker compose exec -T nextcloud php occ status 2>/dev/null || echo "Nextcloud not ready yet"

echo -e "\n=== Health Check Completed ==="
EOF
    chmod +x health-check.sh
    
    # Step 9: Configure firewall
    log "Step 9: Configuring firewall..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw --force enable
    
    # Step 10: Start services
    log "Step 10: Starting Docker services..."
    
    # Add user to docker group and refresh
    sudo usermod -aG docker $USER
    
    # Start containers
    docker compose pull
    docker compose up -d
    
    # Wait for services to start
    log "Waiting for services to start..."
    sleep 30
    
    # Check status
    docker compose ps
    
    # Step 11: Create post-deployment instructions
    cat > POST_DEPLOYMENT.md << EOF
# Post-Deployment Instructions

## 1. Configure Google Drive
Run the following command to configure rclone:
\`\`\`bash
rclone config
\`\`\`

Create a new remote with these settings:
- Name: gdrive
- Storage: Google Drive
- Follow the authentication process

Then create the nextcloud folder:
\`\`\`bash
rclone mkdir gdrive:nextcloud-data
\`\`\`

## 2. Mount Google Drive
\`\`\`bash
./mount-gdrive.sh
\`\`\`

## 3. Configure Let's Encrypt (Production SSL)
\`\`\`bash
# Stop nginx container
docker compose stop nginx

# Get certificate
sudo certbot certonly --standalone -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# Copy certificates
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem ssl/cert.pem
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem ssl/key.pem
sudo chown \$USER:\$USER ssl/*.pem

# Restart nginx
docker compose start nginx
\`\`\`

## 4. Access Nextcloud
- URL: https://$DOMAIN
- Admin User: $ADMIN_USER
- Admin Password: $ADMIN_PASSWORD

## 5. Configure Nextcloud for Google Drive
After accessing Nextcloud, run:
\`\`\`bash
docker compose exec nextcloud bash

# Enable external storage
php occ app:enable files_external

# Configure external storage
php occ files_external:create gdrive_storage local null::null
php occ files_external:config 1 datadir /var/www/html/data/gdrive

# Configure caching
php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu'
php occ config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis'
php occ config:system:set redis host --value='redis'

exit
\`\`\`

## 6. Monitor Health
\`\`\`bash
./health-check.sh
\`\`\`

## Passwords (SAVE THESE SECURELY!)
- Admin Password: $ADMIN_PASSWORD
- MySQL Root Password: $MYSQL_ROOT_PASSWORD
- MySQL Nextcloud Password: $MYSQL_PASSWORD

## Useful Commands
- View logs: \`docker compose logs -f nextcloud\`
- Restart services: \`docker compose restart\`
- Stop services: \`docker compose down\`
- Update: \`docker compose pull && docker compose up -d\`
EOF
    
    # Final message
    log "Deployment completed successfully! 🎉"
    echo
    info "Next steps:"
    info "1. Configure Google Drive with: rclone config"
    info "2. Mount Google Drive with: ./mount-gdrive.sh"
    info "3. Access Nextcloud at: http://localhost:8080 (or your domain)"
    info "4. Read POST_DEPLOYMENT.md for complete setup instructions"
    echo
    warn "IMPORTANT: Save your passwords securely!"
    info "Admin Password: $ADMIN_PASSWORD"
    info "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo
    info "Current status:"
    docker compose ps
}

# Run main function
main "$@"