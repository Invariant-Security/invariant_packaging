#!/usr/bin/env bash
# Segundo canal de instalação do Invariant appliance, ao lado do .deb (ver
# build.sh) -- sem repositório apt assinado de propósito (decisão
# explícita: complexidade desnecessária pro volume esperado). Só valida o
# ambiente do cliente, mostra o que falta na tela, pergunta Y/N por
# dependência faltante, e só instala depois de confirmado. Não builda
# nenhuma imagem Docker -- puxa as mesmas imagens publicadas por tag que
# o .deb usa (ver .github/workflows/publish-image.yml de cada repo
# invariant_*), e busca docker-compose.appliance.yml/nginx.appliance.conf
# de invariant_api na mesma tag, igual build.sh já faz.
#
# Uso:
#   curl -fsSL <raw-url-deste-arquivo> | sudo bash -s -- 0.1.5
# Ou, sem argumento, resolve a tag mais recente de invariant_api via API
# pública do GitHub (sem autenticação -- suficiente pro volume esperado
# de instalações; se isso virar gargalo real, é hora de repensar).
#
# INVARIANT_ASSUME_YES=1 pula todos os prompts (assume Y) -- necessário
# pra automação, já que `curl URL | bash` consome o stdin do pipe com o
# próprio script: todo `read` interativo abaixo lê de /dev/tty
# explicitamente, não do stdin padrão.
set -euo pipefail

API_REPO="Invariant-Security/invariant_api"
ENV_FILE=/etc/invariant/.env
INSTALL_DIR=/opt/invariant
ASSUME_YES="${INVARIANT_ASSUME_YES:-0}"

log_ok()      { printf '  [OK]       %s\n' "$1"; }
log_missing() { printf '  [FALTANDO] %s\n' "$1"; }
log_info()    { printf '%s\n' "$1"; }
log_err()     { printf '%s\n' "$1" >&2; }

# `[ -e /dev/tty ]` não basta -- o nó existe mesmo sem terminal de
# controle (ex. dentro de `docker run` sem `-t`), e só falha ao abrir de
# verdade (ENXIO). Testa abrindo de fato, numa subshell, pra não vazar
# esse erro pro script principal.
tty_available() { ( : < /dev/tty ) 2>/dev/null; }

# Prompt Y/N que funciona mesmo com `curl | bash` (stdin já é o script) --
# lê do terminal de verdade, não do stdin herdado. Sem tty disponível e
# sem ASSUME_YES, aborta em vez de travar esperando input que nunca vem.
confirm() {
    local prompt="$1"
    if [ "$ASSUME_YES" = "1" ]; then
        log_info "$prompt [Y/n] -> assumindo Y (INVARIANT_ASSUME_YES=1)"
        return 0
    fi
    if ! tty_available; then
        log_err "Sem terminal interativo disponível pra confirmar '$prompt'."
        log_err "Rode de novo com INVARIANT_ASSUME_YES=1 se quiser pular a confirmação."
        exit 1
    fi
    local answer
    read -r -p "$prompt [Y/n] " answer < /dev/tty
    case "$answer" in
        ""|[Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

abort_missing_dependency() {
    log_err ""
    log_err "Sem '$1' o Invariant não funciona -- instalação cancelada."
    log_err "Nada foi alterado no sistema além do que já estava confirmado antes."
    exit 1
}

# --- pré-checks de execução ---------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    log_err "Precisa rodar como root: sudo bash install.sh ${1:-<versão>}"
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    log_err "Não foi possível identificar a distribuição (/etc/os-release ausente)."
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    debian|ubuntu) ;;
    *)
        log_err "Distribuição '${ID:-desconhecida}' não suportada -- Invariant appliance"
        log_err "hoje só suporta Debian/Ubuntu (mesma família coberta pelos checks CIS)."
        exit 1
        ;;
esac

# --- resolve versão -------------------------------------------------------

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    log_info "Nenhuma versão informada, resolvendo a tag mais recente de ${API_REPO}..."
    LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/${API_REPO}/tags" | grep -m1 '"name"' | cut -d'"' -f4 || true)"
    if [ -z "$LATEST_TAG" ]; then
        log_err "Não consegui resolver a versão automaticamente."
        log_err "Uso: install.sh <versão, ex. 0.1.5>"
        exit 1
    fi
    VERSION="${LATEST_TAG#v}"
fi
API_REPO_REF="v${VERSION}"
API_RAW_BASE="https://raw.githubusercontent.com/${API_REPO}/${API_REPO_REF}"
log_info "Instalando Invariant appliance ${API_REPO_REF}"
log_info ""

# --- validação de ambiente -------------------------------------------------

log_info "Verificando ambiente:"

NEED_DOCKER=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log_ok "Docker instalado e daemon respondendo"
else
    log_missing "Docker (engine)"
    NEED_DOCKER=1
fi

NEED_COMPOSE=0
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log_ok "Plugin docker compose"
else
    log_missing "Plugin docker compose"
    NEED_COMPOSE=1
fi

NEED_CURL=0
if command -v curl >/dev/null 2>&1; then
    log_ok "curl"
else
    log_missing "curl"
    NEED_CURL=1
fi

NEED_OPENSSL=0
if command -v openssl >/dev/null 2>&1; then
    log_ok "openssl"
else
    log_missing "openssl"
    NEED_OPENSSL=1
fi

