#!/bin/sh
set -e

ADDON_DIR=.
mkdir -p $ADDON_DIR/rootfs/etc/nginx
mkdir -p $ADDON_DIR/rootfs/usr/bin
mkdir -p $ADDON_DIR/rootfs/config/nginx/certs
mkdir -p $ADDON_DIR/rootfs/config/ssh

########################
# Dockerfile
########################
cat > $ADDON_DIR/Dockerfile <<'EOF'
FROM alpine:3.19

RUN apk add --no-cache \
    nginx \
    openssh-client \
    autossh \
    openssl \
    bash

COPY rootfs /

RUN chmod +x /usr/bin/run.sh

CMD ["/usr/bin/run.sh"]
EOF

########################
# config.yaml (HA Add-on)
########################
cat > $ADDON_DIR/config.yaml <<'EOF'
name: Reverse SSH Tunnel with NGINX
slug: reverse_ssh_nginx
description: Reverse SSH tunnel exposing Home Assistant via NGINX over HTTPS
version: "1.0.0"
startup: services
boot: auto
host_network: false
ingress: false
panel_icon: mdi:ssh
options:
  remote_host: example.com
  remote_user: user
  remote_port: 8443
schema:
  remote_host: str
  remote_user: str
  remote_port: int
map:
  - config:rw
ports:
  443/tcp: null
EOF

########################
# NGINX config
########################
cat > $ADDON_DIR/rootfs/etc/nginx/nginx.conf <<'EOF'
events {}

http {
    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate     /config/nginx/certs/ha.crt;
        ssl_certificate_key /config/nginx/certs/ha.key;

        location / {
            proxy_pass http://homeassistant:8123;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto https;
        }
    }
}
EOF

########################
# run.sh (entrypoint)
########################
cat > $ADDON_DIR/rootfs/usr/bin/run.sh <<'EOF'
#!/bin/bash
set -e

CFG=/data/options.json
REMOTE_HOST=$(jq -r '.remote_host' $CFG)
REMOTE_USER=$(jq -r '.remote_user' $CFG)
REMOTE_PORT=$(jq -r '.remote_port' $CFG)

SSH_DIR=/config/ssh
CERT_DIR=/config/nginx/certs

mkdir -p $SSH_DIR $CERT_DIR

# SSH key
if [ ! -f $SSH_DIR/id_ed25519 ]; then
  ssh-keygen -t ed25519 -f $SSH_DIR/id_ed25519 -N ""
  echo "==== PUBLIC SSH KEY ===="
  cat $SSH_DIR/id_ed25519.pub
  echo "========================"
fi

# Self-signed cert
if [ ! -f $CERT_DIR/ha.crt ]; then
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout $CERT_DIR/ha.key \
    -out $CERT_DIR/ha.crt \
    -subj "/CN=homeassistant"
fi

# Start nginx
nginx

# Reverse SSH tunnel loop
while true; do
  autossh \
    -M 0 \
    -N \
    -o "ServerAliveInterval 30" \
    -o "ServerAliveCountMax 3" \
    -o "ExitOnForwardFailure yes" \
    -i $SSH_DIR/id_ed25519 \
    -R 0.0.0.0:${REMOTE_PORT}:localhost:443 \
    ${REMOTE_USER}@${REMOTE_HOST}
  sleep 10
done
EOF

echo "Addon created in ./$ADDON_DIR"
echo "Install as a local Home Assistant add-on."
