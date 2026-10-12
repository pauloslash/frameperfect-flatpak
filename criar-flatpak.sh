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
#   ./criar-flatpak.sh --publico       .flatpak sem o cliente (baixado do site na
#                                      1ª abertura); pode ser distribuído. Não instala.
#   ./criar-flatpak.sh --publicar      completo e publica no GitHub o -full em rascunho
#                                      privado; com --publico, o release do código
#                                      (v<versão>) com o .flatpak público anexado. Um não
#                                      apaga o outro.
#   ./criar-flatpak.sh --instalar [arquivo]
#                                      só instala um .flatpak já gerado (padrão: o
#                                      FramePerfect-<versão>-full.flatpak mais novo da
#                                      pasta; o público só se não houver o -full)
#
# Precisa no sistema: flatpak, curl, unzip, 7z, file, python3 e o remote flathub
# (para --publicar também git e gh logado; para --instalar, só o flatpak).
# O resto (org.flatpak.Builder, SDK, base Wine) é instalado pelo script.
set -euo pipefail

APP_ID=cc.frameperfect.FramePerfect
API_URL=https://frameperfect.cc/api/app/version/
WINE_BASE_VERSION=stable-25.08
RUNTIME_VERSION=25.08

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

GERAR_SO=0 INSTALAR=1 BUNDLE=1 PUBLICO=0 PUBLICAR=0

# Fecha o Frame Perfect antes de instalar (senão a versão nova só vale
# depois de reabrir)
fechar_app() {
    flatpak ps --columns=application 2>/dev/null | grep -qx $APP_ID || return 0
    echo ">> Fechando o Frame Perfect"
    flatpak kill $APP_ID 2>/dev/null
    for _ in $(seq 20); do
        flatpak ps --columns=application 2>/dev/null | grep -qx $APP_ID || return 0
        sleep 0.5
    done
    echo "!! o Frame Perfect não fechou; feche-o e rode de novo" >&2
    exit 1
}

# Só instala um .flatpak já gerado (--instalar). Serve para outro PC: copie o
# .flatpak e este script e rode lá; precisa só do flatpak (o runtime e a base
# do Wine vêm do Flathub). Os dados do app em ~/.var/app não são tocados.
instalar_bundle() {  # instalar_bundle [arquivo]
    command -v flatpak >/dev/null || { echo "falta o comando: flatpak" >&2; exit 1; }
    local arq=${1:-}
    if [ -z "$arq" ]; then
        # O -full (com o cliente) tem preferência sobre o público
        arq=$(find . -maxdepth 1 -name 'FramePerfect-*-full.flatpak' \
            -printf '%f\n' | sort -V | tail -1)
        [ -n "$arq" ] || arq=$(find . -maxdepth 1 -name 'FramePerfect-*.flatpak' \
            -printf '%f\n' | sort -V | tail -1)
        [ -n "$arq" ] || { echo "nenhum FramePerfect-*.flatpak em $DIR" >&2; exit 1; }
    fi
    [ -f "$arq" ] || { echo "arquivo não encontrado: $arq" >&2; exit 1; }
    flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fechar_app
    echo ">> Instalando $(basename "$arq")"
    flatpak --user install -y --noninteractive --reinstall "$arq"
    echo
    echo "Pronto: Frame Perfect $(flatpak list --user --app --columns=application,version |
        awk -v id="$APP_ID" '$1 == id {print $2}') instalado"
    echo "  rodar: flatpak run $APP_ID (ou pelo menu de aplicativos)"
    exit 0
}
# O arquivo é relativo à pasta de onde o script foi chamado
if [ "${1:-}" = --instalar ]; then
    arq=${2:-}
    [ -z "$arq" ] || [ "${arq#/}" != "$arq" ] || arq=$OLDPWD/$arq
    instalar_bundle "$arq"