WEB_PORT="${INVARIANT_WEB_PORT:-80}"
if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${WEB_PORT} )" | grep -q ":${WEB_PORT}"; then
    log_missing "Porta ${WEB_PORT} livre"
    log_info ""
    log_info "Porta ${WEB_PORT} já está em uso:"
    ss -ltnp "( sport = :${WEB_PORT} )" 2>/dev/null | sed 's/^/  /' || true
    log_info ""
    if [ "$ASSUME_YES" = "1" ] || ! tty_available; then
        log_err "Escolha outra porta com INVARIANT_WEB_PORT=<porta> e rode de novo."
        exit 1
    fi
    read -r -p "Digite outra porta pra usar (ou Enter pra cancelar): " WEB_PORT < /dev/tty
    if [ -z "$WEB_PORT" ]; then
        log_err "Instalação cancelada."
        exit 1
    fi
else
    log_ok "Porta ${WEB_PORT} livre"
fi

log_info ""

# --- confirma instalação de dependências faltando -------------------------

if [ "$NEED_CURL" -eq 1 ] || [ "$NEED_OPENSSL" -eq 1 ]; then
    # curl precisa já existir pra este script ter sido baixado via
    # `curl | bash` -- se chegou aqui sem curl, foi rodado de outro jeito
    # (ex. copiado manualmente); openssl é o único que falta de fato via apt.
    PKGS=""
    [ "$NEED_CURL" -eq 1 ] && PKGS="$PKGS curl"
    [ "$NEED_OPENSSL" -eq 1 ] && PKGS="$PKGS openssl"
    if confirm "Instalar pacotes do sistema (apt-get install$PKGS)?"; then
        apt-get update -qq
        # shellcheck disable=SC2086
        apt-get install -y $PKGS
    else
        abort_missing_dependency "curl/openssl"
    fi
fi

if [ "$NEED_DOCKER" -eq 1 ]; then
    log_info "Docker não encontrado. A instalação oficial roda o script"
    log_info "de conveniência da Docker Inc. (https://get.docker.com),"
    log_info "baixado e executado como root."
    if confirm "Baixar e instalar o Docker agora (curl -fsSL https://get.docker.com | sh)?"; then
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    else
        abort_missing_dependency "Docker"
    fi
fi

if [ "$NEED_COMPOSE" -eq 1 ]; then
    if confirm "Instalar o plugin docker-compose-plugin (apt-get install)?"; then
        apt-get update -qq
        apt-get install -y docker-compose-plugin
    else
        abort_missing_dependency "docker compose"
    fi
fi

# As 5 imagens do appliance são privadas no ghcr.io (protege a lógica
# proprietária dos checks CIS de download público) -- precisa de um token
# de leitura no ambiente de quem instala. Nunca embutido neste script:
# install.sh é público (curl direto do GitHub), qualquer segredo aqui
# vazaria pra qualquer pessoa que o baixasse.
if [ -z "${INVARIANT_PULL_TOKEN:-}" ]; then
    abort_missing_dependency "INVARIANT_PULL_TOKEN no ambiente (token de leitura do ghcr.io -- rode com INVARIANT_PULL_TOKEN=<token> antes do comando)"
fi
echo "$INVARIANT_PULL_TOKEN" | docker login ghcr.io -u invariant-appliance --password-stdin

# --- instalação -------------------------------------------------------------

log_info ""
log_info "Ambiente OK. Instalando em ${INSTALL_DIR}..."

mkdir -p "$INSTALL_DIR"
curl -fsSL "${API_RAW_BASE}/docker-compose.appliance.yml" -o "${INSTALL_DIR}/docker-compose.appliance.yml"
curl -fsSL "${API_RAW_BASE}/nginx.appliance.conf" -o "${INSTALL_DIR}/nginx.appliance.conf"
curl -fsSL "${API_RAW_BASE}/bootstrap-documents.sh" -o "${INSTALL_DIR}/bootstrap-documents.sh"
chmod +x "${INSTALL_DIR}/bootstrap-documents.sh"

mkdir -p /etc/invariant
if [ ! -f "$ENV_FILE" ]; then
    SECRET="$(openssl rand -hex 32)"
    cat > "$ENV_FILE" <<EOF
INVARIANT_API_SECRET_KEY=$SECRET
INVARIANT_WEB_PORT=$WEB_PORT
INVARIANT_VERSION=$API_REPO_REF
EOF
    chmod 600 "$ENV_FILE"
else
    log_info "${ENV_FILE} já existe -- mantendo (reinstalação/atualização, não gera secret novo)."
fi

# Exportado pro shell, não só escrito no .env -- garante que a porta
# validada acima (que pode ter mudado de INVARIANT_WEB_PORT/80 se estava
# ocupada) prevalece mesmo numa reinstalação onde o .env já existe com
# outro valor (env do processo tem precedência sobre --env-file no
# `docker compose`).
export INVARIANT_WEB_PORT="$WEB_PORT"
COMPOSE="docker compose -f ${INSTALL_DIR}/docker-compose.appliance.yml --env-file ${ENV_FILE}"

log_info "Subindo postgres..."
$COMPOSE up -d --wait postgres

log_info "Rodando migrations..."
$COMPOSE run --rm api alembic upgrade head

log_info "Subindo o restante da stack..."
$COMPOSE up -d --wait

log_info "Carregando benchmarks CIS padrão (pode levar 1-2 minutos na primeira vez)..."
INVARIANT_WEB_PORT="$WEB_PORT" "${INSTALL_DIR}/bootstrap-documents.sh" || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
log_info ""
log_info "Invariant está no ar."
log_info "Abra http://${IP:-<ip-desta-maquina>}:${WEB_PORT}/ no navegador pra terminar a configuração."
log_info ""
log_info "Comandos úteis (não há systemd unit neste canal de instalação):"
log_info "  $COMPOSE ps"
log_info "  $COMPOSE logs -f"
log_info "  $COMPOSE down"
log_info ""
log_info "Pra remover, use uninstall.sh (mesma pasta deste script)."
