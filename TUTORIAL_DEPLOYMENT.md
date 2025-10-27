# Tutorial Deployment Nextcloud Server 🚀

## Daftar Isi
1. [Persiapan Sistem](#persiapan-sistem)
2. [Method 1: Manual Installation](#method-1-manual-installation)
3. [Method 2: Docker Deployment](#method-2-docker-deployment)
4. [Method 3: Snap Package](#method-3-snap-package)
5. [Konfigurasi SSL](#konfigurasi-ssl)
6. [Optimisasi Performance](#optimisasi-performance)
7. [Backup & Maintenance](#backup--maintenance)
8. [Troubleshooting](#troubleshooting)

---

## Persiapan Sistem

### Requirement Minimum
- **OS**: Ubuntu 20.04+, Debian 11+, CentOS 8+, atau distribusi Linux lainnya
- **PHP**: 8.1 atau lebih baru
- **Database**: MySQL 8.0+, PostgreSQL 12+, atau SQLite 3.8+
- **Web Server**: Apache 2.4+ atau Nginx 1.18+
- **Memory**: Minimum 512MB RAM (direkomendasikan 2GB+)
- **Storage**: Minimum 1GB (tergantung kebutuhan data)

### PHP Extensions yang Dibutuhkan
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y php8.1 php8.1-fpm php8.1-mysql php8.1-xml php8.1-zip \
    php8.1-curl php8.1-gd php8.1-mbstring php8.1-intl php8.1-bcmath \
    php8.1-gmp php8.1-imagick php8.1-redis php8.1-apcu

# CentOS/RHEL
sudo dnf install -y php php-fpm php-mysql php-xml php-zip php-curl \
    php-gd php-mbstring php-intl php-bcmath php-gmp php-pecl-imagick \
    php-pecl-redis php-pecl-apcu
```

---

## Method 1: Manual Installation

### 1. Download Nextcloud
```bash
# Buat direktori untuk Nextcloud
sudo mkdir -p /var/www/nextcloud
cd /tmp

# Download versi terbaru
wget https://download.nextcloud.com/server/releases/latest.tar.bz2
wget https://download.nextcloud.com/server/releases/latest.tar.bz2.sha256

# Verifikasi checksum
sha256sum -c latest.tar.bz2.sha256 < latest.tar.bz2

# Extract
tar -xjf latest.tar.bz2

# Pindahkan ke direktori web
sudo mv nextcloud/* /var/www/nextcloud/
sudo chown -R www-data:www-data /var/www/nextcloud/
sudo chmod -R 755 /var/www/nextcloud/
```

### 2. Setup Database

#### MySQL/MariaDB
```bash
# Install MySQL/MariaDB
sudo apt install -y mysql-server

# Secure installation
sudo mysql_secure_installation

# Buat database dan user
sudo mysql -u root -p
```

```sql
CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY 'password_yang_kuat';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

#### PostgreSQL (Alternatif)
```bash
# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Buat database dan user
sudo -u postgres psql
```

```sql
CREATE DATABASE nextcloud;
CREATE USER nextcloud WITH PASSWORD 'password_yang_kuat';
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
\q
```

### 3. Konfigurasi Web Server

#### Apache
```bash
# Install Apache
sudo apt install -y apache2

# Enable modules
sudo a2enmod rewrite headers env dir mime ssl

# Buat virtual host
sudo nano /etc/apache2/sites-available/nextcloud.conf
```

```apache
<VirtualHost *:80>
    ServerAdmin admin@yourdomain.com
    DocumentRoot /var/www/nextcloud
    ServerName your-domain.com
    ServerAlias www.your-domain.com

    <Directory /var/www/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog ${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
```

```bash
# Enable site
sudo a2ensite nextcloud.conf
sudo a2dissite 000-default.conf
sudo systemctl reload apache2
```

#### Nginx (Alternatif)
```bash
# Install Nginx
sudo apt install -y nginx

# Buat konfigurasi
sudo nano /etc/nginx/sites-available/nextcloud
```

```nginx
upstream php-handler {
    server unix:/var/run/php/php8.1-fpm.sock;
}

server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com;

    # Enforce HTTPS (gunakan setelah SSL setup)
    # return 301 https://$server_name$request_uri;

    # Path to the root of your installation
    root /var/www/nextcloud;

    # set max upload size
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    # Enable gzip but do not remove ETag headers
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    # Pagespeed is not supported by Nextcloud, so if your server is built
    # with the `ngx_pagespeed` module, uncomment this line to disable it.
    #pagespeed off;

    # HTTP response headers borrowed from Nextcloud `.htaccess`
    add_header Referrer-Policy                      "no-referrer"   always;
    add_header X-Content-Type-Options               "nosniff"       always;
    add_header X-Download-Options                   "noopen"        always;
    add_header X-Frame-Options                      "SAMEORIGIN"    always;
    add_header X-Permitted-Cross-Domain-Policies    "none"          always;
    add_header X-Robots-Tag                         "none"          always;
    add_header X-XSS-Protection                     "1; mode=block" always;

    # Remove X-Powered-By, which is an information leak
    fastcgi_hide_header X-Powered-By;

    # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
    location = / {
        if ( $http_user_agent ~ ^DavClnt ) {
            return 302 /remote.php/webdav/$is_args$args;
        }
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # Make a regex exception for `/.well-known` so that clients can still
    # access it despite the existence of the regex rule
    # `location ~ /(\.|autotest|...)` which would otherwise handle requests
    # for `/.well-known`.
    location ^~ /.well-known {
        # The rules in this block are an adaptation of the rules
        # in `.htaccess` that concern `/.well-known`.

        location = /.well-known/carddav { return 301 /remote.php/dav/; }
        location = /.well-known/caldav  { return 301 /remote.php/dav/; }

        location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
        location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

        # Let Nextcloud's API for `/.well-known` URIs handle all other
        # requests by passing them to the front-end controller.
        return 301 /index.php$request_uri;
    }

    # Rules borrowed from `.htaccess` to hide certain paths from clients
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

    # Ensure this block, which passes PHP files to the PHP process, is above the blocks
    # which handle static assets (as a `location` block's specificity is determined by the
    # order in which they appear in the configuration file).
    location ~ \.php(?:$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        set $path_info $fastcgi_path_info;

        try_files $fastcgi_script_name =404;

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_param HTTPS on;

        fastcgi_param modHeadersAvailable true;         # Avoid sending the security headers twice
        fastcgi_param front_controller_active true;     # Enable pretty urls
        fastcgi_pass php-handler;

        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~ \.(?:css|js|svg|gif)$ {
        try_files $uri /index.php$request_uri;
        expires 6M;         # Cache-Control policy borrowed from `.htaccess`
        access_log off;     # Optional: Don't log access to assets
    }

    location ~ \.woff2?$ {
        try_files $uri /index.php$request_uri;
        expires 7d;         # Cache-Control policy borrowed from `.htaccess`
        access_log off;     # Optional: Don't log access to assets
    }

    # Rule borrowed from `.htaccess`
    location /remote {
        return 301 /remote.php$request_uri;
    }

    location / {
        try_files $uri $uri/ /index.php$request_uri;
    }
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 4. Konfigurasi PHP
```bash
sudo nano /etc/php/8.1/fpm/php.ini
```

Ubah nilai berikut:
```ini
memory_limit = 512M
upload_max_filesize = 16G
post_max_size = 16G
max_input_time = 3600
max_execution_time = 3600
```

```bash
# Restart PHP-FPM
sudo systemctl restart php8.1-fpm
```

### 5. Instalasi Web-based
1. Akses domain Anda di browser
2. Buat akun admin
3. Konfigurasi database:
   - Database user: `nextcloud`
   - Database password: `password_yang_kuat`
   - Database name: `nextcloud`
   - Database host: `localhost`

---

## Method 2: Docker Deployment

### 1. Install Docker & Docker Compose
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install -y docker-compose
```

### 2. Buat Docker Compose File
```bash
mkdir ~/nextcloud-docker
cd ~/nextcloud-docker
nano docker-compose.yml
```

```yaml
version: '3.8'

services:
  db:
    image: mariadb:10.6
    restart: always
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=secure_root_password
      - MYSQL_PASSWORD=secure_password
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    networks:
      - nextcloud

  redis:
    image: redis:alpine
    restart: always
    networks:
      - nextcloud

  app:
    image: nextcloud:latest
    restart: always
    ports:
      - 8080:80
    links:
      - db
      - redis
    volumes:
      - nextcloud:/var/www/html
      - ./data:/var/www/html/data
    environment:
      - MYSQL_PASSWORD=secure_password
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=db
      - REDIS_HOST=redis
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=admin_password
      - NEXTCLOUD_TRUSTED_DOMAINS=your-domain.com
    depends_on:
      - db
      - redis
    networks:
      - nextcloud

volumes:
  nextcloud:
  db:

networks:
  nextcloud:
```

### 3. Deploy
```bash
# Start containers
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f app
```

---

## Method 3: Snap Package

### 1. Install Snap (jika belum ada)
```bash
sudo apt update
sudo apt install -y snapd
```

### 2. Install Nextcloud
```bash
# Install Nextcloud
sudo snap install nextcloud

# Buat admin user
sudo nextcloud.manual-install admin password_admin

# Enable HTTPS
sudo nextcloud.enable-https self-signed
# Atau untuk Let's Encrypt:
# sudo nextcloud.enable-https lets-encrypt

# Set trusted domain
sudo nextcloud.occ config:system:set trusted_domains 0 --value=your-domain.com
```

---

## Konfigurasi SSL

### Let's Encrypt (Certbot)
```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-apache
# Atau untuk Nginx:
# sudo apt install -y certbot python3-certbot-nginx

# Dapatkan certificate
sudo certbot --apache -d your-domain.com
# Atau untuk Nginx:
# sudo certbot --nginx -d your-domain.com

# Auto-renewal
sudo crontab -e
# Tambahkan:
# 0 12 * * * /usr/bin/certbot renew --quiet
```

### Self-Signed Certificate
```bash
# Buat certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nextcloud-selfsigned.key \
    -out /etc/ssl/certs/nextcloud-selfsigned.crt

# Update Apache config untuk SSL
sudo nano /etc/apache2/sites-available/nextcloud-ssl.conf
```

---

## Optimisasi Performance

### 1. PHP OPcache
```bash
sudo nano /etc/php/8.1/fpm/conf.d/10-opcache.ini
```

```ini
opcache.enable=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
```

### 2. Redis Cache
```bash
# Install Redis
sudo apt install -y redis-server

# Configure Nextcloud
sudo -u www-data php /var/www/nextcloud/occ config:system:set \
  memcache.local --value="\OC\Memcache\APCu"
sudo -u www-data php /var/www/nextcloud/occ config:system:set \
  memcache.distributed --value="\OC\Memcache\Redis"
sudo -u www-data php /var/www/nextcloud/occ config:system:set \
  redis host --value="localhost"
sudo -u www-data php /var/www/nextcloud/occ config:system:set \
  redis port --value=6379
```

### 3. Database Tuning
```bash
sudo nano /etc/mysql/conf.d/nextcloud.cnf
```

```ini
[mysqld]
innodb_buffer_pool_size = 128M
innodb_buffer_pool_instances = 1
innodb_flush_log_at_trx_commit = 2
innodb_log_buffer_size = 32M
innodb_max_dirty_pages_pct = 90
query_cache_type = 1
query_cache_limit = 2M
query_cache_size = 64M
tmp_table_size= 64M
max_heap_table_size= 64M
slow-query-log = 1
slow-query-log-file = /var/log/mysql/slow.log
long_query_time = 1
```

---

## Backup & Maintenance

### 1. Backup Script
```bash
nano ~/backup-nextcloud.sh
```

```bash
#!/bin/bash

# Configuration
NEXTCLOUD_DIR="/var/www/nextcloud"
BACKUP_DIR="/backup/nextcloud"
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS="password_yang_kuat"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Enable maintenance mode
sudo -u www-data php $NEXTCLOUD_DIR/occ maintenance:mode --on

# Backup files
tar -czf $BACKUP_DIR/nextcloud_files_$DATE.tar.gz -C $NEXTCLOUD_DIR .

# Backup database
mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > $BACKUP_DIR/nextcloud_db_$DATE.sql

# Disable maintenance mode
sudo -u www-data php $NEXTCLOUD_DIR/occ maintenance:mode --off

echo "Backup completed: $DATE"
```

```bash
chmod +x ~/backup-nextcloud.sh

# Schedule backup (daily at 2 AM)
crontab -e
# Tambahkan:
# 0 2 * * * /home/user/backup-nextcloud.sh
```

### 2. Update Nextcloud
```bash
# Manual method
sudo -u www-data php /var/www/nextcloud/updater/updater.phar

# Atau via web interface
# Akses Settings > Administration > Overview

# Atau via OCC command
sudo -u www-data php /var/www/nextcloud/occ upgrade
```

### 3. Maintenance Commands
```bash
# File scan
sudo -u www-data php /var/www/nextcloud/occ files:scan --all

# Cleanup
sudo -u www-data php /var/www/nextcloud/occ files:cleanup

# Check integrity
sudo -u www-data php /var/www/nextcloud/occ integrity:check-core

# Database optimization
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint
```

---

## Troubleshooting

### 1. Permission Issues
```bash
# Reset permissions
sudo find /var/www/nextcloud/ -type f -print0 | xargs -0 chmod 0640
sudo find /var/www/nextcloud/ -type d -print0 | xargs -0 chmod 0750
sudo chown -R www-data:www-data /var/www/nextcloud/
sudo chmod 0644 /var/www/nextcloud/.htaccess
sudo chmod 0644 /var/www/nextcloud/data/.htaccess
```

### 2. Memory Issues
```bash
# Increase PHP memory limit
sudo nano /etc/php/8.1/fpm/php.ini
# memory_limit = 1024M

# Restart PHP-FPM
sudo systemctl restart php8.1-fpm
```

### 3. Database Connection
```bash
# Test database connection
mysql -u nextcloud -p nextcloud

# Check database status
sudo systemctl status mysql
```

### 4. Log Analysis
```bash
# Nextcloud logs
sudo tail -f /var/www/nextcloud/data/nextcloud.log

# Apache logs
sudo tail -f /var/log/apache2/nextcloud_error.log

# Nginx logs
sudo tail -f /var/log/nginx/error.log

# PHP logs
sudo tail -f /var/log/php8.1-fpm.log
```

### 5. Common Issues & Solutions

#### "Data directory not writable"
```bash
sudo chown -R www-data:www-data /var/www/nextcloud/data
sudo chmod -R 0750 /var/www/nextcloud/data
```

#### "Trusted domain error"
```bash
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 0 --value=your-domain.com
```

#### "PHP OPcache not configured"
```bash
# Enable OPcache
sudo nano /etc/php/8.1/fpm/conf.d/10-opcache.ini
```

#### "Database missing indices"
```bash
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
```

---

## Security Hardening

### 1. Firewall
```bash
# UFW (Ubuntu)
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable

# iptables
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

### 2. Fail2ban
```bash
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
maxretry = 3
bantime = 3600
findtime = 36000
logpath = /var/www/nextcloud/data/nextcloud.log
```

### 3. HTTP Security Headers
Tambahkan di konfigurasi web server:
```apache
# Apache
Header set X-Content-Type-Options nosniff
Header set X-XSS-Protection "1; mode=block"
Header set X-Robots-Tag none
Header set X-Download-Options noopen
Header set X-Permitted-Cross-Domain-Policies none
Header set Referrer-Policy no-referrer
```

---

## Monitoring

### 1. Basic Monitoring Script
```bash
nano ~/monitor-nextcloud.sh
```

```bash
#!/bin/bash

# Check services
echo "=== Service Status ==="
systemctl is-active apache2 nginx mysql redis-server php8.1-fpm

# Check disk space
echo "=== Disk Usage ==="
df -h /var/www/nextcloud

# Check memory
echo "=== Memory Usage ==="
free -h

# Check Nextcloud status
echo "=== Nextcloud Status ==="
sudo -u www-data php /var/www/nextcloud/occ status
```

### 2. Log Rotation
```bash
sudo nano /etc/logrotate.d/nextcloud
```

```
/var/www/nextcloud/data/nextcloud.log {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        sudo -u www-data php /var/www/nextcloud/occ log:manage --rotate
    endscript
}
```

---

## Kesimpulan

Tutorial ini mencakup berbagai metode deployment Nextcloud Server:

1. **Manual Installation**: Kontrol penuh, cocok untuk production
2. **Docker**: Mudah di-maintain, portable
3. **Snap**: Paling mudah, auto-update

### Rekomendasi:
- **Production**: Manual installation dengan SSL certificate
- **Development**: Docker
- **Quick setup**: Snap package

### Next Steps:
1. Setup regular backup
2. Configure monitoring
3. Install apps sesuai kebutuhan
4. Setup external storage jika diperlukan
5. Configure user management (LDAP/SAML)

Selamat menggunakan Nextcloud! 🎉