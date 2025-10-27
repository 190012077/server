# Nextcloud Docker + MySQL + Google Drive Integration 🚀

## Overview
Tutorial ini akan membuat:
- Nextcloud dengan Docker versi stabil
- MySQL 8.0 sebagai database
- Google Drive sebagai primary storage via rclone
- Upload otomatis langsung ke Google Drive

---

## 1. Persiapan VPS & Dependencies

### Install Docker & Docker Compose
```bash
# Update sistem
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose v2
sudo apt install -y docker-compose-plugin

# Logout dan login kembali atau:
newgrp docker

# Verify installation
docker --version
docker compose version
```

### Install rclone
```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Verify installation
rclone version
```

---

## 2. Setup Google Drive dengan rclone

### Konfigurasi rclone untuk Google Drive
```bash
# Jalankan konfigurasi rclone
rclone config

# Pilih: n (new remote)
# Name: gdrive
# Storage: 18 (Google Drive)
# Client ID: (kosongkan, tekan enter)
# Client Secret: (kosongkan, tekan enter)
# Scope: 1 (full access)
# Root folder ID: (kosongkan)
# Service account file: (kosongkan)
# Advanced config: n
# Auto config: y (akan buka browser untuk auth)

# Test koneksi
rclone lsd gdrive:

# Buat folder untuk Nextcloud
rclone mkdir gdrive:nextcloud-data
```

### Buat mount point dan script
```bash
# Buat direktori mount
sudo mkdir -p /mnt/gdrive
sudo chown $USER:$USER /mnt/gdrive

# Buat script mount
nano ~/mount-gdrive.sh
```

```bash
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
```

```bash
chmod +x ~/mount-gdrive.sh

# Test mount
~/mount-gdrive.sh

# Verify mount
df -h | grep gdrive
ls -la /mnt/gdrive/
```

---

## 3. Docker Compose Configuration

### Buat direktori project
```bash
mkdir -p ~/nextcloud-production
cd ~/nextcloud-production

# Buat direktori untuk volume
mkdir -p ./volumes/nextcloud
mkdir -p ./volumes/mysql
mkdir -p ./volumes/redis
```

### Docker Compose dengan versi stabil
```bash
nano docker-compose.yml
```

```yaml
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
      - ./config/apache-custom.conf:/etc/apache2/conf-available/custom.conf:ro
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

volumes:
  mysql_data:
  redis_data:
  nextcloud_data:
```

### Environment file
```bash
nano .env
```

```env
# MySQL Configuration
MYSQL_ROOT_PASSWORD=your_very_secure_root_password_here
MYSQL_PASSWORD=your_secure_nextcloud_password_here

# Nextcloud Admin
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=your_admin_password_here

# Domain Configuration
NEXTCLOUD_TRUSTED_DOMAINS=your-domain.com

# Timezone
TZ=Asia/Jakarta
```

---

## 4. Konfigurasi Files

### MySQL Optimization
```bash
mkdir -p mysql
nano mysql/init.sql
```

```sql
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
```

### PHP Configuration
```bash
mkdir -p config
nano config/custom.ini
```

```ini
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
```

### Apache Configuration
```bash
nano config/apache-custom.conf
```

```apache
# Apache custom configuration for Nextcloud
<IfModule mod_headers.c>
    # Security Headers
    Header set X-Content-Type-Options nosniff
    Header set X-XSS-Protection "1; mode=block"
    Header set X-Robots-Tag none
    Header set X-Download-Options noopen
    Header set X-Permitted-Cross-Domain-Policies none
    Header set Referrer-Policy no-referrer
    Header set Strict-Transport-Security "max-age=15552000; includeSubDomains"
</IfModule>

# Increase upload limits
LimitRequestBody 0

# Enable compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
</IfModule>
```

### Nginx Configuration
```bash
mkdir -p nginx
nano nginx/nginx.conf
```

```nginx
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
```

```bash
nano nginx/nextcloud.conf
```

