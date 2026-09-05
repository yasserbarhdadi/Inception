#!/bin/bash
set -e

mkdir -p /etc/nginx/ssl

if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    echo "[nginx] Generating self-signed TLS certificate for ${DOMAIN_NAME}"
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=MA/ST=Casablanca/L=Casablanca/O=42/OU=Inception/CN=${DOMAIN_NAME}"
fi

envsubst '${DOMAIN_NAME}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# PID 1: run nginx in the foreground
exec nginx -g "daemon off;"