fi

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

  5) Publicar no GitHub
     Igual ao completo e depois publica o .flatpak -full em rascunho
     privado (substitui o anterior). O release do código, com o público
     (opção 6), não é apagado; só é criado se não existir.
     Precisa do gh logado e de tudo commitado e enviado (push).

  6) Publicar a versão pública no GitHub
     Gera o .flatpak sem o cliente (ele é baixado do site oficial na
     primeira abertura), sem instalar neste PC, e publica: substitui o
     release do código (v<versão>), com esse .flatpak anexado. O -full
     (opção 5) não é apagado.

  7) Só instalar um .flatpak já gerado
     Instala o FramePerfect-<versão>-full.flatpak mais novo desta pasta, sem
     compilar. Use em outro PC (precisa só do flatpak).

  0) Sair

MENU
    read -rp "  Escolha uma opção [1]: " opcao
    case ${opcao:-1} in
        1) ;;
        2) BUNDLE=0 ;;
        3) INSTALAR=0 ;;
        4) GERAR_SO=1 ;;
        5) PUBLICAR=1 ;;
        6) PUBLICO=1 PUBLICAR=1 ;;
        7) instalar_bundle ;;
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
        --publico) PUBLICO=1 ;;
        --publicar) PUBLICAR=1 ;;
        -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "opção desconhecida: $arg" >&2; exit 1 ;;
    esac
done

# A versão pública não instala neste PC: trocaria a instalação atual (com o
# cliente) por uma que baixa o cliente de novo. Teste com --instalar <arquivo>.
[ $PUBLICO = 1 ] && INSTALAR=0
[ $PUBLICAR = 1 ] && GERAR_SO=0 BUNDLE=1

for c in flatpak curl unzip 7z python3 file; do
    command -v "$c" >/dev/null || { echo "falta o comando: $c" >&2; exit 1; }
done

# O release do código aponta para o commit atual: ele precisa estar no GitHub
if [ $PUBLICAR = 1 ]; then
    for c in git gh; do
        command -v "$c" >/dev/null || { echo "falta o comando: $c" >&2; exit 1; }
    done
    gh auth status >/dev/null 2>&1 || { echo "o gh não está logado (gh auth login)" >&2; exit 1; }
    if [ -n "$(git status --porcelain)" ]; then
        echo "há mudanças não commitadas; faça commit e push antes de publicar" >&2; exit 1
    fi
    git fetch -q origin
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}' 2>/dev/null)" ]; then
        echo "o commit atual não está no GitHub; faça push (ou pull) antes de publicar" >&2; exit 1
    fi
fi

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

# Confere, depois do build, se algum símbolo do cliente ficou sem fonte
cat > scripts/verificar-fontes.py <<'EOF'
#!/usr/bin/env python3
# Gerado por criar-flatpak.sh.
# uso: verificar-fontes.py <FramePerfect.exe> <PresentationCore.dll> <fontes.reg> <fonte.ttf>...
#
# Avisa sobre símbolos do cliente que vão aparecer como quadrado (ou sumir)
# no Wine. Pega os textos do exe (#US e BAML) e, para cada símbolo, faz o que
# o WPF faz: tenta a Segoe UI e, se ela não tiver, o mapa de fallback da
# "Global User Interface" do Wine Mono (faixa Unicode -> lista de famílias).
# Os nomes passam pelas Replacements do fontes.reg e só contam as fontes
# passadas (as que o lançador põe no C:\windows\Fonts). Só avisa: a correção
# (outra fonte, outro mapeamento no fontes.reg) é decidida à mão.
import re, struct, sys, unicodedata

exe, dll, reg, *fontes = sys.argv[1:]
PRIMARIA = 'Segoe UI'
CATEGORIAS = ('So', 'Sm', 'Sk', 'Pd', 'Po', 'Pi', 'Pf', 'Ps', 'Pe', 'No')


def tabelas(d):
    n = struct.unpack_from('>H', d, 4)[0]
    return {d[12+16*i:16+16*i]: struct.unpack_from('>I', d, 20+16*i)[0] for i in range(n)}