```nginx
upstream nextcloud-app {
    server nextcloud:80;
}

server {
    listen 80;
    server_name your-domain.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL Configuration (gunakan Let's Encrypt atau self-signed)
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
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
```

---

## 5. SSL Certificate Setup

### Self-Signed Certificate (untuk testing)
```bash
mkdir -p ssl
cd ssl

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout key.pem \
    -out cert.pem \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Nextcloud/CN=your-domain.com"

cd ..
```

### Let's Encrypt (untuk production)
```bash
# Install certbot
sudo apt install -y certbot

# Stop nginx container temporarily
docker compose stop nginx

# Generate certificate
sudo certbot certonly --standalone -d your-domain.com

# Copy certificates
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ssl/cert.pem
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem ssl/key.pem
sudo chown $USER:$USER ssl/*.pem
```

---

## 6. Deploy & Configure

### Start containers
```bash
# Start semua services
docker compose up -d

# Check status
docker compose ps

# Check logs
docker compose logs -f nextcloud
```

### Configure Nextcloud untuk Google Drive
```bash
# Tunggu sampai Nextcloud fully started (check via browser)
# Lalu execute commands berikut:

# Masuk ke container Nextcloud
docker compose exec nextcloud bash

# Install required apps
php occ app:enable files_external

# Configure external storage
php occ files_external:create gdrive_storage local null::null
php occ files_external:config 1 datadir /var/www/html/data/gdrive
php occ files_external:option 1 encrypt true
php occ files_external:option 1 previews true
php occ files_external:option 1 enable_sharing true

# Set as primary storage
php occ config:system:set primary_storage_config --value='{"class":"\\OC\\Files\\Storage\\Local","arguments":{"datadir":"\/var\/www\/html\/data\/gdrive"}}'

# Configure caching
php occ config:system:set memcache.local --value='\OC\Memcache\APCu'
php occ config:system:set memcache.distributed --value='\OC\Memcache\Redis'
php occ config:system:set redis host --value='redis'
php occ config:system:set redis port --value=6379

# Set trusted domains
php occ config:system:set trusted_domains 0 --value=your-domain.com

# Enable HTTPS
php occ config:system:set overwriteprotocol --value=https

# Optimize for large files
php occ config:system:set chunk_size --value=10485760

exit
```

### Advanced Nextcloud Configuration
```bash
# Create custom config file
docker compose exec nextcloud bash

# Edit config.php untuk optimisasi Google Drive
nano /var/www/html/config/config.php
```

Tambahkan konfigurasi berikut ke `config.php`:

```php
<?php
// ... existing config ...

// Google Drive optimizations
'filesystem_check_changes' => 1,
'files_external_allow_create_new_local' => true,
'enable_previews' => true,
'preview_max_x' => 2048,
'preview_max_y' => 2048,
'preview_max_scale_factor' => 10,

// Upload optimizations
'max_chunk_size' => 10485760, // 10MB chunks
'upload_chunk_size' => 10485760,

// Memory and performance
'memory_limit' => '2G',
'mysql.utf8mb4' => true,

// Background jobs
'backgroundjobs_mode' => 'cron',

// Logging
'log_type' => 'file',
'loglevel' => 2,
'log_rotate_size' => 104857600, // 100MB

// Google Drive specific
'objectstore' => [
    'class' => 'OC\\Files\\ObjectStore\\S3',
    'arguments' => [
        'bucket' => 'nextcloud-data',
        'autocreate' => true,
        'key' => '',
        'secret' => '',
        'hostname' => 'localhost',
        'port' => 9000,
        'use_ssl' => false,
        'region' => 'us-east-1',
        'use_path_style' => true
    ],
],

// External storage
'files_external_allow_create_new_local' => true,
'allow_local_remote_servers' => true,
?>
```

---

## 7. Automation Scripts

### Auto-mount script untuk startup
```bash
nano ~/auto-mount-gdrive.sh
```

