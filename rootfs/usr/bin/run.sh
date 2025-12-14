#!/bin/bash
set -e

CFG=/data/options.json
REMOTE_HOST=$(jq -r '.remote_host' $CFG)
REMOTE_USER=$(jq -r '.remote_user' $CFG)
REMOTE_PORT=$(jq -r '.remote_port' $CFG)

SSH_DIR=/data/ssh
CERT_DIR=/data/nginx/certs

mkdir -p $SSH_DIR $CERT_DIR

echo "Starting..."

# SSH key
if [ ! -f $SSH_DIR/id_ed25519 ]; then
  ssh-keygen -t ed25519 -f $SSH_DIR/id_ed25519 -N ""
fi
echo "==== PUBLIC SSH KEY ===="
cat $SSH_DIR/id_ed25519.pub
echo "========================"


# Self-signed cert
if [ ! -f $CERT_DIR/ha.crt ]; then
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout $CERT_DIR/ha.key \
    -out $CERT_DIR/ha.crt \
    -subj "/CN=homeassistant"
fi

# known_hosts handling
KNOWN_HOSTS=/data/ssh/known_hosts
touch $KNOWN_HOSTS
ssh-keyscan -H "$REMOTE_HOST" >> $KNOWN_HOSTS 2>/dev/null
chmod 600 /data/ssh/known_hosts

# Start nginx
nginx

# Reverse SSH tunnel loop
while true; do
  autossh \
    -M 0 \
    -N \
    -v \
    -o "ServerAliveInterval 30" \
    -o "ServerAliveCountMax 3" \
    -o "ExitOnForwardFailure yes" \
    -o "UserKnownHostsFile=/data/ssh/known_hosts" \
    -i $SSH_DIR/id_ed25519 \
    -R 0.0.0.0:${REMOTE_PORT}:localhost:443 \
    ${REMOTE_USER}@${REMOTE_HOST}
  sleep 10
done