def caracteres(d, t):
    c, cps = t[b'cmap'], set()
    for i in range(struct.unpack_from('>H', d, c+2)[0]):
        s = c + struct.unpack_from('>I', d, c+8+8*i)[0]
        fmt = struct.unpack_from('>H', d, s)[0]
        if fmt == 12:
            for k in range(struct.unpack_from('>I', d, s+12)[0]):
                a, b, _ = struct.unpack_from('>III', d, s+16+12*k)
                cps.update(range(a, b+1))
        elif fmt == 4:
            seg = struct.unpack_from('>H', d, s+6)[0] // 2
            for k in range(seg):
                fim = struct.unpack_from('>H', d, s+14+2*k)[0]
                ini = struct.unpack_from('>H', d, s+16+2*seg+2*k)[0]
                cps.update(range(ini, fim+1))
    cps.discard(0xFFFF)
    return cps


def familias(d, t):
    base = t[b'name']
    cnt, soff = struct.unpack_from('>HH', d, base+2)
    nomes = set()
    for k in range(cnt):
        pid, _, _, nid, ln, o = struct.unpack_from('>6H', d, base+6+12*k)
        if pid == 3 and nid in (1, 16):
            nomes.add(d[base+soff+o:base+soff+o+ln].decode('utf-16-be'))
    return nomes


cobertura = {}  # família -> caracteres
for f in fontes:
    d = open(f, 'rb').read()
    t = tabelas(d)
    for nome in familias(d, t):
        cobertura.setdefault(nome.lower(), set()).update(caracteres(d, t))

troca = {}
txt = open(reg, encoding='utf-8', errors='replace').read()
if 'Replacements]' in txt:
    for de, para in re.findall(r'^"([^"]+)"="([^"]+)"', txt.split('Replacements]', 1)[1], re.M):
        troca[de.lower()] = para


def tem(familia, cp):
    real = troca.get(familia.lower(), familia)
    return real, cp in cobertura.get(real.lower(), ())


# Mapa de fallback: a "Global User Interface" do Windows 10 RS5 (a que o Wine Mono usa)
d = open(dll, 'rb').read().decode('utf-8', 'replace')
blocos = re.findall(r'<FontFamily\s+xmlns=.*?</FontFamily>', d, re.S)
gui = [b for b in blocos if 'Global User Interface' in b]
gui = next((b for b in gui if 'OS="Windows10RS5"' in b), gui[0] if gui else '')
gui = re.sub(r'<!--.*?-->', '', gui, flags=re.S)
mapas = []
for m in re.findall(r'<FontFamilyMap\b(.*?)/>', gui, re.S):
    attr = dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', m))
    if attr.get('Language') and not attr['Language'].lower().startswith('pt'):
        continue
    faixas = []
    for r in attr.get('Unicode', '').split(','):
        a, _, b = r.strip().partition('-')
        if a:
            faixas.append((int(a, 16), int(b or a, 16)))
    mapas.append((faixas, [x.strip() for x in attr.get('Target', '').split(',') if x.strip()]))
if not mapas:
    print('!! verificar-fontes: mapa de fallback do WPF não encontrado em', dll)
    sys.exit(0)

# Textos do cliente: #US (strings do código, UTF-16) e BAML (XAML, UTF-8)
d = open(exe, 'rb').read()
textos = []
i = d.find(b'BSJB')
if i >= 0:
    p = i + 16 + struct.unpack_from('<I', d, i+12)[0] + 2
    n = struct.unpack_from('<H', d, p)[0]; p += 2
    for _ in range(n):
        off, tam = struct.unpack_from('<II', d, p); p += 8
        e = d.index(b'\0', p); nome = d[p:e]; p = (e + 4) & ~3
        if nome == b'#US':
            q, fim = i + off + 1, i + off + tam
            while q < fim:
                b = d[q]
                if b & 0x80 == 0: L = b; q += 1
                elif b & 0xC0 == 0x80: L = ((b & 0x3f) << 8) | d[q+1]; q += 2
                else: L = ((b & 0x1f) << 24) | (d[q+1] << 16) | (d[q+2] << 8) | d[q+3]; q += 4
                if L > 1:
                    textos.append(d[q:q+L-1].decode('utf-16le', 'replace'))
                q += L
