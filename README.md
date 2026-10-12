# Frame Perfect em Flatpak

Empacota o cliente de Windows do [Frame Perfect](https://frameperfect.cc/) para
Linux, rodando no Wine, no mesmo modelo do
[com.fightcade.Fightcade](https://github.com/flathub/com.fightcade.Fightcade):
base `org.winehq.Wine` (stable-25.08), Wine Mono/Gecko e 32 bits herdados como
extensões.

## Baixar o .flatpak pronto

**Download:** [FramePerfect.flatpak](https://github.com/pauloslash/frameperfect-flatpak/releases/latest/download/FramePerfect.flatpak)
(versão pública: não contém o cliente; ele é baixado do site oficial na
primeira abertura, sempre na versão mais recente, por isso o arquivo não tem
versão no nome)

```sh
flatpak install --user FramePerfect.flatpak
flatpak run cc.frameperfect.FramePerfect
```

O link aponta sempre para o release mais recente.

## Gerar na sua máquina

**Tudo é gerado por `criar-flatpak.sh`.** Só o script basta: numa pasta vazia
ele baixa o cliente e a fonte, gera o manifesto, o lançador, o .desktop, o
metainfo, os ícones e o `fontes.reg`, e compila. Para mudar o pacote, mude o
script e rode-o de novo; os arquivos gerados são sobrescritos.

Precisa no sistema: `flatpak` (com o remote flathub), `curl`, `unzip`, `7z`,
`file` e `python3`, além de internet (para `--publicar`, também `git` e o `gh`
logado).

```sh
./criar-flatpak.sh                 # menu com as opções abaixo, explicadas
./criar-flatpak.sh --completo      # versão mais nova: compila, instala (--user) e gera o .flatpak
./criar-flatpak.sh --so-gerar      # só gera os arquivos
./criar-flatpak.sh --sem-instalar  # compila sem instalar
./criar-flatpak.sh --sem-bundle    # não gera o .flatpak
./criar-flatpak.sh --publico       # .flatpak sem o cliente (FramePerfect.flatpak); não instala
./criar-flatpak.sh --publicar      # completo + publica os releases no GitHub (opções 5 e 6 do menu)
./criar-flatpak.sh --instalar      # só instala o FramePerfect-<versão>-full.flatpak mais novo da pasta (opção 7)
flatpak run cc.frameperfect.FramePerfect
```

Para instalar em outro PC, copie o `FramePerfect-<versão>-full.flatpak` junto com o
`criar-flatpak.sh` e rode `./criar-flatpak.sh --instalar` lá (precisa só do
`flatpak`; o Flathub é adicionado se faltar). Os dados do app em
`~/.var/app/...` não são tocados. O script fecha o Frame Perfect antes de
instalar, se estiver aberto.

### Versão pública

O `.flatpak` normal (`FramePerfect-<versão>-full.flatpak`) contém o cliente,
que é proprietário, por isso só é publicado em rascunho privado. Com `--publico` o pacote sai sem o cliente
(~80 MB em vez de ~220 MB) e pode ser distribuído: na primeira abertura o
lançador baixa o zip completo do site oficial (`full_download_url` da API,
conferido pelo tamanho e pelo CRC de cada arquivo) para
`~/.var/app/cc.frameperfect.FramePerfect/data/cliente`, que faz o papel do
`/app/frameperfect`, e as atualizações são aplicadas nele e na pasta do
cliente. Sem internet na primeira abertura, o app avisa e fecha. Ele vai para
outro repo local (`repo-publico/`) e não é instalado neste PC (trocaria a
instalação atual); teste com `./criar-flatpak.sh --instalar FramePerfect.flatpak`.

Não usa `extra-data` (download na instalação, o mecanismo do Flathub) porque
ele exige URL e SHA-256 fixos, e o site só mantém a versão atual: o zip
completo não tem versão na URL e o pacote versionado antigo some. O
`.flatpak` pararia de instalar a cada versão nova do cliente.

### Publicar no GitHub

`--publicar` (opções 5 e 6 do menu) faz o completo e publica em dois
releases, que ficam juntos (um não apaga o outro):

- `flatpak`: release do código (o "latest", título "Frame Perfect Flatpak",
  sem a versão do cliente), apontando para o commit atual,
  com o `.flatpak` público anexado. A opção 6 sempre o substitui; a opção 5 só
  o cria (sem o anexo) se não existir nenhum;
- `flatpak-full-<versão>`: rascunho privado com o `-full` (opção 5; só quem
  tem acesso de escrita vê).

Os releases antigos do mesmo tipo (de qualquer versão) são apagados, com as
tags. O envio do `.flatpak` tem limite de 7 minutos por tentativa e até 3
tentativas. Exige tudo commitado e o commit atual no GitHub (push), e confere isso antes
de baixar ou compilar.

## Como funciona

- O script consulta `https://frameperfect.cc/api/app/version/`, baixa o zip
  portátil completo (`FramePerfect-Launcher.zip`, cliente Windows 10/11) para
  `downloads/` e extrai os ícones do `FramePerfect.exe`.
- Pastas: `/app/frameperfect` (só leitura) tem o cliente original e serve de
  semente. O cliente roda de `~/.var/app/cc.frameperfect.FramePerfect/data/FramePerfect`
  porque grava na própria pasta. Lá, os arquivos que ele só lê (exe, dll,
  `recursos.dat`, licenças: ~194 MB) são links para o `/app`; configs,
  savestates e NVRAM do emulador (~79 MB) são cópias reais; login
  (`rbf-launcher.json`), ROMs, replays e logs existem só lá.
- Recuperação: a cada abertura o lançador recria o que tiver sido apagado em
  `.../data/FramePerfect` a partir do `/app` (sem sobrescrever nada); se a
  pasta inteira sumir, ela é reinstalada (sem login, sem ROMs). Quando o
  Flatpak traz uma versão mais nova, os arquivos são copiados de novo, mas o
  login e as configs dos emuladores (`emuladores/*/config`) não são
  sobrescritos: só os arquivos que faltam são copiados.
- Atualizações do cliente: o `updater.exe` dele não funciona com os links
  (grava por cima do arquivo, e o link aponta para o `/app`). O lançador
  consulta a API antes de abrir o cliente e, se houver versão nova, baixa o
  pacote oficial, confere o SHA-256 e aplica (`atualizar.py`); o que não
  mudou volta a ser link. `FP_ATUALIZAR=false` desliga;
  `FP_API_VERSAO=<url>` troca a API (para testes). Uma atualização lançada
  com o app aberto falha no updater dele e é aplicada na próxima abertura.
- Atalhos em `~/.var/app/cc.frameperfect.FramePerfect` (recriados a cada
  abertura): `data/roms` → `data/FramePerfect/roms`;
  `config/favoritos.json` → `data/FramePerfect/favoritos.json`;
  `config/emulator/arcade/{games,presets,ips,localisation}` → configs do
  emulador de arcade;
  `config/emulator/ps1/{settings.ini,gamesettings,inputprofiles}` → configs do
  DuckStation (ficam quebrados até o cliente baixar o emulador de PS1).
- Links `frameperfect://replay?...` do site: o .desktop registra
  `x-scheme-handler/frameperfect` e passa o link ao cliente (`%u`), que o
  trata como no Windows. Funciona com o app fechado ou aberto.
- O prefixo do Wine fica em `.../data/wineprefix` e é atualizado (`wineboot -u`)
  quando a versão do Wine muda.
- Fontes (quadrados nos textos): o cliente é WPF e, no Wine Mono, falham duas
  coisas. (1) Faltam as fontes que ele pede: Segoe UI, Arial, Consolas e, para
  símbolos/emoji, Segoe UI Symbol/Emoji. O lançador copia fontes livres para o
  `C:\windows\Fonts` do prefixo (o WPF só enxerga as de lá) e o `fontes.reg`
  mapeia: Segoe UI/Arial → Liberation Sans, Consolas → Liberation Mono,
  Segoe UI Symbol → DejaVu Sans, Segoe UI Emoji → Noto Emoji (monocromática;
  a Noto Color Emoji não renderiza). (2) Toda ligadura (fi, fl) desenha um
  quadradinho a mais ("confirma.□", "fila, □"). Por isso o build gera, com
  `scripts/fontes.py`, cópias sem a feature `liga`: a Tahoma do Wine (com
  revisão +100, para o Wine preferi-la à original) e a Barlow Condensed com o
  nome "Tw Cen MT Condensed", primeira da lista
  `"Tw Cen MT Condensed, ./fonts/#Barlow Condensed, Segoe UI"` do cliente (a
  Barlow embutida no exe tem ligadura). O executável do cliente não é
  alterado. Resta um quadradinho extra por emoji (ex.: busca "🔍"), limitação
  do Wine Mono. Para reaplicar as fontes num prefixo existente, mude
  `FONTES_VERSAO` no lançador. Para U+27C0-2BFF (ex.: o ⭕ de "🅱️ / ⭕ / Esc
  voltar") o WPF tenta Segoe UI Symbol e depois Cambria Math, por isso
  Cambria Math → Noto Emoji.
- Verificação de fontes: a cada build, `scripts/verificar-fontes.py` lê os
  textos do `FramePerfect.exe` (strings do código e do XAML) e, para cada
  símbolo, refaz a escolha de fonte do WPF: a Segoe UI e depois o mapa de
  fallback "Global User Interface" do `PresentationCore.dll` do Wine Mono
  (faixa Unicode → famílias), com as trocas do `fontes.reg` e só as fontes que
  o lançador põe no prefixo. Ela só avisa (`!! sem fonte para ...`, com as
  famílias tentadas); a correção (outra fonte ou outro mapeamento) é à mão.
  Atualizações do cliente aplicadas pelo lançador não passam por ela; a
  próxima compilação, que baixa a versão nova, confere.
- DXVK: desligado; ative com `flatpak override --user --env=USE_DXVK=true cc.frameperfect.FramePerfect`.
- Depuração: `flatpak run cc.frameperfect.FramePerfect winecfg|regedit|winetricks ...|shell`;
  logs do cliente em `.../data/FramePerfect/rbf-launcher.log`.

## Detalhes do build

- Usa o `org.flatpak.Builder` (Flatpak). Ele procura a instalação `--user` em
  `~/.var/app/org.flatpak.Builder/data/flatpak`, então o script cria ali
  symlinks para `~/.local/share/flatpak`.
- `--disable-rofiles-fuse` é necessário neste sistema.
- O Builder só compila; a instalação é feita pelo `flatpak` do host a partir
  do remote local `frameperfect-local` (o `repo/`). Instalando de dentro do
  Builder (`--install`), o .desktop exportado ficava com
  `Exec=/app/bin/flatpak ...` e o app não aparecia no menu.
- O Builder recebe `--filesystem=<pasta do script>`, senão não enxerga pastas
  fora da home (ex.: `/tmp`).
- O cliente de Windows 7 (`FramePerfect-Setup-*-Windows7.exe`) não foi
  necessário: o de Windows 10/11 roda no Wine 11 com o Wine Mono.
- O aviso "não consegui criar/atualizar o atalho" no `rbf-launcher.log` é
  esperado (o Wine Mono não implementa o COM do atalho .lnk).
