#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(grep '^WP_ADMIN_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)
WP_USER_PASSWORD=$(grep '^WP_USER_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)

echo "[setup_wp] Waiting for MariaDB at ${MYSQL_HOST}..."
until mariadb-admin ping -h"${MYSQL_HOST}" -u"${MYSQL_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; do
    sleep 2
done

if [ ! -f /var/www/html/wp-config.php ]; then
    echo "[setup_wp] Downloading and configuring WordPress"

    wp core download --allow-root --path=/var/www/html --force

    wp config create --allow-root \
        --path=/var/www/html \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${MYSQL_HOST}"

    wp core install --allow-root \
        --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --allow-root \
        --path=/var/www/html \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author

    chown -R www-data:www-data /var/www/html
    echo "[setup_wp] WordPress installation complete"
fi

# PID 1: run php-fpm in the foreground
exec php-fpm8.2 -F