for m in re.finditer(rb'(?:[\x20-\x7e]|[\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf]{2}|[\xf0-\xf4][\x80-\xbf]{3}){4,}', d):
    t = m.group().decode('utf-8', 'ignore')
    if re.search(r'[A-Za-z]{3}', t):
        textos.append(t)

simbolos = {}
for t in textos:
    for c in t:
        if ord(c) > 0x7f and unicodedata.category(c) in CATEGORIAS:
            simbolos.setdefault(c, t.strip())

faltando = 0
for c, ctx in sorted(simbolos.items()):
    cp = ord(c)
    if tem(PRIMARIA, cp)[1]:
        continue
    alvos = next((a for faixas, a in mapas if any(x <= cp <= y for x, y in faixas)), [])
    tentou = []
    for f in alvos:
        real, ok = tem(f, cp)
        if ok:
            break
        tentou.append(f if real == f else f'{f} -> {real}')
    else:
        faltando += 1
        print(f'!! sem fonte para {c} (U+{cp:04X}) em "{ctx[:60]}"')
        print(f'   o WPF tenta {PRIMARIA} -> {tem(PRIMARIA, cp)[0]}, ' +
              (', '.join(tentou) if tentou else 'nenhuma família no mapa de fallback'))
print(f'>> Fontes: {len(simbolos)} símbolos do cliente conferidos, {faltando} sem fonte')
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
"Cambria Math"="Noto Emoji"
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
# Na versão pública (criar-flatpak.sh --publico) o pacote não traz o cliente:
# ele é baixado do site oficial na primeira abertura para /var/data/cliente,
# que faz o papel do /app/frameperfect.
#
# Subcomandos para depuração:
#   flatpak run cc.frameperfect.FramePerfect winecfg|regedit|winetricks ...|shell

