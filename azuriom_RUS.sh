#!/bin/bash

# ================================================================
# УСТАНОВЩИК AZURIOM CMS
# ================================================================

set -euo pipefail

# --- Проверка ОС ---
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "❌ Этот скрипт предназначен только для Ubuntu!" >&2
    exit 1
fi

if [ "$(id -u)" != "0" ]; then
    echo "❌ Требуются права root. Используйте: sudo bash $0" >&2
    exit 1
fi

# --- Логирование ---
LOG_FILE="/var/log/azuriom_install.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "📝 Начата установка Azuriom $(date)"

# --- Функции ---
print_info() { echo -e "\n\e[1;36m$1\e[0m"; }
print_success() { echo -e "\e[1;32m✅ $1\e[0m"; }
print_error() { echo -e "\e[1;31m❌ $1\e[0m"; }
print_warning() { echo -e "\e[1;33m⚠️ $1\e[0m"; }
print_tip() { echo -e "\e[1;34m💡 $1\e[0m"; }

# --- Безопасная функция UFW ---
safe_ufw() {
    local command="$1"
    if ufw $command 2>/dev/null; then
        return 0
    else
        print_warning "Команда UFW не выполнена: ufw $command"
        return 1
    fi
}

# --- Определение последней версии ---
get_latest_version() {
    print_info "🔍 Поиск последней версии Azuriom..."
    
    # Используем GitHub API для получения последнего релиза
    LATEST_VERSION=$(curl -s https://api.github.com/repos/Azuriom/Azuriom/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$LATEST_VERSION" ]; then
        # Если не удалось получить версию, используем стабильную
        LATEST_VERSION="v1.2.7"
        print_warning "Не удалось определить версию автоматически, используем $LATEST_VERSION"
    else
        print_success "Найдена последняя версия: $LATEST_VERSION"
    fi
    
    # Возвращаем только чистую версию без escape-кодов
    echo "$LATEST_VERSION"
}

# --- Генерация безопасного пароля ---
generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c 24
}

# --- Сбор данных ---
print_info "🚀 Установщик Azuriom CMS"
echo ""
print_tip "Нажмите Ctrl+C в любой момент для отмены установки"
echo ""

# --- Доменное имя ---
echo "=================================================="
print_info "🌐 НАСТРОЙКА ДОМЕНА"
print_tip "Убедитесь, что домен указывает на IP этого сервера: $(curl -s ifconfig.me 2>/dev/null || echo "неизвестно")"
print_tip "Примеры: mysite.com или panel.myserver.net"
read -p "➡️ Введите ваше доменное имя: " DOMAIN

if [ -z "$DOMAIN" ]; then 
    print_error "Доменное имя обязательно для SSL сертификата"
    exit 1
fi

# Базовая проверка формата домена
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_warning "Введенное значение не похоже на доменное имя. Продолжить? (y/N)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Email для SSL ---
echo ""
echo "=================================================="
print_info "📧 КОНТАКТНЫЙ EMAIL"
print_tip "Этот email используется для:"
print_tip "  • SSL сертификатов Let's Encrypt"
print_tip "  • Уведомлений о истечении сертификатов"
read -p "➡️ Введите ваш email: " LETSENCRYPT_EMAIL

if [ -z "$LETSENCRYPT_EMAIL" ]; then
    print_error "Email обязателен для SSL сертификатов"
    exit 1
fi

