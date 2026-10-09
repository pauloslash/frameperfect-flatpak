#!/usr/bin/env bash
# Instala (--user) o FramePerfect-<versão>.flatpak de versão mais alta que
# estiver na pasta deste script, substituindo a instalação atual.
#
# Uso:
#   ./instalar-flatpak.sh            instala o .flatpak mais novo da pasta
#   ./instalar-flatpak.sh <arquivo>  instala um .flatpak específico
#
# Os dados do app (login, ROMs, configs em ~/.var/app/cc.frameperfect.FramePerfect)
# não são tocados. O runtime e a base do Wine vêm do Flathub.
set -euo pipefail

APP_ID=cc.frameperfect.FramePerfect
DIR=$(cd "$(dirname "$0")" && pwd)

case ${1:-} in
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
esac

command -v flatpak >/dev/null || { echo "falta o comando: flatpak" >&2; exit 1; }

if [ $# -gt 0 ]; then
    BUNDLE=$1
else
    BUNDLE=$(find "$DIR" -maxdepth 1 -name 'FramePerfect-*.flatpak' -printf '%f\n' |
        sort -V | tail -1)
    [ -n "$BUNDLE" ] || { echo "nenhum FramePerfect-*.flatpak em $DIR (rode ./criar-flatpak.sh)" >&2; exit 1; }
    BUNDLE=$DIR/$BUNDLE
fi
[ -f "$BUNDLE" ] || { echo "arquivo não encontrado: $BUNDLE" >&2; exit 1; }

# O runtime (org.freedesktop.Platform) e a base org.winehq.Wine vêm do Flathub
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

if flatpak ps --columns=application 2>/dev/null | grep -qx "$APP_ID"; then
    echo "O Frame Perfect está aberto; feche-o antes de instalar." >&2
    exit 1
fi

echo ">> Instalando $(basename "$BUNDLE")"
flatpak --user install -y --noninteractive --reinstall "$BUNDLE"

echo
echo "Pronto: Frame Perfect $(flatpak list --user --app --columns=application,version |
    awk -v id="$APP_ID" '$1 == id {print $2}') instalado"
echo "  rodar: flatpak run $APP_ID (ou pelo menu de aplicativos)"
