FROM php:8.2-fpm

# Cache buster - force Railway rebuild: 2026-03-10-09-45

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx git zip unzip curl libpng-dev libjpeg-dev libfreetype6-dev \
    && curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o - | sh -s \
    mysqli pdo pdo_mysql gd \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy application files
COPY . /var/www/html/

# Install dependencies
RUN cd /var/www/html && composer install --no-dev --optimize-autoloader

# Set permissions
RUN chown -R www-data:www-data /var/www/html && \
    mkdir -p /var/log/nginx && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Create nginx config
RUN cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default;
    server_name localhost;
    client_max_body_size 128M;
    access_log /var/log/nginx/application.access.log;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ ^.+\.php {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PHP_VALUE "error_log=/var/log/nginx/application_php_errors.log";
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_index index.php;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Create config.php at startup
RUN cat > /start.sh << 'EOF'
#!/bin/bash

# Get values from environment or defaults
BASE_URL_VAL="${BASE_URL:-http://localhost}"
DEBUG_MODE_VAL="${DEBUG_MODE:-FALSE}"
DB_HOST_VAL="${DB_HOST:-localhost}"
DB_NAME_VAL="${DB_NAME:-easyappointments}"
DB_USERNAME_VAL="${DB_USERNAME:-root}"
DB_PASSWORD_VAL="${DB_PASSWORD:-}"

# Convert DEBUG_MODE to boolean
if [[ "$DEBUG_MODE_VAL" == "TRUE" || "$DEBUG_MODE_VAL" == "true" || "$DEBUG_MODE_VAL" == "1" ]]; then
    DEBUG_BOOL="true"
else
    DEBUG_BOOL="false"
fi

# Generate config.php with actual values
cat > /var/www/html/config.php << PHPEOF
<?php
class Config
{
    const BASE_URL = '$BASE_URL_VAL';
    const LANGUAGE = 'english';
    const DEBUG_MODE = $DEBUG_BOOL;
    const DB_HOST = '$DB_HOST_VAL';
    const DB_NAME = '$DB_NAME_VAL';
    const DB_USERNAME = '$DB_USERNAME_VAL';
    const DB_PASSWORD = '$DB_PASSWORD_VAL';
    const GOOGLE_SYNC_FEATURE = false;
    const GOOGLE_CLIENT_ID = '';
    const GOOGLE_CLIENT_SECRET = '';
}
PHPEOF

chown www-data:www-data /var/www/html/config.php

# Start PHP-FPM and nginx
php-fpm -D
nginx -g 'daemon off;'
EOF

RUN chmod +x /start.sh

EXPOSE 80

CMD ["/start.sh"]
