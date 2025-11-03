#!/bin/bash

# ================================================================
# AZURIOM CMS INSTALLER - STABLE VERSION
# ================================================================

set -euo pipefail

# --- OS Check ---
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "❌ This script is for Ubuntu only!" >&2
    exit 1
fi

if [ "$(id -u)" != "0" ]; then
    echo "❌ Root privileges required. Use: sudo bash $0" >&2
    exit 1
fi

# --- Logging ---
LOG_FILE="/var/log/azuriom_install.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "📝 Starting Azuriom installation $(date)"

# --- Functions ---
print_info() { echo -e "\n\e[1;36m$1\e[0m"; }
print_success() { echo -e "\e[1;32m✅ $1\e[0m"; }
print_error() { echo -e "\e[1;31m❌ $1\e[0m"; }
print_warning() { echo -e "\e[1;33m⚠️ $1\e[0m"; }
print_tip() { echo -e "\e[1;34m💡 $1\e[0m"; }

# --- Safe UFW function ---
safe_ufw() {
    local command="$1"
    if ufw $command 2>/dev/null; then
        return 0
    else
        print_warning "UFW command failed: ufw $command"
        return 1
    fi
}

# --- Latest Version Detection ---
get_latest_version() {
    print_info "🔍 Searching for latest Azuriom version..."
    
    # Use GitHub API to get latest release
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Azuriom/Azuriom/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v1.2.7")
    
    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "v1.2.7" ]; then
        print_warning "Could not auto-detect version, using v1.2.7"
    else
        print_success "Found latest version: $LATEST_VERSION"
    fi
    
    echo "$LATEST_VERSION"
}

# --- Secure Password Generation ---
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c 24
}

# --- Data Collection ---
print_info "🚀 Azuriom CMS Installer"
echo ""
print_tip "Press Ctrl+C at any time to cancel installation"
echo ""

# --- Domain Name ---
echo "=================================================="
print_info "🌐 DOMAIN SETUP"
print_tip "Make sure your domain points to this server's IP: $(curl -s ifconfig.me 2>/dev/null || echo "unknown")"
print_tip "Examples: mysite.com or panel.myserver.net"
read -p "➡️ Enter your domain name: " DOMAIN

if [ -z "$DOMAIN" ]; then 
    print_error "Domain name is required for SSL certificate"
    exit 1
fi

# Basic domain format check
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_warning "The entered value doesn't look like a domain name. Continue? (y/N)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- SSL Email ---
echo ""
echo "=================================================="
print_info "📧 CONTACT EMAIL"
print_tip "This email is used for:"
print_tip "  • Let's Encrypt SSL certificates"
print_tip "  • Certificate expiration notifications"
read -p "➡️ Enter your email: " LETSENCRYPT_EMAIL

if [ -z "$LETSENCRYPT_EMAIL" ]; then
    print_error "Email is required for SSL certificates"
    exit 1
fi

