# invariant_packaging

Dois canais de instalação do Invariant appliance, lado a lado -- nenhum
builda nenhuma imagem Docker, isso é `publish-image.yml` em cada repo
`invariant_*`, que precisa já ter rodado pra tag correspondente antes de
qualquer um dos dois fazer sentido:

- **`.deb`** (`apt install ./invariant_X.Y.Z_amd64.deb`): instala um
  systemd unit, sobrevive a reboot via `systemctl enable`.
- **`install.sh`**: um script que baixa e roda direto
  (`curl -fsSL <url> | sudo bash -s -- <versão>`), sem apt/dpkg nem
  repositório assinado -- valida o ambiente do cliente na tela (Docker,
  plugin compose, porta livre), pergunta Y/N antes de instalar qualquer
  coisa que falte, e encerra com uma mensagem clara se o cliente recusar.
  Sobrevive a reboot só via `restart: unless-stopped` no compose (sem
  unit de systemd nesse canal).

Os dois buscam `docker-compose.appliance.yml`/`nginx.appliance.conf` já
publicados na tag `v<versão>` do `invariant_api`.

## `install.sh` / `uninstall.sh`

```bash
curl -fsSL https://raw.githubusercontent.com/Invariant-Security/invariant_packaging/main/install.sh | sudo bash -s -- 0.1.5
```

Sem argumento de versão, resolve a tag mais recente de `invariant_api`
via API pública do GitHub. `INVARIANT_ASSUME_YES=1` pula os prompts
(automação); `INVARIANT_WEB_PORT=<porta>` muda a porta padrão (`80`).

Pra remover: `uninstall.sh` (mesma pasta) para o stack mantendo config e
dados; `uninstall.sh --purge` também apaga `/etc/invariant`,
`/opt/invariant` e os volumes Docker nomeados -- pede confirmação
interativa (ou `INVARIANT_ASSUME_PURGE=1`).

## O que o `.deb` instala

- `/opt/invariant/docker-compose.appliance.yml` + `nginx.appliance.conf`
- `/etc/systemd/system/invariant.service`
- `/etc/invariant/.env` (gerado pelo `postinst`, só na primeira instalação
  -- `INVARIANT_API_SECRET_KEY` aleatório + `INVARIANT_WEB_PORT=80`)

`postinst` habilita e sobe o serviço; `invariant.service` sobe o Postgres,
espera ele ficar saudável, roda `alembic upgrade head` (a imagem `api` não
faz isso sozinha no boot -- ver o comentário no unit file) e só então sobe
o resto do stack. `prerm`/`postrm` seguem a distinção padrão do Debian
entre `remove` (mantém `/etc/invariant` e os volumes) e `purge` (apaga
tudo).

## Pré-requisito não resolvido pelo `.deb`

Docker precisa já estar instalado (`docker-ce` ou `docker.io` +
`docker-compose-plugin`) -- o `.deb` declara a dependência, mas não
adiciona o repositório apt da Docker sozinho (isso exigiria confiança
implícita numa fonte de pacote de terceiros só pelo `apt install`, o que
não é razoável fazer sem consentimento explícito). `postinst` falha com
uma mensagem clara se `docker` não estiver no `$PATH`, em vez de deixar o
systemd falhar de um jeito obscuro.

`install.sh` resolve isso de outro jeito: como já é interativo por
natureza, ele *pergunta* antes de baixar e rodar o script oficial
`https://get.docker.com` -- mesma fonte de terceiro, mas com
consentimento explícito na hora, em vez de instalar calado.

## Build local

```bash
gem install --no-document fpm
./build.sh 0.2.0   # precisa existir a tag v0.2.0 em invariant_api
```

## `.exe` (Windows) -- não existe ainda

Windows não tem daemon Docker nativo -- um instalador `.exe` precisaria
detectar/exigir Docker Desktop + WSL2 como pré-requisito (uma dependência
de vários GB fora do controle do Invariant, com termos de licença próprios
pra empresas maiores) antes de conseguir rodar o mesmo `docker compose up
-d`. Fricção real, documentada aqui de propósito -- não implementada.
