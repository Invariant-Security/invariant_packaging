# invariant_packaging

Empacota o Invariant appliance como um `.deb` instalável (`apt install
./invariant_X.Y.Z_amd64.deb`). Não builda nenhuma imagem Docker -- isso é
`publish-image.yml` em cada repo `invariant_*`, que precisa já ter rodado
pra tag correspondente antes deste build fazer sentido. Este repo só
empacota o systemd unit + scripts de instalação + o
`docker-compose.appliance.yml`/`nginx.appliance.conf` já publicados na tag
`v<versão>` do `invariant_api`.

## O que o pacote instala

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

## Pré-requisito não resolvido pelo pacote

Docker precisa já estar instalado (`docker-ce` ou `docker.io` +
`docker-compose-plugin`) -- o `.deb` declara a dependência, mas não
adiciona o repositório apt da Docker sozinho (isso exigiria confiança
implícita numa fonte de pacote de terceiros só pelo `apt install`, o que
não é razoável fazer sem consentimento explícito). `postinst` falha com
uma mensagem clara se `docker` não estiver no `$PATH`, em vez de deixar o
systemd falhar de um jeito obscuro.

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
