FROM php:8.2-fpm

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
cat > /var/www/html/config.php << 'PHPEOF'
<?php
// Read environment variables
\$baseUrl = getenv('BASE_URL') ?: ((!empty(\$_SERVER['HTTPS']) ? 'https' : 'http') . '://' . (\$_SERVER['HTTP_HOST'] ?? 'localhost'));
\$debugMode = getenv('DEBUG_MODE') ?: 'FALSE';
\$dbHost = getenv('DB_HOST') ?: 'localhost';
\$dbName = getenv('DB_NAME') ?: 'easyappointments';
\$dbUsername = getenv('DB_USERNAME') ?: 'root';
\$dbPassword = getenv('DB_PASSWORD') ?: '';

class Config
{
    public static \$BASE_URL;
    public static \$LANGUAGE = 'english';
    public static \$DEBUG_MODE;
    public static \$DB_HOST;
    public static \$DB_NAME;
    public static \$DB_USERNAME;
    public static \$DB_PASSWORD;
    public static \$GOOGLE_SYNC_FEATURE = false;
    public static \$GOOGLE_CLIENT_ID = '';
    public static \$GOOGLE_CLIENT_SECRET = '';
}

Config::\$BASE_URL = \$baseUrl;
Config::\$DEBUG_MODE = (\$debugMode === 'TRUE' || \$debugMode === 'true' || \$debugMode === '1');
Config::\$DB_HOST = \$dbHost;
Config::\$DB_NAME = \$dbName;
Config::\$DB_USERNAME = \$dbUsername;
Config::\$DB_PASSWORD = \$dbPassword;
PHPEOF

chown www-data:www-data /var/www/html/config.php

# Start PHP-FPM and nginx
php-fpm -D
nginx -g 'daemon off;'
EOF

RUN chmod +x /start.sh

EXPOSE 80

CMD ["/start.sh"]
