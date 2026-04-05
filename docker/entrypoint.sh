#!/bin/bash
set -e

echo "========================================="
echo "  Laravel Docker Template — Dev Setup"
echo "========================================="

# 1. ถ้ายังไม่มี Laravel → สร้างโปรเจกต์ใหม่ให้อัตโนมัติ
if [ ! -f "/var/www/composer.json" ]; then
    echo "No Laravel project found. Creating new Laravel 10 project..."
    composer create-project laravel/laravel:^10 /tmp/laravel --no-interaction --prefer-dist
    cp -rT /tmp/laravel /var/www
    rm -rf /tmp/laravel
    echo "Laravel project created!"
else
    echo "Laravel project found. Installing dependencies..."
    composer install --no-interaction --prefer-dist
fi

# 2. สร้าง .env ถ้ายังไม่มี
if [ ! -f "/var/www/.env" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

# 3. สร้าง APP_KEY ถ้ายังไม่มี
if ! grep -q "APP_KEY=base64:" /var/www/.env; then
    echo "Generating APP_KEY..."
    php artisan key:generate --force
else
    echo "APP_KEY already exists, skipping..."
fi

# 4. รอ MySQL พร้อม
echo "Waiting for MySQL to be ready..."
max_retries=30
counter=0
until mysqladmin ping -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" --silent 2>/dev/null; do
    counter=$((counter + 1))
    if [ $counter -ge $max_retries ]; then
        echo "MySQL not ready after ${max_retries} attempts, continuing anyway..."
        break
    fi
    echo "  Waiting for MySQL... (${counter}/${max_retries})"
    sleep 2
done

# 5. รัน Migration
echo "Running database migrations..."
php artisan migrate --force 2>/dev/null || echo "Migration skipped (DB may not be ready yet)"

# 6. ตั้งค่า Permissions
echo "Setting permissions..."
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache 2>/dev/null || true
chmod -R 775 /var/www/storage /var/www/bootstrap/cache 2>/dev/null || true

echo "========================================="
echo "  Laravel Ready!"
echo "  Laravel:   http://localhost:8000"
echo "  .NET API:  http://localhost:5000"
echo "  MySQL:     localhost:3306"
echo "========================================="

# 7. รัน PHP-FPM
exec php-fpm
