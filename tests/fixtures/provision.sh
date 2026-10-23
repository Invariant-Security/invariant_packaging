#!/bin/sh
# Stand-in mínimo do provision.sh do invariant_api (privado): gera cada
# segredo só se faltar. O provision real tem teste próprio no repo do api.
env_file="$1"; tls="$2"
mkdir -p "$tls"
for k in INVARIANT_API_SECRET_KEY INVARIANT_INTERNAL_ASSESSMENT_TOKEN INVARIANT_INTERNAL_DISCOVERY_TOKEN \
         INVARIANT_INTERNAL_INGESTION_TOKEN INVARIANT_INTERNAL_GATEWAY_TOKEN INVARIANT_USAGE_HMAC_KEY INVARIANT_INSTALLATION_ID; do
    grep -q "^$k=." "$env_file" || echo "$k=$(openssl rand -hex 16)" >> "$env_file"
done
[ -f "$tls/key.pem" ] || openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tls/key.pem" -out "$tls/cert.pem" -subj /CN=x -days 1 2>/dev/null
chmod 600 "$tls/key.pem"
