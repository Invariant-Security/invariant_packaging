#!/usr/bin/env bash
# Prova a extração dos 4 arquivos de /opt/invariant/appliance/ de uma imagem
# (docker create + cp + rm), usando a função real de install.sh e de
# scripts/postinst contra uma imagem descartável construída aqui (não
# depende da imagem real do invariant_api). Docker real, sem registry.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; IMG="invariant-extract-test:$$"
trap 'docker rmi -f "$IMG" >/dev/null 2>&1 || true; rm -rf "$W"' EXIT

mkdir "$W/ctx"
for f in docker-compose.appliance.yml nginx.appliance.conf provision.sh bootstrap-documents.sh; do echo "fake $f" > "$W/ctx/$f"; done
cat > "$W/ctx/Dockerfile" <<'D'
FROM busybox
COPY . /opt/invariant/appliance/
CMD ["true"]
D
docker build -q -t "$IMG" "$W/ctx" >/dev/null

for src in install.sh scripts/postinst; do
    out="$W/out-$(basename "$src")"
    sed -n '/^# >>> extract_appliance/,/^# <<< extract_appliance/p' "$HERE/$src" > "$W/fn.sh"
    [ -s "$W/fn.sh" ] || { echo "FALHA: função ausente em $src"; exit 1; }
    sh -c ". '$W/fn.sh'; extract_appliance '$IMG' '$out'"
    for f in docker-compose.appliance.yml nginx.appliance.conf provision.sh bootstrap-documents.sh; do
        grep -q "fake $f" "$out/$f" || { echo "FALHA: $f não extraído ($src)"; exit 1; }
    done
    [ -x "$out/provision.sh" ] && [ -x "$out/bootstrap-documents.sh" ] || { echo "FALHA: não executáveis ($src)"; exit 1; }
    [ -z "$(docker ps -aq --filter "ancestor=$IMG")" ] || { echo "FALHA: container sobrou ($src)"; exit 1; }
    # imagem sem o diretório do contrato deve falhar
    ! sh -c ". '$W/fn.sh'; extract_appliance busybox '$W/bad-$(basename "$src")'" 2>/dev/null || { echo "FALHA: aceitou imagem sem contrato ($src)"; exit 1; }
done
echo "OK: extração dos 4 arquivos (install.sh e postinst)"
