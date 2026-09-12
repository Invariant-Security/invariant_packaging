#!/usr/bin/env bash
# Builda o pacote .deb do Invariant appliance. Não builda nenhuma imagem
# Docker aqui -- isso é o publish-image.yml de cada repo invariant_*,
# rodado antes desta tag existir. Este script só empacota o systemd
# unit + scripts + o docker-compose.appliance.yml/nginx.appliance.conf já
# publicados na tag correspondente do invariant_api.
set -euo pipefail

VERSION="${1:?usage: build.sh <version, e.g. 0.2.0> -- deve bater com a tag v<version> de invariant_api}"
API_REPO_REF="v${VERSION}"
API_RAW_BASE="https://raw.githubusercontent.com/Invariant-Security/invariant_api/${API_REPO_REF}"

if ! command -v fpm >/dev/null 2>&1; then
    echo "fpm não encontrado -- instale com: gem install --no-document fpm" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/opt/invariant" "$STAGE/etc/systemd/system"

curl -fsSL "${API_RAW_BASE}/docker-compose.appliance.yml" -o "$STAGE/opt/invariant/docker-compose.appliance.yml"
curl -fsSL "${API_RAW_BASE}/nginx.appliance.conf" -o "$STAGE/opt/invariant/nginx.appliance.conf"
cp "$(dirname "$0")/systemd/invariant.service" "$STAGE/etc/systemd/system/invariant.service"

mkdir -p "$STAGE/scripts"
sed "s/__INVARIANT_VERSION__/${VERSION}/" "$(dirname "$0")/scripts/postinst" > "$STAGE/scripts/postinst"
chmod 755 "$STAGE/scripts/postinst"

fpm -s dir -t deb \
    -n invariant \
    -v "$VERSION" \
    --description "Invariant security appliance -- on-prem endpoint discovery and benchmark assessment. Runs entirely on the client's own infrastructure; no data leaves the machine." \
    --url "https://invariantsec.org" \
    --license proprietary \
    --depends "docker-ce | docker.io" \
    --depends "docker-compose-plugin" \
    --after-install "$STAGE/scripts/postinst" \
    --before-remove "$(dirname "$0")/scripts/prerm" \
    --after-remove "$(dirname "$0")/scripts/postrm" \
    --deb-no-default-config-files \
    -C "$STAGE" \
    opt etc

echo "built invariant_${VERSION}_amd64.deb"
