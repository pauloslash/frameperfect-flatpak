#!/usr/bin/env bash
# Cria o Flatpak do Frame Perfect (https://frameperfect.cc) rodando o cliente
# de Windows dentro do Wine, no mesmo modelo do com.fightcade.Fightcade do
# Flathub (base org.winehq.Wine + Wine Mono/Gecko + 32 bits).
#
# Este script é a fonte de tudo: ele (re)gera o manifesto, o lançador, o
# .desktop, o metainfo e os ícones, baixa o cliente, compila e instala.
# Qualquer mudança no pacote deve ser feita AQUI e não nos arquivos gerados.
#
# Uso:
#   ./criar-flatpak.sh                 mostra um menu com as opções (num terminal)
#   ./criar-flatpak.sh --completo      baixa a versão mais nova, compila, instala (--user) e gera o .flatpak
#   ./criar-flatpak.sh --so-gerar      só gera os arquivos do projeto (sem compilar)
#   ./criar-flatpak.sh --sem-instalar  compila mas não instala
#   ./criar-flatpak.sh --sem-bundle    não gera o arquivo .flatpak
#
# Precisa no sistema: flatpak, curl, unzip, 7z, file, python3 e o remote flathub.
# O resto (org.flatpak.Builder, SDK, base Wine) é instalado pelo script.
set -euo pipefail

APP_ID=cc.frameperfect.FramePerfect
API_URL=https://frameperfect.cc/api/app/version/
WINE_BASE_VERSION=stable-25.08
RUNTIME_VERSION=25.08

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

GERAR_SO=0 INSTALAR=1 BUNDLE=1

# Sem argumentos, num terminal: menu. Fora de um terminal: faz o completo.
if [ $# -eq 0 ] && [ -t 0 ]; then
    cat <<'MENU'

  Frame Perfect - criar Flatpak
  =============================

  1) Completo
     Baixa a versão mais nova do cliente, compila, instala neste PC e gera
     o arquivo .flatpak para instalar em outros PCs.

  2) Compilar e instalar
     Igual ao completo, mas sem gerar o arquivo .flatpak (mais rápido).
     Use para atualizar ou testar mudanças neste PC.

  3) Só gerar o arquivo .flatpak
     Compila e gera o .flatpak sem instalar neste PC. Use para levar o
     app para outro computador.

  4) Só gerar os arquivos do projeto
     Gera manifesto, lançador, .desktop, metainfo, ícones e fontes sem
     compilar. Use para conferir o que muda antes de compilar.

  0) Sair

MENU
    read -rp "  Escolha uma opção [1]: " opcao
    case ${opcao:-1} in
        1) ;;
        2) BUNDLE=0 ;;
        3) INSTALAR=0 ;;
        4) GERAR_SO=1 ;;
        0) exit 0 ;;
        *) echo "opção inválida: $opcao" >&2; exit 1 ;;
    esac
    echo
fi

for arg in "$@"; do
    case $arg in
        --completo) ;;
        --so-gerar) GERAR_SO=1 ;;
        --sem-instalar) INSTALAR=0 ;;
        --sem-bundle) BUNDLE=0 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "opção desconhecida: $arg" >&2; exit 1 ;;
    esac
done