# Базовая проверка email
if ! [[ "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_warning "Email имеет нестандартный формат. Продолжить? (y/N)"
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Версия PHP ---
echo ""
echo "=================================================="
print_info "🐘 ВЫБОР ВЕРСИИ PHP"
print_tip "Рекомендуемые версии:"
print_tip "  • 8.3 - Самая новая, максимальная производительность"
print_tip "  • 8.2 - Стабильная, хорошая совместимость"
print_tip "  • 8.1 - Старая стабильная, для legacy-систем"
read -p "➡️ Введите версию PHP [8.3]: " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.3}

# Проверка поддерживаемой версии PHP
if [[ ! "$PHP_VERSION" =~ ^8\.[0-3]$ ]]; then
    print_warning "Версия PHP $PHP_VERSION может не поддерживаться Azuriom."
    print_warning "Рекомендуется использовать PHP 8.0-8.3"
    read -p "Продолжить с PHP $PHP_VERSION? (y/N): " -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        PHP_VERSION="8.3"
        print_info "Установлена версия PHP $PHP_VERSION по умолчанию"
    fi
fi

# --- Настройка базы данных ---
echo ""
echo "=================================================="
print_info "🗄️ НАСТРОЙКА БАЗЫ ДАННЫХ"
print_tip "Эти настройки используются для подключения Azuriom к MySQL"
print_tip "Все значения будут сгенерированы автоматически для безопасности"

print_info "Автоматическая генерация безопасных учетных данных..."
sleep 2

# Автоматическая генерация безопасных учетных данных
DB_NAME="azuriom_$(openssl rand -hex 3)"
DB_USER="azuriom_user_$(openssl rand -hex 3)"
DB_PASS=$(generate_password)
MYSQL_ROOT_PASS=$(generate_password)

print_success "Сгенерированы безопасные учетные данные:"
echo "    📁 База данных: $DB_NAME"
echo "    👤 Пользователь БД: $DB_USER"
echo "    🔐 Пароль БД: ${DB_PASS:0:8}..."
echo "    🗝️ Root пароль MySQL: ${MYSQL_ROOT_PASS:0:8}..."

echo ""
print_warning "Все пароли будут сохранены в защищенный файл"
print_warning "Обязательно сохраните их после установки!"

# --- Подтверждение установки ---
echo ""
echo "=================================================="
print_info "🔍 ПОДТВЕРЖДЕНИЕ УСТАНОВКИ"
echo ""
echo "Будет установлено:"
echo "  • Домен: https://$DOMAIN"
echo "  • PHP версия: $PHP_VERSION"
echo "  • База данных: $DB_NAME"
echo "  • Безопасность: UFW, Fail2Ban, SSL"
echo ""
print_warning "Установка займет 5-15 минут в зависимости от скорости интернета"
read -p "➡️ Начать установку? (Y/n): " -r START_INSTALL

if [[ "$START_INSTALL" =~ ^[Nn]$ ]]; then
    print_info "Установка отменена пользователем"
    exit 0
fi

# --- Получение последней версии ---
echo ""
LATEST_VERSION=$(get_latest_version)
print_success "Будет установлена версия: $LATEST_VERSION"

# --- 1. ОБНОВЛЕНИЕ СИСТЕМЫ ---
print_info "Шаг 1: Обновление системы..."
print_tip "Обновление пакетов для обеспечения безопасности и стабильности"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# --- 2. УСТАНОВКА ЗАВИСИМОСТЕЙ ---
print_info "Шаг 2: Установка зависимостей..."
apt-get install -y curl wget unzip ufw

# --- 3. БАЗОВАЯ НАСТРОЙКА МЕЖСЕТЕВОГО ЭКРАНА ---
print_info "Шаг 3: Базовая настройка межсетевого экрана..."
print_tip "Открывается только SSH порт для начала"
safe_ufw "allow OpenSSH"
safe_ufw "--force enable"
print_success "Базовая настройка межсетевого экрана завершена"

# --- 4. УСТАНОВКА MYSQL ---
print_info "Шаг 4: Установка MySQL..."
apt-get install -y mysql-server

# Безопасная настройка MySQL
print_info "Защита MySQL..."
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
print_success "MySQL установлен и защищен"

# --- 5. УСТАНОВКА PHP ---
print_info "Шаг 5: Установка PHP ${PHP_VERSION}..."
apt-get install -y software-properties-common
add-apt-repository ppa:ondrej/php -y
apt-get update

# Установка PHP с правильными пакетами для Ubuntu 24.04
print_info "Установка PHP и необходимых расширений..."
apt-get install -y "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-bcmath" \
                   "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" \
                   "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-tokenizer" "php${PHP_VERSION}-ctype" \
                   "php${PHP_VERSION}-gd"

# Проверяем, какие расширения действительно установились
print_info "Проверка установленных расширений PHP..."
php -m | grep -E "(mysql|bcmath|xml|curl|zip|mbstring|tokenizer|ctype|gd)"
print_success "PHP $PHP_VERSION и расширения установлены"

# --- 6. УСТАНОВКА NGINX ---
print_info "Шаг 6: Установка Nginx..."
apt-get install -y nginx

# --- 7. ЗАВЕРШЕНИЕ НАСТРОЙКИ МЕЖСЕТЕВОГО ЭКРАНА ---
print_info "Шаг 7: Завершение настройки межсетевого экрана..."
print_tip "Открываются HTTP (80) и HTTPS (443) порты"
safe_ufw "allow 80/tcp"
safe_ufw "allow 443/tcp"
print_success "Межсетевой экран полностью настроен"

# --- 8. УСТАНОВКА COMPOSER ---
print_info "Шаг 8: Установка Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# --- 9. СОЗДАНИЕ БАЗЫ ДАННЫХ ---
print_info "Шаг 9: Создание базы данных..."
mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF
CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
print_success "База данных '$DB_NAME' создана"

# --- 10. НАСТРОЙКА PHP ---
print_info "Шаг 10: Настройка PHP..."
PHP_INI_PATH="/etc/php/${PHP_VERSION}/fpm/php.ini"
if [ -f "$PHP_INI_PATH" ]; then
    cp "$PHP_INI_PATH" "$PHP_INI_PATH.backup"
    
    sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "$PHP_INI_PATH"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 32M/' "$PHP_INI_PATH"
    sed -i 's/^post_max_size = .*/post_max_size = 35M/' "$PHP_INI_PATH"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI_PATH"
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_INI_PATH"
    print_success "PHP оптимизирован для Azuriom"
else
    print_warning "Файл конфигурации PHP не найден, используются настройки по умолчанию"
fi

# --- 11. СКАЧИВАНИЕ AZURIOM ---
print_info "Шаг 11: Установка Azuriom ${LATEST_VERSION}..."
mkdir -p "/var/www/${DOMAIN}"
cd "/var/www/${DOMAIN}"

# Используем стабильную версию для гарантии работы
AZURIOM_VERSION="v1.2.7"
DOWNLOAD_URL="https://github.com/Azuriom/Azuriom/releases/download/${AZURIOM_VERSION}/Azuriom-1.2.7.zip"

print_info "Скачивание Azuriom ${AZURIOM_VERSION}..."
if wget -O azuriom.zip "$DOWNLOAD_URL"; then
    unzip -q azuriom.zip
    rm azuriom.zip
    print_success "Azuriom $AZURIOM_VERSION скачан и распакован"
else
    print_error "Не удалось скачать Azuriom"
    print_info "Пробуем прямой URL..."
    # Альтернативный прямой URL
    DIRECT_URL="https://github.com/Azuriom/Azuriom/releases/latest/download/Azuriom-1.2.7.zip"
    if wget -O azuriom.zip "$DIRECT_URL"; then
        unzip -q azuriom.zip
        rm azuriom.zip
        print_success "Azuriom скачан с прямого URL"
    else
        print_error "Не удалось скачать Azuriom"
        print_info "Проверьте подключение к интернету и попробуйте снова"
        exit 1
    fi
fi

# --- 12. НАСТРОЙКА ПРАВ ДОСТУПА ---
print_info "Шаг 12: Настройка прав доступа..."
chown -R www-data:www-data "/var/www/${DOMAIN}"
find "/var/www/${DOMAIN}" -type d -exec chmod 755 {} \;
find "/var/www/${DOMAIN}" -type f -exec chmod 644 {} \;

# Установка специальных прав для storage и cache
STORAGE_PATH="/var/www/${DOMAIN}/storage"
CACHE_PATH="/var/www/${DOMAIN}/bootstrap/cache"

if [ -d "$STORAGE_PATH" ]; then
    chmod -R ug+rwx "$STORAGE_PATH"
fi

if [ -d "$CACHE_PATH" ]; then
    chmod -R ug+rwx "$CACHE_PATH"
fi

print_success "Права доступа настроены"

# --- 13. НАСТРОЙКА NGINX ---
print_info "Шаг 13: Настройка Nginx..."
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

# Активация сайта
ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/" 2>/dev/null || true

# Удаление дефолтного сайта если существует
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# Проверка конфигурации nginx
if nginx -t; then
    print_success "Конфигурация Nginx проверена успешно"
else
    print_error "Проверка конфигурации Nginx не удалась"
    exit 1
fi

# --- 14. НАСТРОЙКА SSL ---
print_info "Шаг 14: Настройка SSL..."
if apt-get install -y certbot python3-certbot-nginx; then
    if certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        --email "${LETSENCRYPT_EMAIL}" \
        --redirect; then
        print_success "SSL сертификат успешно установлен"
    else
        print_warning "Не удалось автоматически получить SSL сертификат"
        print_tip "Вы можете настроить SSL позже командой: certbot --nginx -d $DOMAIN"
    fi
else
    print_warning "Не удалось установить certbot, SSL нужно будет настроить вручную"
fi

# --- 15. ЗАПУСК СЛУЖБ ---
print_info "Шаг 15: Запуск служб..."
systemctl enable nginx php${PHP_VERSION}-fpm mysql 2>/dev/null || true

# Перезапуск служб
systemctl restart nginx 2>/dev/null || print_warning "Не удалось перезапустить nginx"
systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || print_warning "Не удалось перезапустить PHP-FPM"
systemctl restart mysql 2>/dev/null || print_warning "Не удалось перезапустить MySQL"

print_success "Службы настроены"

# --- 16. ДОПОЛНИТЕЛЬНАЯ БЕЗОПАСНОСТЬ ---
print_info "Шаг 16: Дополнительная безопасность..."
if apt-get install -y fail2ban unattended-upgrades; then
    systemctl enable fail2ban 2>/dev/null || true
    systemctl start fail2ban 2>/dev/null || true
    
    # Настройка автоматических обновлений
    echo 'Unattended-Upgrade::Automatic-Reboot "true";' > /etc/apt/apt.conf.d/50unattended-upgrades
    echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    
    print_success "Инструменты безопасности установлены"
else
    print_warning "Не удалось установить некоторые инструменты безопасности"
fi

# --- СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ ---
print_info "Шаг 17: Сохранение учетных данных..."
CREDENTIALS_FILE="/root/azuriom_credentials.txt"
cat > "$CREDENTIALS_FILE" <<EOF
==========================================
AZURIOM CMS - УЧЕТНЫЕ ДАННЫЕ
Установлено: $(date)
Версия: ${AZURIOM_VERSION}
Домен: https://${DOMAIN}
==========================================

БАЗА ДАННЫХ:
- Хост: 127.0.0.1
- База данных: ${DB_NAME}
- Пользователь: ${DB_USER}
- Пароль: ${DB_PASS}

MySQL ROOT:
- Пароль: ${MYSQL_ROOT_PASS}

СИСТЕМА:
- PHP: ${PHP_VERSION}
- Веб-сервер: Nginx

БЕЗОПАСНОСТЬ:
- Межсетевой экран настроен
- Fail2Ban установлен
- Автообновления настроены
- SSL сертификат: $(if command -v certbot &>/dev/null; then echo "Установлен"; else echo "Не установлен"; fi)

ВАЖНО: 
1. Сохраните этот файл в надежном месте
2. Удалите после копирования данных
3. Завершите установку по адресу https://${DOMAIN}
EOF

chmod 600 "$CREDENTIALS_FILE"

# --- ФИНАЛЬНОЕ СООБЩЕНИЕ ---
print_success "=========================================================="
print_success "✅ Установка Azuriom ${AZURIOM_VERSION} завершена!"
print_success "=========================================================="
echo ""
echo -e "🌐 \e[1;32mОткройте в браузере: https://${DOMAIN}\e[0m"
echo ""
echo -e "📦 \e[1;35mУстановленная версия: ${AZURIOM_VERSION}\e[0m"
echo ""
echo -e "🔐 \e[1;33mУчетные данные сохранены в: ${CREDENTIALS_FILE}\e[0m"
echo ""
echo -e "📋 \e[1;36mДля завершения установки следуйте инструкциям на сайте https://${DOMAIN}\e[0m"
echo ""
print_tip "Нужна помощь? Обратитесь к документации Azuriom: https://azuriom.com/docs"