# Basic email validation
if ! [[ "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_warning "Email has non-standard format. Continue? (y/N)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- PHP Version ---
echo ""
echo "=================================================="
print_info "🐘 PHP VERSION SELECTION"
print_tip "Recommended versions:"
print_tip "  • 8.3 - Latest, maximum performance"
print_tip "  • 8.2 - Stable, good compatibility"
print_tip "  • 8.1 - Old stable, for legacy systems"
read -p "➡️ Enter PHP version [8.3]: " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

# Check supported PHP version
if [[ ! "$PHP_VERSION" =~ ^8\.[0-3]$ ]]; then
    print_warning "PHP version $PHP_VERSION may not be supported by Azuriom."
    print_warning "Recommended to use PHP 8.0-8.3"
    read -p "Continue with PHP $PHP_VERSION? (y/N): " -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        PHP_VERSION="8.3"
        print_info "Using default PHP version $PHP_VERSION"
    fi
fi

# --- Database Setup ---
echo ""
echo "=================================================="
print_info "🗄️ DATABASE SETUP"
print_tip "These settings are used for Azuriom to connect to MySQL"
print_tip "All values will be auto-generated for security"

print_info "Auto-generating secure credentials..."
sleep 2

# Auto-generate secure credentials
DB_NAME="azuriom_$(openssl rand -hex 3)"
DB_USER="azuriom_user_$(openssl rand -hex 3)"
DB_PASS=$(generate_password)
MYSQL_ROOT_PASS=$(generate_password)

print_success "Generated secure credentials:"
echo "    📁 Database: $DB_NAME"
echo "    👤 DB User: $DB_USER"
echo "    🔐 DB Password: ${DB_PASS:0:8}..."
echo "    🗝️ MySQL Root Password: ${MYSQL_ROOT_PASS:0:8}..."

echo ""
print_warning "All passwords will be saved to a secure file"
print_warning "Make sure to save them after installation!"

# --- Installation Confirmation ---
echo ""
echo "=================================================="
print_info "🔍 INSTALLATION CONFIRMATION"
echo ""
echo "Will be installed:"
echo "  • Domain: https://$DOMAIN"
echo "  • PHP version: $PHP_VERSION"
echo "  • Database: $DB_NAME"
echo "  • Security: UFW, Fail2Ban, SSL"
echo ""
print_warning "Installation will take 5-15 minutes depending on internet speed"
read -p "➡️ Start installation? (Y/n): " -r START_INSTALL

if [[ "$START_INSTALL" =~ ^[Nn]$ ]]; then
    print_info "Installation cancelled by user"
    exit 0
fi

# --- Get Latest Version ---
echo ""
LATEST_VERSION=$(get_latest_version)
print_success "Will install version: $LATEST_VERSION"

# --- 1. SYSTEM UPDATE ---
print_info "Step 1: Updating system..."
print_tip "Updating packages for security and stability"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# --- 2. INSTALL DEPENDENCIES ---
print_info "Step 2: Installing dependencies..."
apt-get install -y curl wget unzip ufw

# --- 3. BASIC FIREWALL SETUP ---
print_info "Step 3: Basic firewall setup..."
print_tip "Opening SSH port only for now"
safe_ufw "allow OpenSSH"
safe_ufw "--force enable"
print_success "Basic firewall configured"

# --- 4. INSTALL MYSQL ---
print_info "Step 4: Installing MySQL..."
apt-get install -y mysql-server

# Secure MySQL installation
print_info "Securing MySQL..."
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
print_success "MySQL installed and secured"

# --- 5. INSTALL PHP ---
print_info "Step 5: Installing PHP ${PHP_VERSION}..."
apt-get install -y software-properties-common
add-apt-repository ppa:ondrej/php -y
apt-get update

apt-get install -y "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-bcmath" \
                   "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" \
                   "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-tokenizer" "php${PHP_VERSION}-ctype" \
                   "php${PHP_VERSION}-json" "php${PHP_VERSION}-openssl" "php${PHP_VERSION}-gd"
print_success "PHP $PHP_VERSION and all extensions installed"

# --- 6. INSTALL NGINX ---
print_info "Step 6: Installing Nginx..."
apt-get install -y nginx

# --- 7. COMPLETE FIREWALL SETUP ---
print_info "Step 7: Completing firewall setup..."
print_tip "Opening HTTP (80) and HTTPS (443) ports"
safe_ufw "allow 80/tcp"
safe_ufw "allow 443/tcp"
print_success "Firewall fully configured"

# --- 8. INSTALL COMPOSER ---
print_info "Step 8: Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# --- 9. CREATE DATABASE ---
print_info "Step 9: Creating database..."
mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF
CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
print_success "Database '$DB_NAME' created"

# --- 10. CONFIGURE PHP ---
print_info "Step 10: Configuring PHP..."
PHP_INI_PATH="/etc/php/${PHP_VERSION}/fpm/php.ini"
if [ -f "$PHP_INI_PATH" ]; then
    cp "$PHP_INI_PATH" "$PHP_INI_PATH.backup"
    
    sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "$PHP_INI_PATH"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 32M/' "$PHP_INI_PATH"
    sed -i 's/^post_max_size = .*/post_max_size = 35M/' "$PHP_INI_PATH"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI_PATH"
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_INI_PATH"
    print_success "PHP optimized for Azuriom"
else
    print_warning "PHP configuration file not found, using defaults"
fi

# --- 11. DOWNLOAD AZURIOM ---
print_info "Step 11: Installing Azuriom ${LATEST_VERSION}..."
mkdir -p "/var/www/${DOMAIN}"
cd "/var/www/${DOMAIN}"

DOWNLOAD_URL="https://github.com/Azuriom/Azuriom/releases/download/${LATEST_VERSION}/Azuriom-${LATEST_VERSION#v}.zip"
if wget -O azuriom.zip "$DOWNLOAD_URL"; then
    unzip -q azuriom.zip
    rm azuriom.zip
    print_success "Azuriom $LATEST_VERSION downloaded and extracted"
else
    print_error "Failed to download Azuriom"
    print_info "Trying alternative URL..."
    DOWNLOAD_URL="https://github.com/Azuriom/Azuriom/releases/latest/download/Azuriom-${LATEST_VERSION#v}.zip"
    if wget -O azuriom.zip "$DOWNLOAD_URL"; then
        unzip -q azuriom.zip
        rm azuriom.zip
        print_success "Azuriom $LATEST_VERSION downloaded from alternative URL"
    else
        print_error "Failed to download Azuriom from all URLs"
        exit 1
    fi
fi

# --- 12. SET FILE PERMISSIONS ---
print_info "Step 12: Setting file permissions..."
chown -R www-data:www-data "/var/www/${DOMAIN}"
find "/var/www/${DOMAIN}" -type d -exec chmod 755 {} \;
find "/var/www/${DOMAIN}" -type f -exec chmod 644 {} \;

# Set special permissions for storage and cache
STORAGE_PATH="/var/www/${DOMAIN}/storage"
CACHE_PATH="/var/www/${DOMAIN}/bootstrap/cache"

if [ -d "$STORAGE_PATH" ]; then
    chmod -R ug+rwx "$STORAGE_PATH"
fi

if [ -d "$CACHE_PATH" ]; then
    chmod -R ug+rwx "$CACHE_PATH"
fi

print_success "File permissions configured"

# --- 13. CONFIGURE NGINX ---
print_info "Step 13: Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root /var/www/${DOMAIN}/public;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Activate site
ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/" 2>/dev/null || true

# Remove default site if exists
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# Test nginx configuration
if nginx -t; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# --- 14. SSL SETUP ---
print_info "Step 14: Setting up SSL..."
if apt-get install -y certbot python3-certbot-nginx; then
    if certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        --email "${LETSENCRYPT_EMAIL}" \
        --redirect; then
        print_success "SSL certificate installed successfully"
    else
        print_warning "Failed to obtain SSL certificate automatically"
        print_tip "You can configure SSL later with: certbot --nginx -d $DOMAIN"
    fi
else
    print_warning "Failed to install certbot, SSL will need to be configured manually"
fi

# --- 15. START SERVICES ---
print_info "Step 15: Starting services..."
systemctl enable nginx php${PHP_VERSION}-fpm mysql 2>/dev/null || true

# Restart services
systemctl restart nginx 2>/dev/null || print_warning "Could not restart nginx"
systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || print_warning "Could not restart PHP-FPM"
systemctl restart mysql 2>/dev/null || print_warning "Could not restart MySQL"

print_success "Services configured"

# --- 16. ADDITIONAL SECURITY ---
print_info "Step 16: Additional security..."
if apt-get install -y fail2ban unattended-upgrades; then
    systemctl enable fail2ban 2>/dev/null || true
    systemctl start fail2ban 2>/dev/null || true
    
    # Configure automatic updates
    echo 'Unattended-Upgrade::Automatic-Reboot "true";' > /etc/apt/apt.conf.d/50unattended-upgrades
    echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    
    print_success "Security tools installed"
else
    print_warning "Failed to install some security tools"
fi

# --- SAVE CREDENTIALS ---
print_info "Step 17: Saving credentials..."
CREDENTIALS_FILE="/root/azuriom_credentials.txt"
cat > "$CREDENTIALS_FILE" <<EOF
==========================================
AZURIOM CMS - CREDENTIALS
Installed: $(date)
Version: ${LATEST_VERSION}
Domain: https://${DOMAIN}
==========================================

DATABASE:
- Host: 127.0.0.1
- Database: ${DB_NAME}
- User: ${DB_USER}
- Password: ${DB_PASS}

MySQL ROOT:
- Password: ${MYSQL_ROOT_PASS}

SYSTEM:
- PHP: ${PHP_VERSION}
- Web Server: Nginx

SECURITY:
- Firewall configured
- Fail2Ban installed
- Auto-updates configured
- SSL certificate: $(if command -v certbot &>/dev/null; then echo "Installed"; else echo "Not installed"; fi)

IMPORTANT: 
1. Save this file in a secure location
2. Delete after copying credentials
3. Complete the setup at https://${DOMAIN}
EOF

chmod 600 "$CREDENTIALS_FILE"

# --- FINAL MESSAGE ---
print_success "=========================================================="
print_success "✅ Azuriom ${LATEST_VERSION} installation completed!"
print_success "=========================================================="
echo ""
echo -e "🌐 \e[1;32mOpen in browser: https://${DOMAIN}\e[0m"
echo ""
echo -e "📦 \e[1;35mInstalled version: ${LATEST_VERSION}\e[0m"
echo ""
echo -e "🔐 \e[1;33mCredentials saved to: ${CREDENTIALS_FILE}\e[0m"
echo ""
echo -e "📋 \e[1;36mFollow the on-screen instructions at https://${DOMAIN} to complete setup\e[0m"
echo ""
print_tip "Need help? Check Azuriom documentation: https://azuriom.com/docs"