SEMENTE=/app/frameperfect
DATA=/var/data
JOGO=$DATA/FramePerfect
API_VERSAO=${FP_API_VERSAO:-https://frameperfect.cc/api/app/version/}
PUBLICO=@PUBLICO@
[ $PUBLICO = 1 ] && SEMENTE=$DATA/cliente

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
# - "Cambria Math" -> Noto Emoji: para 27C0-2BFF o WPF tenta Segoe UI Symbol
#   (DejaVu Sans, sem o ⭕ de "🅱️ / ⭕ / Esc voltar") e depois Cambria Math;
# - a Tahoma do Wine e a Barlow ("Tw Cen MT Condensed") vêm do build sem a
#   ligadura (scripts/fontes.py), em /app/share/frameperfect/fontes.
FONTES_VERSAO="5 $WINE_VERSAO"
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

# --- Versão pública: baixa o cliente completo na primeira abertura ---
if [ $PUBLICO = 1 ] && [ ! -f "$SEMENTE/FramePerfect.exe" ]; then
    INFO=$(curl -fsS --max-time 15 "$API_VERSAO" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["latest_version"], d["full_download_url"], d["full_file_size_bytes"])' 2>/dev/null)
    URL=$(echo "$INFO" | cut -d' ' -f2)
    TAM=$(echo "$INFO" | cut -d' ' -f3)
    ZIP=$DATA/.fp-cliente.zip
    # O zip completo não tem SHA-256 na API: confere o tamanho, e o
    # atualizar.py confere o CRC de cada arquivo ao extrair
    if [ -n "$INFO" ] &&
       com_progresso "Baixando o Frame Perfect ${INFO%% *} do site oficial..." \
           curl -fsSL -o "$ZIP" "$URL" &&
       [ "$(stat -c %s "$ZIP")" = "$TAM" ]; then
        rm -rf "$SEMENTE.novo"
        python3 /app/share/frameperfect/atualizar.py "$ZIP" "$SEMENTE.novo" >/dev/null &&
            rm -rf "$SEMENTE" && mv "$SEMENTE.novo" "$SEMENTE"
    fi
    rm -rf "$ZIP" "$SEMENTE.novo"
    if [ ! -f "$SEMENTE/FramePerfect.exe" ]; then
        MSG="Não foi possível baixar o Frame Perfect de frameperfect.cc. Confira a conexão e abra de novo."
        echo "$MSG" >&2
        command -v zenity >/dev/null && zenity --error --title="Frame Perfect" --text="$MSG" 2>/dev/null
        exit 1
    fi
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
# trouxer versão mais nova que a instalada. A config do launcher (login), as
# configs dos emuladores (emuladores/*/config: só os arquivos que faltam) e os
# arquivos do usuário (ROMs, logs) não são sobrescritos.
V_SEMENTE=$(versao "$SEMENTE")
V_JOGO=$(versao "$JOGO")
if [ ! -f "$JOGO/FramePerfect.exe" ] || mais_nova "$V_SEMENTE" "$V_JOGO"; then
    echo "Instalando o Frame Perfect $V_SEMENTE em $JOGO (havia: ${V_JOGO:-nada})"
    mkdir -p "$JOGO"
    imutaveis > "$DATA/.fp-imutaveis"
    (cd "$SEMENTE" && tar cf - -X "$DATA/.fp-imutaveis" --exclude=./rbf-launcher.json \
        --exclude='./emuladores/*/config' .) | (cd "$JOGO" && tar xf - --no-same-owner)
    rm -f "$DATA/.fp-imutaveis"
    for d in "$SEMENTE"/emuladores/*/config; do
        [ -d "$d" ] || continue
        mkdir -p "$JOGO/${d#"$SEMENTE"/}"
        cp -r --update=none "$d/." "$JOGO/${d#"$SEMENTE"/}/"
    done
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
            # Na versão pública a semente também é atualizada (ela é gravável),
            # para continuar servindo de base para os links e a recuperação
            if [ $PUBLICO = 1 ]; then
                python3 /app/share/frameperfect/atualizar.py "$PACOTE" "$SEMENTE" &&
                    V_SEMENTE=$(versao "$SEMENTE")
            fi
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

# Atalhos para o usuário achar as ROMs e as configs dos emuladores em
# ~/.var/app/cc.frameperfect.FramePerfect: data/roms, config/favoritos.json e
# config/emulator/<emulador>.
# Links relativos, para funcionarem no host e no sandbox (/var/config). Não
# substitui o que o usuário tiver posto lá no lugar de um link.
atalho() {  # atalho <alvo relativo> <link>
    mkdir -p "$(dirname "$2")"
    if [ -L "$2" ] || [ ! -e "$2" ]; then
        [ "$(readlink "$2")" = "$1" ] || ln -sfn "$1" "$2"
    fi
}
EMU=../../../data/FramePerfect/emuladores
atalho FramePerfect/roms "$DATA/roms"
atalho ../data/FramePerfect/favoritos.json /var/config/favoritos.json
for d in games presets ips localisation; do
    atalho $EMU/arcade/config/$d /var/config/emulator/arcade/$d
done
# DuckStation (baixado pelo cliente na primeira vez que se joga PS1)
for f in settings.ini gamesettings inputprofiles; do
    atalho $EMU/ps1/$f /var/config/emulator/ps1/$f
done

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
sed -i "s/@PUBLICO@/$PUBLICO/" scripts/frameperfect.sh
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
# Versão pública: o cliente não entra no pacote (o lançador baixa)
CLIENTE_CMDS="" CLIENTE_SRCS=""
if [ $PUBLICO = 0 ]; then
    CLIENTE_CMDS="      - mkdir -p /app/frameperfect"$'\n'"      - cp -a cliente/. /app/frameperfect/"$'\n'
    CLIENTE_SRCS="      - type: archive"$'\n'"        path: $ZIP"$'\n'"        sha256: $ZIP_SHA"$'\n'"        dest: cliente"$'\n'
fi

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
${CLIENTE_CMDS}      - install -Dm755 frameperfect.sh /app/bin/frameperfect
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
${CLIENTE_SRCS}      - type: file
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

echo ">> Arquivos gerados para a versão $VERSAO$([ $PUBLICO = 1 ] && echo ' (pública)')"
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

# A versão pública vai para outro repo: o remote frameperfect-local (o repo/)
# é de onde a instalação deste PC se atualiza. O .flatpak com o cliente leva
# "-full" no nome; o público fica só com a versão.
REPO=repo
ARQ=FramePerfect-$VERSAO-full.flatpak
if [ $PUBLICO = 1 ]; then
    REPO=repo-publico
    ARQ=FramePerfect-$VERSAO.flatpak
fi

# Sem --install: instalando de dentro do sandbox do Builder, o .desktop
# exportado ganha Exec=/app/bin/flatpak (caminho do Builder) e some do menu
BUILDER_ARGS=(--force-clean --user --repo=$REPO --disable-rofiles-fuse)

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
# O repo criado pelo ostree exige 3% do disco livre (~10 GB num disco de
# 300 GB) e o export falha com "min-free-space-percent would be exceeded".
# Usa o mesmo limite fixo da instalação --user do flatpak (500MB).
flatpak run --filesystem="$DIR" --cwd="$DIR" --command=ostree org.flatpak.Builder \
    init --repo=$REPO --mode=archive-z2
flatpak run --filesystem="$DIR" --cwd="$DIR" --command=ostree org.flatpak.Builder \
    config --repo=$REPO set core.min-free-space-size 500MB
# --filesystem: o sandbox do Builder não enxerga pastas fora da home (ex.: /tmp)
flatpak run --filesystem="$DIR" --cwd="$DIR" --command=flatpak-builder org.flatpak.Builder \
    "${BUILDER_ARGS[@]}" build-dir $APP_ID.yml

# Símbolos do cliente sem fonte no Wine (só avisa; ver scripts/verificar-fontes.py).
# Usa as fontes que o lançador copia para o prefixo: as do build e as do runtime.
MONO=$(flatpak info --show-location org.winehq.Wine.mono//$WINE_BASE_VERSION 2>/dev/null)
PLATAFORMA=$(flatpak info --show-location org.freedesktop.Platform//$RUNTIME_VERSION 2>/dev/null)
DLL=$(find "${MONO:-/nada}/files" -name PresentationCore.dll 2>/dev/null | head -1)
if [ -n "$DLL" ] && [ -n "$PLATAFORMA" ]; then
    mapfile -t FONTES < <(find "$PLATAFORMA/files/share/fonts" \( -name DejaVuSans.ttf \
        -o -name 'LiberationSans-*.ttf' -o -name 'LiberationMono-*.ttf' \))
    python3 -I scripts/verificar-fontes.py "$TMP/FramePerfect.exe" "$DLL" fontes.reg \
        "${FONTES[@]}" build-dir/files/share/frameperfect/fontes/*.ttf
else
    echo "!! verificação de fontes pulada: Wine Mono ou runtime não encontrado" >&2
fi

if [ $INSTALAR = 1 ]; then
    fechar_app
    echo ">> Instalando (--user) a partir do repo local"
    flatpak --user remote-add --if-not-exists --no-gpg-verify frameperfect-local "$DIR/repo"
    flatpak --user install -y --noninteractive --reinstall frameperfect-local $APP_ID
fi

if [ $BUNDLE = 1 ]; then
    echo ">> Gerando $ARQ"
    flatpak build-bundle $REPO "$ARQ" $APP_ID \
        --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
fi

# ---------------------------------------------------------------------------
# 7. Publica no GitHub (--publicar). São dois releases:
#    - v<versão>: o código (o "latest") com o .flatpak público anexado.
#      Substituído pela opção 6; a opção 5 só o cria se não houver nenhum
#      (sem o anexo), para não apagar o público;
#    - flatpak-full-<versão>: rascunho privado com o -full (opção 5).
# ---------------------------------------------------------------------------
if [ $PUBLICAR = 1 ]; then
    COMMIT=$(git rev-parse HEAD)
    SHA=$(sha256sum "$ARQ" | cut -d' ' -f1)
    REPO_GH=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    preencher() {  # troca os @CAMPOS@ das notas
        sed -e "s|@VERSAO@|$VERSAO|g" -e "s|@COMMIT@|${COMMIT:0:7}|g" -e "s|@SHA@|$SHA|g" \
            -e "s|@ARQ@|$ARQ|g" -e "s|@REPO@|$REPO_GH|g"
    }
    tipo() {  # tipo <tag> <rascunho>: codigo, full ou publico
        case $1 in
            v[0-9]*) echo codigo ;;
            flatpak-full-*) echo full ;;
            flatpak-*) [ "$2" = true ] && echo full || echo publico ;;  # formatos antigos
            *) echo outro ;;
        esac
    }
    # Apaga os releases (de qualquer versão) dos tipos passados
    apagar() {
        echo ">> Apagando os releases antigos ($*)"
        gh release list --limit 1000 --json tagName,isDraft -q '.[] | "\(.tagName) \(.isDraft)"' |
            while read -r tag rascunho; do
                case " $* " in *" $(tipo "$tag" "$rascunho") "*) ;; *) continue ;; esac
                echo "   $tag"
                if [ "$rascunho" = true ]; then  # rascunho não tem tag
                    gh release delete "$tag" --yes </dev/null
                else
                    gh release delete "$tag" --yes --cleanup-tag </dev/null
                    git tag -d "$tag" >/dev/null 2>&1 || true
                fi
            done
    }
    # O upload do .flatpak às vezes trava (ex.: a internet cai); com limite
    # de tempo e até 3 tentativas (--clobber substitui o envio incompleto)
    enviar() {  # enviar <tag> <arquivo>
        local n
        for n in 1 2 3; do
            timeout 420 gh release upload "$1" "$2" --clobber && return 0
            echo "!! envio de $2 falhou (tentativa $n de 3)" >&2
        done
        exit 1
    }

    if [ $PUBLICO = 0 ]; then
        apagar full
        # Contém o cliente proprietário: só em rascunho (visível para quem
        # tem acesso de escrita ao repositório)
        preencher > "$TMP/notas-flatpak.md" <<'NOTAS'
**Rascunho privado: não publicar.** Contém o cliente proprietário do Frame Perfect; rascunhos só ficam visíveis para quem tem acesso de escrita ao repositório.

`@ARQ@`, gerado pelo `criar-flatpak.sh` do commit @COMMIT@ (cliente @VERSAO@).
SHA-256: `@SHA@`

Baixar (precisa estar logado no `gh`):

```sh
gh release download flatpak-full-@VERSAO@ -R @REPO@ -p '*.flatpak'
./criar-flatpak.sh --instalar
```
NOTAS
        echo ">> Publicando o .flatpak em rascunho (flatpak-full-$VERSAO)"
        gh release create "flatpak-full-$VERSAO" --draft --target "$COMMIT" \
            --title "$ARQ (privado)" --notes-file "$TMP/notas-flatpak.md"
        enviar "flatpak-full-$VERSAO" "$ARQ"
    fi

    # Release do código: a opção 6 sempre recria (com o .flatpak público);
    # a opção 5 só cria se não existir nenhum
    CODIGO_EXISTE=$(gh release list --limit 1000 --json tagName -q '.[].tagName' | grep -c '^v[0-9]' || true)
    if [ $PUBLICO = 1 ] || [ "$CODIGO_EXISTE" = 0 ]; then
        if [ $PUBLICO = 1 ]; then
            # O link direto do README aponta para o .flatpak público desta
            # versão: atualiza, faz commit e push, e o release usa esse commit
            sed -i -E "s#FramePerfect-[0-9][0-9.]*\.flatpak#$ARQ#g; s#releases/download/v[0-9][0-9.]*/#releases/download/v$VERSAO/#g" README.md
            if ! git diff --quiet README.md; then
                echo ">> Atualizando o link de download do README para $VERSAO"
                git commit -q -m "README: link de download do $ARQ" README.md
                git push -q origin HEAD
                COMMIT=$(git rev-parse HEAD)
            fi
            apagar codigo publico
        fi
        {
            cat <<'NOTAS'
Flatpak do [Frame Perfect](https://frameperfect.cc) rodando o cliente de Windows (10/11) no Wine, no mesmo modelo do [com.fightcade.Fightcade](https://github.com/flathub/com.fightcade.Fightcade) do Flathub. Testado com o cliente **@VERSAO@**.

NOTAS
            if [ $PUBLICO = 1 ]; then
                cat <<'NOTAS'
### Instalar o .flatpak pronto

**Download:** [@ARQ@](https://github.com/@REPO@/releases/download/v@VERSAO@/@ARQ@)

O `@ARQ@` não contém o cliente do Frame Perfect (que é proprietário): na primeira abertura ele baixa o cliente oficial de frameperfect.cc (~150 MB) e depois se atualiza sozinho.

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user @ARQ@
flatpak run cc.frameperfect.FramePerfect
```

SHA-256: `@SHA@`

### Ou gerar na sua máquina
NOTAS
            else
                cat <<'NOTAS'
### Como gerar e instalar
NOTAS
            fi
            cat <<'NOTAS'

O script baixa o cliente oficial do site e gera o pacote na sua máquina:

```sh
git clone https://github.com/@REPO@.git
cd frameperfect-flatpak
./criar-flatpak.sh          # menu: escolha 1 (completo) ou 2 (compilar e instalar)
flatpak run cc.frameperfect.FramePerfect
```

Precisa de `flatpak` (com o Flathub), `curl`, `unzip`, `7z`, `file` e `python3`. O script instala o resto (org.flatpak.Builder, SDK 25.08 e a base org.winehq.Wine stable-25.08).

Para levar a outro PC: gere o `.flatpak` (opção 1 ou 3 do menu) e instale lá com `./criar-flatpak.sh --instalar` (precisa só do `flatpak`).

### O que tem

- Cliente WPF rodando com Wine 11 + Wine Mono, sem precisar do .NET da Microsoft
- Fontes corrigidas: sem quadrados no lugar de símbolos, emojis e ligaduras (fi, fl)
- Links `frameperfect://replay?...` do site abrem o app
- Atalhos em `~/.var/app/cc.frameperfect.FramePerfect` para as ROMs (`data/roms`), os favoritos (`config/favoritos.json`) e as configs dos emuladores (`config/emulator/arcade/{games,presets,ips,localisation}` e do DuckStation em `config/emulator/ps1`)
- O cliente roda em `~/.var/app/cc.frameperfect.FramePerfect` com links para os arquivos estáticos; as atualizações do cliente são aplicadas pelo lançador, e os dados apagados são recriados ao abrir

Detalhes no [README](https://github.com/@REPO@#readme).
NOTAS
        } | preencher > "$TMP/notas-codigo.md"

        echo ">> Publicando o release do código (v$VERSAO)"
        gh release create "v$VERSAO" --target "$COMMIT" --latest \
            --title "Frame Perfect $VERSAO" --notes-file "$TMP/notas-codigo.md"
        [ $PUBLICO = 0 ] || enviar "v$VERSAO" "$ARQ"
    else
        echo ">> Release do código mantido (é substituído pela opção 6, com o .flatpak público)"
    fi
fi

echo
echo "Pronto: Frame Perfect $VERSAO$([ $PUBLICO = 1 ] && echo ' (versão pública: o cliente é baixado na 1ª abertura)')"
[ $INSTALAR = 1 ] && echo "  rodar:   flatpak run $APP_ID"
[ $BUNDLE = 1 ] && echo "  bundle:  $DIR/$ARQ (./criar-flatpak.sh --instalar $ARQ)"
[ $PUBLICAR = 1 ] && echo "  github:  https://github.com/$REPO_GH/releases"
exit 0
