# Frame Perfect em Flatpak

Empacota o cliente de Windows do [Frame Perfect](https://frameperfect.cc/) para
Linux, rodando no Wine, no mesmo modelo do
[com.fightcade.Fightcade](https://github.com/flathub/com.fightcade.Fightcade):
base `org.winehq.Wine` (stable-25.08), Wine Mono/Gecko e 32 bits herdados como
extensões.

**Tudo é gerado por `criar-flatpak.sh`.** Só o script basta: numa pasta vazia
ele baixa o cliente e a fonte, gera o manifesto, o lançador, o .desktop, o
metainfo, os ícones e o `fontes.reg`, e compila. Para mudar o pacote, mude o
script e rode-o de novo; os arquivos gerados são sobrescritos.

Precisa no sistema: `flatpak` (com o remote flathub), `curl`, `unzip`, `7z`,
`file` e `python3`, além de internet.

```sh
./criar-flatpak.sh                 # menu com as opções abaixo, explicadas
./criar-flatpak.sh --completo      # versão mais nova: compila, instala (--user) e gera o .flatpak
./criar-flatpak.sh --so-gerar      # só gera os arquivos
./criar-flatpak.sh --sem-instalar  # compila sem instalar
./criar-flatpak.sh --sem-bundle    # não gera o .flatpak
./instalar-flatpak.sh              # instala o FramePerfect-<versão>.flatpak mais novo da pasta
flatpak run cc.frameperfect.FramePerfect
```

Para instalar em outro PC, copie o `FramePerfect-<versão>.flatpak` junto com o
`instalar-flatpak.sh` e rode o script lá (precisa só do `flatpak`; o Flathub é
adicionado se faltar). Os dados do app em `~/.var/app/...` não são tocados.

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
  pasta inteira sumir, ela é reinstalada (sem login, sem ROMs).
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
  `FONTES_VERSAO` no lançador.
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
