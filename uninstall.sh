#!/usr/bin/env bash
# Companheiro do install.sh -- espelha a distinção remove-vs-purge do .deb
# (ver scripts/prerm e scripts/postrm): sem flag só para os containers
# (mantém config e dados, uma reinstalação depois recupera tudo); com
# --purge também apaga /etc/invariant, /opt/invariant e os volumes
# nomeados -- destrutivo de propósito, por isso pede confirmação mesmo
# com INVARIANT_ASSUME_YES=1 (só INVARIANT_ASSUME_PURGE=1 pula essa).
set -euo pipefail

ENV_FILE=/etc/invariant/.env
INSTALL_DIR=/opt/invariant
PURGE=0

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        *)
            echo "uso: uninstall.sh [--purge]" >&2
            exit 1
            ;;
    esac
done

log_info() { printf '%s\n' "$1"; }
log_err()  { printf '%s\n' "$1" >&2; }

# Ver comentário equivalente em install.sh -- `-e /dev/tty` não detecta
# ausência de terminal de controle, só de fato tentar abrir detecta.
tty_available() { ( : < /dev/tty ) 2>/dev/null; }

if [ "$(id -u)" -ne 0 ]; then
    log_err "Precisa rodar como root: sudo bash uninstall.sh ${*}"
    exit 1
fi

if [ -f "$ENV_FILE" ] && [ -f "${INSTALL_DIR}/docker-compose.appliance.yml" ]; then
    log_info "Parando o stack..."
    docker compose -f "${INSTALL_DIR}/docker-compose.appliance.yml" --env-file "$ENV_FILE" down
else
    log_info "Stack não encontrado em ${INSTALL_DIR} (já removido ou nunca instalado por aqui)."
fi

if [ "$PURGE" -eq 0 ]; then
    log_info "Containers parados. Configuração e dados mantidos em ${ENV_FILE} e nos volumes Docker."
    log_info "Rode 'install.sh' de novo pra recuperar tudo, ou 'uninstall.sh --purge' pra apagar de vez."
    exit 0
fi

log_info ""
log_info "--purge vai apagar PERMANENTEMENTE:"
log_info "  - ${ENV_FILE} (inclui o INVARIANT_API_SECRET_KEY -- invalida toda sessão)"
log_info "  - ${INSTALL_DIR}"
log_info "  - os volumes Docker com os dados do Postgres e uploads"
log_info ""

if [ "${INVARIANT_ASSUME_PURGE:-0}" != "1" ]; then
    if ! tty_available; then
        log_err "Sem terminal interativo pra confirmar --purge."
        log_err "Rode de novo com INVARIANT_ASSUME_PURGE=1 se tiver certeza."
        exit 1
    fi
    read -r -p "Confirma a remoção permanente? [y/N] " answer < /dev/tty
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *)
            log_info "Cancelado -- nada foi apagado."
            exit 0
            ;;
    esac
fi

rm -rf /etc/invariant "$INSTALL_DIR"
docker volume rm invariant-appliance_pgdata_appliance invariant-appliance_appliance_data_raw invariant-appliance_appliance_data_demo 2>/dev/null || true

log_info "Removido."