for c in flatpak curl unzip 7z python3 file; do
    command -v "$c" >/dev/null || { echo "falta o comando: $c" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. Descobre a versão atual e baixa o cliente completo (zip portátil Win10/11)
# ---------------------------------------------------------------------------
echo ">> Consultando $API_URL"
read -r VERSAO ZIP_URL < <(curl -fsSL "$API_URL" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["latest_version"], d["full_download_url"])')
echo "   versão $VERSAO"

mkdir -p downloads
ZIP=downloads/FramePerfect-Launcher-$VERSAO.zip
if [ ! -s "$ZIP" ]; then
    echo ">> Baixando $ZIP_URL"
    curl -fL --progress-bar -o "$ZIP.part" "$ZIP_URL"
    mv "$ZIP.part" "$ZIP"
fi
# A URL do zip completo não tem versão; confere se o zip é mesmo desta versão
ZIP_VERSAO=$(unzip -p "$ZIP" "Frame Perfect/versao.txt" | grep -o '[0-9][0-9.]*' | tail -1)
if [ "$ZIP_VERSAO" != "$VERSAO" ]; then
    echo "!! o zip baixado é da versão $ZIP_VERSAO, não $VERSAO; renomeando" >&2
    mv "$ZIP" "downloads/FramePerfect-Launcher-$ZIP_VERSAO.zip"
    VERSAO=$ZIP_VERSAO
    ZIP=downloads/FramePerfect-Launcher-$VERSAO.zip
fi
ZIP_SHA=$(sha256sum "$ZIP" | cut -d' ' -f1)

# ---------------------------------------------------------------------------
# 2. Ícones: extraídos do próprio FramePerfect.exe
# ---------------------------------------------------------------------------
echo ">> Extraindo ícones do FramePerfect.exe"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q -j "$ZIP" "Frame Perfect/FramePerfect.exe" -d "$TMP"
7z x -y -o"$TMP/rsrc" "$TMP/FramePerfect.exe" '.rsrc/ICON/*' >/dev/null
rm -rf icons && mkdir -p icons
for f in "$TMP"/rsrc/.rsrc/ICON/*; do
    file "$f" | grep -q 'PNG image' || continue
    tam=$(file "$f" | sed -n 's/.*PNG image data, \([0-9]*\) x.*/\1/p')
    cp "$f" "icons/$APP_ID-$tam.png"
done
ls icons

# ---------------------------------------------------------------------------
# 2b. Fonte de emoji monocromática (o WPF não desenha a Noto Color Emoji do
#     runtime) e os mapeamentos Segoe UI Symbol/Emoji -> fontes livres
# ---------------------------------------------------------------------------
NOTO_EMOJI=downloads/NotoEmoji.ttf
if [ ! -s "$NOTO_EMOJI" ]; then
    echo ">> Baixando a fonte Noto Emoji (OFL)"
    curl -fL --progress-bar -o "$NOTO_EMOJI.part" \
        'https://github.com/google/fonts/raw/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf'
    mv "$NOTO_EMOJI.part" "$NOTO_EMOJI"
fi
NOTO_EMOJI_SHA=$(sha256sum "$NOTO_EMOJI" | cut -d' ' -f1)

# Barlow Condensed (OFL): o cliente usa "Tw Cen MT Condensed, ./fonts/#Barlow
# Condensed, Segoe UI"; a Barlow embutida no exe tem ligadura fi. Uma cópia
# sem ligadura com o nome "Tw Cen MT Condensed" é encontrada primeiro.
BARLOW_SRCS=""
for peso in Regular SemiBold Bold; do
    f=downloads/BarlowCondensed-$peso.ttf
    if [ ! -s "$f" ]; then
        echo ">> Baixando a fonte Barlow Condensed $peso (OFL)"
        curl -fL --progress-bar -o "$f.part" \
            "https://github.com/google/fonts/raw/main/ofl/barlowcondensed/BarlowCondensed-$peso.ttf"
        mv "$f.part" "$f"
    fi
    BARLOW_SRCS+="      - type: file"$'\n'"        path: $f"$'\n'"        sha256: $(sha256sum "$f" | cut -d' ' -f1)"$'\n'
done

# Ajuste de fontes, usado no build (python3 do SDK)
mkdir -p scripts
cat > scripts/fontes.py <<'EOF'
#!/usr/bin/env python3
# Gerado por criar-flatpak.sh.
# uso: fontes.py <entrada.ttf> <saida.ttf> [--renomear DE PARA] [--revisao] [--notdef-vazio]
#
# Desliga a ligadura 'liga' (fi, fl, ...): no WPF do Wine Mono cada ligadura
# desenha um quadradinho a mais no texto ("confirma.□"). A tag é renomeada
# para 'lig_' no FeatureList do GSUB (mesmo tamanho; '_' < 'a' mantém a ordem).
# --renomear troca o nome de família na tabela 'name' (reescrita no fim).
# --revisao soma 100 ao fontRevision, para o Wine preferir esta cópia a uma
# fonte de mesmo nome que ele já tem (ex.: a Tahoma do próprio Wine).
# --notdef-vazio deixa vazio o glifo .notdef (o "quadrado"): o WPF do Wine
# Mono desenha um .notdef a mais depois de cada emoji ("🏆□ RECORDES").
import struct, sys

args = sys.argv[1:]
renomear = revisao = notdef = None
if '--notdef-vazio' in args:
    args.remove('--notdef-vazio'); notdef = True
if '--revisao' in args:
    args.remove('--revisao'); revisao = True
if '--renomear' in args:
    i = args.index('--renomear'); renomear = (args[i+1], args[i+2]); del args[i:i+3]
src, dst = args
d = bytearray(open(src, 'rb').read())
n = struct.unpack_from('>H', d, 4)[0]
dirent = {bytes(d[12+16*i:16+16*i]): 12+16*i for i in range(n)}
off = lambda tag: struct.unpack_from('>I', d, dirent[tag]+8)[0]

trocas = 0
if b'GSUB' in dirent:
    g = off(b'GSUB')
    fl = g + struct.unpack_from('>H', d, g+6)[0]
    for i in range(struct.unpack_from('>H', d, fl)[0]):
        p = fl + 2 + 6*i
        if d[p:p+4] == b'liga':
            d[p:p+4] = b'lig_'
            trocas += 1

if notdef:
    # glifo 0 vazio: loca[0] = loca[1] (e o mesmo no gvar, se for variável)
    loca = off(b'loca')
    if struct.unpack_from('>h', d, off(b'head')+50)[0]:
        struct.pack_into('>I', d, loca, struct.unpack_from('>I', d, loca+4)[0])
    else:
        struct.pack_into('>H', d, loca, struct.unpack_from('>H', d, loca+2)[0])
    if b'gvar' in dirent:
        g = off(b'gvar')
        if struct.unpack_from('>H', d, g+14)[0] & 1:
            struct.pack_into('>I', d, g+20, struct.unpack_from('>I', d, g+24)[0])
        else:
            struct.pack_into('>H', d, g+20, struct.unpack_from('>H', d, g+22)[0])

if revisao:
    h = off(b'head')
    struct.pack_into('>i', d, h+4, struct.unpack_from('>i', d, h+4)[0] + (100 << 16))

if renomear:
    de, para = renomear
    base = off(b'name')
    cnt, soff = struct.unpack_from('>HH', d, base+2)
    recs, dados = [], b''
    for k in range(cnt):
        pid, eid, lid, nid, ln, o = struct.unpack_from('>6H', d, base+6+12*k)
        enc = 'utf-16-be' if pid in (0, 3) else 'latin-1'
        txt = bytes(d[base+soff+o:base+soff+o+ln]).decode(enc)
        if nid in (1, 3, 4, 16, 18, 21):
            txt = txt.replace(de, para)
        elif nid == 6:
            txt = txt.replace(de.replace(' ', ''), para.replace(' ', ''))
        raw = txt.encode(enc)
        recs.append((pid, eid, lid, nid, len(raw), len(dados)))
        dados += raw
    tab = struct.pack('>HHH', 0, cnt, 6+12*cnt) + b''.join(struct.pack('>6H', *r) for r in recs) + dados
    while len(d) % 4:
        d.append(0)
    struct.pack_into('>II', d, dirent[b'name']+8, len(d), len(tab))
    d += tab

open(dst, 'wb').write(d)
print(f'{src} -> {dst}: {trocas} ligadura(s) desligada(s)')
EOF

cat > fontes.reg <<'EOF'
REGEDIT4

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"DejaVu Sans (TrueType)"="DejaVuSans.ttf"
"Liberation Sans (TrueType)"="LiberationSans-Regular.ttf"
"Liberation Sans Bold (TrueType)"="LiberationSans-Bold.ttf"
"Liberation Sans Italic (TrueType)"="LiberationSans-Italic.ttf"
"Liberation Sans Bold Italic (TrueType)"="LiberationSans-BoldItalic.ttf"
"Liberation Mono (TrueType)"="LiberationMono-Regular.ttf"
"Liberation Mono Bold (TrueType)"="LiberationMono-Bold.ttf"
"Noto Emoji (TrueType)"="NotoEmoji.ttf"
"Tw Cen MT Condensed (TrueType)"="TwCenMTCondensed-Regular.ttf"
"Tw Cen MT Condensed SemiBold (TrueType)"="TwCenMTCondensed-SemiBold.ttf"
"Tw Cen MT Condensed Bold (TrueType)"="TwCenMTCondensed-Bold.ttf"

[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
"Segoe UI"="Liberation Sans"
"Arial"="Liberation Sans"
"Consolas"="Liberation Mono"
"Segoe UI Symbol"="DejaVu Sans"
"Segoe UI Emoji"="Noto Emoji"
EOF

# Aplica o pacote de atualização do cliente (usado pelo lançador)
cat > scripts/atualizar.py <<'EOF'
#!/usr/bin/env python3
# Gerado por criar-flatpak.sh.
# uso: atualizar.py <pacote.zip> <pasta do cliente>
# Extrai o pacote de atualização do Frame Perfect (tudo dentro de uma pasta
# raiz, ex.: Frame-Perfect-Update/) por cima da pasta do cliente. Links (para
# os arquivos em /app, só leitura) são removidos antes de gravar.
import os, shutil, sys, zipfile

pacote, destino = sys.argv[1:3]
destino = os.path.realpath(destino)
with zipfile.ZipFile(pacote) as z:
    for info in z.infolist():
        partes = info.filename.replace('\\', '/').split('/')[1:]
        if not partes or not partes[-1] or '..' in partes:
            continue
        alvo = os.path.join(destino, *partes)
        if not os.path.realpath(os.path.dirname(alvo)).startswith(destino):
            continue
        os.makedirs(os.path.dirname(alvo), exist_ok=True)
        if os.path.islink(alvo):
            os.unlink(alvo)
        with z.open(info) as src, open(alvo + '.fp-novo', 'wb') as dst:
            shutil.copyfileobj(src, dst)
        os.replace(alvo + '.fp-novo', alvo)
print('atualização aplicada em', destino)
EOF

# ---------------------------------------------------------------------------
# 3. Lançador que roda dentro do sandbox
# ---------------------------------------------------------------------------
mkdir -p scripts
cat > scripts/frameperfect.sh <<'EOF'
#!/bin/sh
# Lançador do Frame Perfect no Flatpak (gerado por criar-flatpak.sh).
#
# O cliente é portátil e escreve na própria pasta (config, ROMs, logs e o
# auto-update dele), então ele roda de /var/data/FramePerfect, que é gravável
# (~/.var/app/cc.frameperfect.FramePerfect/data/FramePerfect no host). Os
# arquivos que ele só lê (exe, dll, recursos.dat...) ficam lá como links para
# /app/frameperfect; o resto (configs, savestates, NVRAM) é cópia de verdade.
#
# Subcomandos para depuração:
#   flatpak run cc.frameperfect.FramePerfect winecfg|regedit|winetricks ...|shell

SEMENTE=/app/frameperfect
DATA=/var/data
JOGO=$DATA/FramePerfect
API_VERSAO=${FP_API_VERSAO:-https://frameperfect.cc/api/app/version/}

export WINEPREFIX=$DATA/wineprefix
export WINEARCH=win64
export WINEDEBUG=${WINEDEBUG:--all}
# winemenubuilder criaria atalhos/associações de arquivo inúteis no sandbox
export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

versao() {
    grep -o '[0-9][0-9.]*' "$1/versao.txt" 2>/dev/null | tail -1
}

# Mostra uma barra de progresso enquanto o comando roda
com_progresso() {
    texto=$1; shift
    "$@" >/dev/null 2>&1 &
    pid=$!
    if command -v zenity >/dev/null; then
        while kill -0 $pid 2>/dev/null; do echo "#$texto"; sleep 1; done |
            zenity --progress --pulsate --auto-close --no-cancel \
                --title="Frame Perfect" --text="$texto" 2>/dev/null &
    fi
    echo "$texto"
    wait $pid
}

# --- Prefixo do Wine: cria ou atualiza quando a versão do Wine muda ---
# DISPLAY inválido evita janelas do wineboot; o wineserver -w é obrigatório,
# senão o cliente reaproveita o explorer.exe sem display e não cria janelas
# As marcas ficam dentro do prefixo: apagar o prefixo refaz tudo.
WINE_VERSAO=$(wine --version)
if [ "$(cat "$WINEPREFIX/.fp-wine-versao" 2>/dev/null)" != "$WINE_VERSAO" ]; then
    mkdir -p "$WINEPREFIX"
    com_progresso "Preparando o Wine ($WINE_VERSAO), pode levar um minuto..." \
        sh -c 'DISPLAY=:invalid wineboot -u && wineserver -w'
    echo "$WINE_VERSAO" > "$WINEPREFIX/.fp-wine-versao"
fi

# --- Fontes ---
# O cliente é WPF e pede Segoe UI, Arial e Consolas, e procura os símbolos
# (★ ✓ ⚙ 🔍 🎮 ...) em Segoe UI Symbol e Segoe UI Emoji; o Wine não tem
# nenhuma delas e aparecem quadrados. O WPF só enxerga fontes que estão no
# C:\windows\Fonts do prefixo, então elas são copiadas para lá e mapeadas em
# fontes.reg. No WPF do Wine Mono cada ligadura (fi, fl) e cada emoji desenha
# um quadradinho a mais no texto ("confirma.□", "fila, □"), por isso:
# - texto em Liberation Sans, que não tem ligaduras;
# - a Noto Emoji vem com o glifo .notdef vazio (o quadrado depois do emoji);
# - a Tahoma do Wine e a Barlow ("Tw Cen MT Condensed") vêm do build sem a
#   ligadura (scripts/fontes.py), em /app/share/frameperfect/fontes.
FONTES_VERSAO="4 $WINE_VERSAO"
if [ "$(cat "$WINEPREFIX/.fp-fontes" 2>/dev/null)" != "$FONTES_VERSAO" ]; then
    echo "Instalando as fontes no prefixo"
    FONTES_WIN=$WINEPREFIX/drive_c/windows/Fonts
    mkdir -p "$FONTES_WIN"
    for f in 'DejaVu Sans:style=Book' \
             'Liberation Sans:style=Regular' 'Liberation Sans:style=Bold' \
             'Liberation Sans:style=Italic' 'Liberation Sans:style=Bold Italic' \
             'Liberation Mono:style=Regular' 'Liberation Mono:style=Bold'; do
        cp -f "$(fc-match -f '%{file}' "$f")" "$FONTES_WIN/"
    done
    cp -f /app/share/frameperfect/fontes/*.ttf "$FONTES_WIN/"
    wine regedit /app/share/frameperfect/fontes.reg && wineserver -w &&
        echo "$FONTES_VERSAO" > "$WINEPREFIX/.fp-fontes"
fi

# --- DXVK opcional (Flatseal: USE_DXVK=true) ---
if [ "${USE_DXVK:-false}" = true ] && [ ! -f "$WINEPREFIX/.fp-dxvk" ]; then
    com_progresso "Instalando o DXVK..." winetricks -q dxvk && touch "$WINEPREFIX/.fp-dxvk"
elif [ "${USE_DXVK:-false}" != true ] && [ -f "$WINEPREFIX/.fp-dxvk" ]; then
    # Sem os overrides "native" o Wine volta a usar o próprio Direct3D (wined3d)
    for dll in d3d8 d3d9 d3d10core d3d11 dxgi; do
        wine reg delete 'HKCU\Software\Wine\DllOverrides' /v $dll /f >/dev/null 2>&1
    done
    rm -f "$WINEPREFIX/.fp-dxvk"
fi

# --- Cliente ---
# Arquivos que o cliente só lê viram links para a semente em /app (não ocupam
# espaço de novo e acompanham as atualizações do Flatpak). Por causa dos links
# o updater.exe do cliente não funciona (ele grava por cima do arquivo, e o
# link aponta para /app, que é só leitura); as atualizações do cliente são
# aplicadas por este lançador, antes de abrir o cliente.
imutaveis() {
    (cd "$SEMENTE" && find . -type f \( -iname '*.exe' -o -iname '*.dll' \
        -o -iname '*.dylib' -o -iname '*.so' -o -iname '*.exe.config' \
        -o -name recursos.dat -o -name README.md -o -path './licencas/*' \))
}
# ligar forcar:   link para todos os imutáveis (semente mais nova)
# ligar iguais:   troca por link os arquivos idênticos aos da semente
# ligar faltando: só recria os links que foram apagados
ligar() {
    imutaveis | while IFS= read -r f; do
        f=${f#./}
        alvo=$JOGO/$f
        [ "$(readlink "$alvo")" = "$SEMENTE/$f" ] && continue
        if [ ! -e "$alvo" ] || [ "$1" = forcar ] ||
           { [ "$1" = iguais ] && cmp -s "$SEMENTE/$f" "$alvo"; }; then
            mkdir -p "$(dirname "$alvo")"
            ln -sfn "$SEMENTE/$f" "$alvo"
        fi
    done
}
mais_nova() {  # mais_nova A B: verdadeiro se a versão A for maior que a B
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# Instala na primeira vez (ou se a pasta foi apagada) e atualiza se o Flatpak
# trouxer versão mais nova que a instalada. A config do launcher (login) e os
# arquivos do usuário (ROMs, configs, logs) não são tocados.
V_SEMENTE=$(versao "$SEMENTE")
V_JOGO=$(versao "$JOGO")
if [ ! -f "$JOGO/FramePerfect.exe" ] || mais_nova "$V_SEMENTE" "$V_JOGO"; then
    echo "Instalando o Frame Perfect $V_SEMENTE em $JOGO (havia: ${V_JOGO:-nada})"
    mkdir -p "$JOGO"
    imutaveis > "$DATA/.fp-imutaveis"
    (cd "$SEMENTE" && tar cf - -X "$DATA/.fp-imutaveis" --exclude=./rbf-launcher.json .) |
        (cd "$JOGO" && tar xf - --no-same-owner)
    rm -f "$DATA/.fp-imutaveis"
    chmod -R u+w "$JOGO"
    ligar forcar
    V_JOGO=$V_SEMENTE
fi

# Atualização do cliente pela mesma API que ele usa (desligue com
# FP_ATUALIZAR=false). O pacote é conferido pelo SHA-256 antes de extrair.
if [ "${FP_ATUALIZAR:-true}" = true ]; then
    INFO=$(curl -fsS --max-time 8 "$API_VERSAO" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["latest_version"], d["download_url"], d["sha256"].lower())' 2>/dev/null)
    NOVA=${INFO%% *}
    if [ -n "$INFO" ] && mais_nova "$NOVA" "$V_JOGO"; then
        PACOTE=$DATA/.fp-atualizacao.zip
        URL=$(echo "$INFO" | cut -d' ' -f2)
        SHA=$(echo "$INFO" | cut -d' ' -f3)
        if com_progresso "Baixando a atualização do Frame Perfect ($V_JOGO -> $NOVA)..." \
               curl -fsSL -o "$PACOTE" "$URL" &&
           echo "$SHA  $PACOTE" | sha256sum -c --status; then
            echo "Atualizando o Frame Perfect para $NOVA"
            # rm .fp-links: o que não mudou entre as versões volta a ser link
            python3 /app/share/frameperfect/atualizar.py "$PACOTE" "$JOGO" &&
                V_JOGO=$(versao "$JOGO") && rm -f "$JOGO/.fp-links"
        else
            echo "Falha ao baixar/conferir a atualização $NOVA; seguindo com $V_JOGO" >&2
        fi
        rm -f "$PACOTE"
    fi
fi

# Recria o que tiver sido apagado em $JOGO (sem sobrescrever nada). Só quando
# a versão instalada é a da semente, para não misturar versões.
if [ "$V_JOGO" = "$V_SEMENTE" ]; then
    ligar faltando
    cp -r --update=none "$SEMENTE/." "$JOGO/"
fi
[ -f "$JOGO/rbf-launcher.json" ] || cp "$SEMENTE/rbf-launcher.json" "$JOGO/"
chmod u+w "$JOGO/rbf-launcher.json"
# Quando a versão instalada muda, troca por links os arquivos que forem iguais
# aos da semente (ex.: depois de rebuild do Flatpak com a versão nova)
if [ "$(cat "$JOGO/.fp-links" 2>/dev/null)" != "$V_JOGO" ]; then
    ligar iguais
    echo "$V_JOGO" > "$JOGO/.fp-links"
fi

case $1 in
    winecfg|regedit|taskmgr|explorer) exec wine "$@" ;;
    winetricks) shift; exec winetricks "$@" ;;
    shell) exec /bin/sh ;;
esac

cd "$JOGO" || exit 1
wine "$JOGO/FramePerfect.exe" "$@"
# O auto-update fecha o launcher e reabre pelo updater.exe; espera todos os
# processos do Wine terminarem para o sandbox não ser encerrado no meio
wineserver -w
EOF
chmod +x scripts/frameperfect.sh

# ---------------------------------------------------------------------------
# 4. .desktop e metainfo
# ---------------------------------------------------------------------------
cat > $APP_ID.desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Frame Perfect
Comment=Jogos de luta clássicos online com rollback netcode
Keywords=retrogaming;arcade;fightcade;rollback;netplay;fliperama;
Exec=frameperfect %u
Icon=$APP_ID
Terminal=false
Categories=Game;Emulator;ArcadeGame;
# Links frameperfect://replay?... do site abrem o cliente (ele trata o link
# recebido como argumento, igual ao "FramePerfect.exe" "%1" do Windows)
MimeType=x-scheme-handler/frameperfect;
StartupWMClass=frameperfect.exe
EOF

cat > $APP_ID.metainfo.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP_ID</id>
  <name>Frame Perfect</name>
  <summary>Jogos de luta clássicos online com rollback netcode</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>LicenseRef-proprietary</project_license>
  <developer id="cc.frameperfect">
    <name>CyborgRJ</name>
  </developer>
  <description>
    <p>
      Frame Perfect é uma plataforma para jogar clássicos de arcade e PS1 online
      com rollback netcode. Este pacote roda o cliente de Windows através do Wine.
    </p>
  </description>
  <launchable type="desktop-id">$APP_ID.desktop</launchable>
  <url type="homepage">https://frameperfect.cc/</url>
  <content_rating type="oars-1.1">
    <content_attribute id="violence-cartoon">moderate</content_attribute>
    <content_attribute id="social-chat">intense</content_attribute>
  </content_rating>
  <releases>
    <release version="$VERSAO" date="$(date +%F)"/>
  </releases>
</component>
EOF

# ---------------------------------------------------------------------------
# 5. Manifesto
# ---------------------------------------------------------------------------
ICONES_CMDS=""
ICONES_SRCS=""
for f in icons/*.png; do
    tam=${f##*-}; tam=${tam%.png}
    ICONES_CMDS+="      - install -Dm644 $(basename "$f") /app/share/icons/hicolor/${tam}x${tam}/apps/$APP_ID.png"$'\n'
    ICONES_SRCS+="      - type: file"$'\n'"        path: $f"$'\n'
done

cat > $APP_ID.yml <<EOF
# Gerado por criar-flatpak.sh: não edite à mão.
app-id: $APP_ID
base: org.winehq.Wine
base-version: $WINE_BASE_VERSION
runtime: org.freedesktop.Platform
runtime-version: '$RUNTIME_VERSION'
sdk: org.freedesktop.Sdk
command: frameperfect
tags:
  - proprietary

# 32 bits + Wine Mono (o cliente é .NET/WPF) + Wine Gecko
inherit-extensions:
  - org.freedesktop.Platform.Compat.i386
  - org.freedesktop.Platform.GL32
  - org.winehq.Wine.gecko
  - org.winehq.Wine.mono

finish-args:
  - --share=ipc
  - --socket=x11
  - --share=network
  - --socket=pulseaudio
  - --allow=multiarch
  # Controles (USB/arcade sticks)
  - --device=all
  - --talk-name=org.freedesktop.ScreenSaver
  - --talk-name=org.freedesktop.Notifications
  - --env=LD_LIBRARY_PATH=/app/lib:/app/lib32
  # DXVK (desligado por padrão; ative com Flatseal ou flatpak override)
  - --env=USE_DXVK=false

modules:
  - name: frameperfect
    buildsystem: simple
    build-commands:
      - mkdir -p /app/frameperfect
      - cp -a cliente/. /app/frameperfect/
      - install -Dm755 frameperfect.sh /app/bin/frameperfect
      - install -Dm644 atualizar.py /app/share/frameperfect/atualizar.py
      - mkdir -p /app/share/frameperfect/fontes
      - python3 fontes.py NotoEmoji.ttf /app/share/frameperfect/fontes/NotoEmoji.ttf --notdef-vazio
      # Fontes sem ligadura (ver scripts/fontes.py); a Tahoma vem da base Wine
      - python3 fontes.py /app/share/wine/fonts/tahoma.ttf /app/share/frameperfect/fontes/tahoma.ttf --revisao
      - python3 fontes.py /app/share/wine/fonts/tahomabd.ttf /app/share/frameperfect/fontes/tahomabd.ttf --revisao
      - for p in Regular SemiBold Bold; do python3 fontes.py BarlowCondensed-\$p.ttf /app/share/frameperfect/fontes/TwCenMTCondensed-\$p.ttf --renomear "Barlow Condensed" "Tw Cen MT Condensed"; done
      - install -Dm644 fontes.reg /app/share/frameperfect/fontes.reg
      - install -Dm644 $APP_ID.desktop /app/share/applications/$APP_ID.desktop
      - install -Dm644 $APP_ID.metainfo.xml /app/share/metainfo/$APP_ID.metainfo.xml
${ICONES_CMDS}    sources:
      - type: archive
        path: $ZIP
        sha256: $ZIP_SHA
        dest: cliente
      - type: file
        path: scripts/frameperfect.sh
      - type: file
        path: $NOTO_EMOJI
        sha256: $NOTO_EMOJI_SHA
      - type: file
        path: fontes.reg
      - type: file
        path: scripts/fontes.py
      - type: file
        path: scripts/atualizar.py
${BARLOW_SRCS}      - type: file
        path: $APP_ID.desktop
      - type: file
        path: $APP_ID.metainfo.xml
${ICONES_SRCS}
EOF

echo ">> Arquivos gerados para a versão $VERSAO"
[ $GERAR_SO = 1 ] && exit 0

# ---------------------------------------------------------------------------
# 6. Compila (org.flatpak.Builder), instala e gera o bundle
# ---------------------------------------------------------------------------
echo ">> Instalando dependências de build (se faltarem)"
flatpak install -y --noninteractive --user flathub \
    org.flatpak.Builder \
    org.freedesktop.Sdk//$RUNTIME_VERSION \
    org.freedesktop.Platform//$RUNTIME_VERSION \
    org.freedesktop.Platform.Compat.i386//$RUNTIME_VERSION \
    org.freedesktop.Platform.GL32.default//$RUNTIME_VERSION \
    org.winehq.Wine//$WINE_BASE_VERSION

# Sem --install: instalando de dentro do sandbox do Builder, o .desktop
# exportado ganha Exec=/app/bin/flatpak (caminho do Builder) e some do menu
BUILDER_ARGS=(--force-clean --user --repo=repo --disable-rofiles-fuse)

echo ">> Compilando"
# O Builder repassa o XDG_DATA_HOME do sandbox dele para o "flatpak" do host,
# que aí procura a instalação --user (SDK, base Wine) em
# ~/.var/app/org.flatpak.Builder/data/flatpak. Esse caminho precisa ser um
# diretório (o bwrap monta a instalação real em cima dele dentro do sandbox),
# então ele recebe symlinks para cada entrada da instalação real.
USER_FLATPAK=${XDG_DATA_HOME:-$HOME/.local/share}/flatpak
BUILDER_FLATPAK=$HOME/.var/app/org.flatpak.Builder/data/flatpak
[ -L "$BUILDER_FLATPAK" ] && rm "$BUILDER_FLATPAK"
mkdir -p "$BUILDER_FLATPAK"
for item in "$USER_FLATPAK"/* "$USER_FLATPAK"/.changed; do
    [ -e "$item" ] || continue
    dest=$BUILDER_FLATPAK/$(basename "$item")
    [ -L "$dest" ] && continue
    rm -rf "$dest"
    ln -s "$item" "$dest"
done
# --filesystem: o sandbox do Builder não enxerga pastas fora da home (ex.: /tmp)
flatpak run --filesystem="$DIR" --cwd="$DIR" --command=flatpak-builder org.flatpak.Builder \
    "${BUILDER_ARGS[@]}" build-dir $APP_ID.yml

if [ $INSTALAR = 1 ]; then
    echo ">> Instalando (--user) a partir do repo local"
    flatpak --user remote-add --if-not-exists --no-gpg-verify frameperfect-local "$DIR/repo"
    flatpak --user install -y --noninteractive --reinstall frameperfect-local $APP_ID
fi

if [ $BUNDLE = 1 ]; then
    echo ">> Gerando FramePerfect-$VERSAO.flatpak"
    flatpak build-bundle repo "FramePerfect-$VERSAO.flatpak" $APP_ID \
        --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
fi

echo
echo "Pronto: Frame Perfect $VERSAO"
[ $INSTALAR = 1 ] && echo "  rodar:   flatpak run $APP_ID"
[ $BUNDLE = 1 ] && echo "  bundle:  $DIR/FramePerfect-$VERSAO.flatpak (flatpak install --user FramePerfect-$VERSAO.flatpak)"
exit 0