```bash
#!/bin/bash
# auto-mount-gdrive.sh - Auto mount Google Drive on system startup

LOG_FILE="/var/log/gdrive-mount.log"
MOUNT_POINT="/mnt/gdrive"
RCLONE_CONFIG="gdrive:nextcloud-data"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    log_message "Google Drive already mounted at $MOUNT_POINT"
    exit 0
fi

# Wait for network
log_message "Waiting for network connectivity..."
until ping -c1 google.com &>/dev/null; do
    sleep 5
done

# Mount Google Drive
log_message "Mounting Google Drive..."
rclone mount "$RCLONE_CONFIG" "$MOUNT_POINT" \
    --allow-other \
    --allow-non-empty \
    --vfs-cache-mode writes \
    --vfs-cache-max-size 2G \
    --vfs-cache-max-age 2h \
    --buffer-size 128M \
    --dir-cache-time 24h \
    --poll-interval 30s \
    --umask 002 \
    --uid $(id -u) \
    --gid $(id -g) \
    --daemon \
    --log-file "$LOG_FILE" \
    --log-level INFO

if mountpoint -q "$MOUNT_POINT"; then
    log_message "Google Drive mounted successfully at $MOUNT_POINT"
    
    # Start Docker Compose
    cd /home/$USER/nextcloud-production
    log_message "Starting Nextcloud containers..."
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        log_message "Nextcloud containers started successfully"
    else
        log_message "ERROR: Failed to start Nextcloud containers"
    fi
else
    log_message "ERROR: Failed to mount Google Drive"
    exit 1
fi
```

```bash
chmod +x ~/auto-mount-gdrive.sh

# Add to systemd for auto-start
sudo nano /etc/systemd/system/nextcloud-gdrive.service
```

```ini
[Unit]
Description=Nextcloud with Google Drive Storage
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=your-username
ExecStart=/home/your-username/auto-mount-gdrive.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
# Enable service
sudo systemctl daemon-reload
sudo systemctl enable nextcloud-gdrive.service
```

### Backup script
```bash
nano ~/backup-nextcloud.sh
```

```bash
#!/bin/bash
# Backup Nextcloud config and database

BACKUP_DIR="/backup/nextcloud"
DATE=$(date +%Y%m%d_%H%M%S)
PROJECT_DIR="/home/$USER/nextcloud-production"

mkdir -p "$BACKUP_DIR"

echo "Starting backup at $(date)"

# Backup database
echo "Backing up database..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T mysql \
    mysqldump -u nextcloud -p$MYSQL_PASSWORD nextcloud > "$BACKUP_DIR/nextcloud_db_$DATE.sql"

# Backup Nextcloud config
echo "Backing up Nextcloud config..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T nextcloud \
    tar -czf - -C /var/www/html config/ > "$BACKUP_DIR/nextcloud_config_$DATE.tar.gz"

# Backup Docker Compose files
echo "Backing up Docker Compose configuration..."
tar -czf "$BACKUP_DIR/docker_config_$DATE.tar.gz" -C "$PROJECT_DIR" .

echo "Backup completed at $(date)"
echo "Files backed up to: $BACKUP_DIR"

# Cleanup old backups (keep 7 days)
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
```

```bash
chmod +x ~/backup-nextcloud.sh

# Schedule daily backup
crontab -e
# Add: 0 2 * * * /home/your-username/backup-nextcloud.sh
```

---

## 8. Monitoring & Maintenance

### Health check script
```bash
nano ~/health-check.sh
```

```bash
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
docker compose -f /home/$USER/nextcloud-production/docker-compose.yml ps

# Check Nextcloud status
echo -e "\n=== Nextcloud Application Status ==="
docker compose -f /home/$USER/nextcloud-production/docker-compose.yml exec -T nextcloud \
    php occ status

# Check database connection
echo -e "\n=== Database Status ==="
docker compose -f /home/$USER/nextcloud-production/docker-compose.yml exec -T mysql \
    mysqladmin ping -u nextcloud -p$MYSQL_PASSWORD

# Check disk usage
echo -e "\n=== Disk Usage ==="
df -h

# Check memory usage
echo -e "\n=== Memory Usage ==="
free -h

echo -e "\n=== Health Check Completed ==="
```

