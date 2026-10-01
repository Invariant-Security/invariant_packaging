#!/usr/bin/env bash
# Roda o postinst real duas vezes num Debian 12 limpo (container) e prova que
# a segunda instalação/atualização não muda nenhum segredo nem o
# certificado. Sem Docker no container o postinst termina na checagem do
# Docker -- o provisionamento acontece antes disso, que é o que importa aqui.
#
# Uso: tests/postinst_preserves_secrets.sh <caminho do provision.sh do invariant_api>
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROVISION="$(realpath "${1:?uso: $0 <invariant_api/provision.sh>}")"

docker run --rm -v "$HERE/scripts/postinst:/postinst:ro" -v "$PROVISION:/provision.sh:ro" debian:12 bash -c '
set -euo pipefail
apt-get update -qq >/dev/null && apt-get install -y -qq openssl hostname >/dev/null
mkdir -p /opt/invariant && install -m 755 /provision.sh /opt/invariant/provision.sh
sed "s/__INVARIANT_VERSION__/9.9.9/" /postinst > /tmp/postinst && chmod +x /tmp/postinst
snapshot() { grep -v "^INVARIANT_VERSION=" /etc/invariant/.env | sort; openssl x509 -in /etc/invariant/tls/cert.pem -noout -fingerprint -sha256; }
/tmp/postinst configure >/dev/null 2>&1 || true
first="$(snapshot)"
/tmp/postinst configure 1.0 >/dev/null 2>&1 || true
second="$(snapshot)"
for name in INVARIANT_API_SECRET_KEY INVARIANT_INTERNAL_ASSESSMENT_TOKEN INVARIANT_INTERNAL_DISCOVERY_TOKEN \
            INVARIANT_INTERNAL_INGESTION_TOKEN INVARIANT_INTERNAL_GATEWAY_TOKEN INVARIANT_USAGE_HMAC_KEY \
            INVARIANT_INSTALLATION_ID INVARIANT_WEB_PORT INVARIANT_HTTPS_PORT; do
    grep -q "^${name}=." /etc/invariant/.env || { echo "FALHA: $name ausente"; exit 1; }
done
[ "$(stat -c %a /etc/invariant/.env)" = 600 ] || { echo "FALHA: .env não é 600"; exit 1; }
[ "$(stat -c %a /etc/invariant/tls/key.pem)" = 600 ] || { echo "FALHA: key.pem não é 600"; exit 1; }
grep -q "^INVARIANT_VERSION=v9.9.9$" /etc/invariant/.env || { echo "FALHA: versão não gravada"; exit 1; }
[ "$first" = "$second" ] || { echo "FALHA: segunda execução mudou segredos/certificado"; diff <(echo "$first") <(echo "$second"); exit 1; }
echo "OK: postinst 2x preserva segredos, portas e certificado"
'