```bash
chmod +x ~/health-check.sh

# Schedule hourly health check
crontab -e
# Add: 0 * * * * /home/your-username/health-check.sh >> /var/log/nextcloud-health.log 2>&1
```

---

## 9. Troubleshooting

### Common Issues & Solutions

#### Google Drive Mount Issues
```bash
# Check rclone config
rclone config show

# Test connection
rclone lsd gdrive:

# Remount manually
fusermount -u /mnt/gdrive
~/mount-gdrive.sh

# Check mount logs
tail -f /var/log/gdrive-mount.log
```

#### Container Issues
```bash
# Check container logs
docker compose logs nextcloud
docker compose logs mysql
docker compose logs redis

# Restart services
docker compose restart nextcloud
docker compose restart mysql

# Check resource usage
docker stats
```

#### Database Issues
```bash
# Access MySQL
docker compose exec mysql mysql -u nextcloud -p

# Check database size
docker compose exec mysql mysql -u nextcloud -p -e "
SELECT 
    table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.tables 
WHERE table_schema = 'nextcloud'
GROUP BY table_schema;"

# Optimize database
docker compose exec nextcloud php occ db:add-missing-indices
docker compose exec nextcloud php occ db:convert-filecache-bigint
```

#### Performance Issues
```bash
# Clear Nextcloud cache
docker compose exec nextcloud php occ files:scan --all
docker compose exec nextcloud php occ files:cleanup

# Check PHP OPcache
docker compose exec nextcloud php -i | grep opcache

# Monitor resource usage
htop
iotop
```

---

## 10. Security Hardening

### Firewall Configuration
```bash
# Install UFW
sudo apt install -y ufw

# Basic rules
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443

# Enable firewall
sudo ufw enable
sudo ufw status
```

### Fail2Ban Setup
```bash
# Install Fail2Ban
sudo apt install -y fail2ban

# Configure Nextcloud jail
sudo nano /etc/fail2ban/jail.d/nextcloud.conf
```

```ini
[nextcloud]
enabled = true
port = 80,443
protocol = tcp
filter = nextcloud
logpath = /home/your-username/nextcloud-production/volumes/nextcloud/data/nextcloud.log
maxretry = 3
bantime = 3600
findtime = 600
```

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status nextcloud
```

---

## 11. Performance Optimization

### System Optimization
```bash
# Optimize system for Nextcloud
sudo nano /etc/sysctl.conf

# Add these lines:
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Apply changes
sudo sysctl -p
```

### Docker Optimization
```bash
# Configure Docker daemon
sudo nano /etc/docker/daemon.json
```

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
```

```bash
sudo systemctl restart docker
```

---

## Summary & Best Practices

### ✅ **Yang Sudah Dicapai:**
1. **Nextcloud 28.0.1 LTS** (versi stabil)
2. **MySQL 8.0.35** (database stabil)
3. **Google Drive sebagai primary storage**
4. **Automatic upload ke Google Drive**
5. **SSL/HTTPS support**
6. **Auto-mount pada startup**
7. **Monitoring & backup automation**

### 🚀 **Rekomendasi:**
1. **Ganti domain** `your-domain.com` dengan domain aktual Anda
2. **Update password** di file `.env` dengan password yang kuat
3. **Setup Let's Encrypt** untuk SSL certificate production
4. **Monitor log files** secara berkala
5. **Test backup & restore** secara berkala

### 📝 **Next Steps:**
1. Setup domain dan DNS
2. Configure Let's Encrypt
3. Install Nextcloud apps sesuai kebutuhan
4. Setup user management
5. Configure email notifications

Dengan setup ini, semua file yang diupload ke Nextcloud akan langsung tersimpan di Google Drive, dan VPS Anda hanya berfungsi sebagai interface/proxy ke Google Drive storage! 🎉