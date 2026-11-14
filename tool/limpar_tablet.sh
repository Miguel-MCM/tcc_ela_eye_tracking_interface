#!/usr/bin/env bash
# Apaga todas as sessões de métricas gravadas no tablet, depois de mostrá-las
# e pedir confirmação.
#
# Uso: tool/limpar_tablet.sh
set -euo pipefail

PASTA_TABLET=/sdcard/Android/data/br.com.tcc.tcc_ela_eye_tracking_interface/files/typing_metrics

if ! adb get-state >/dev/null 2>&1; then
    echo "Nenhum tablet conectado. Ligue o cabo USB e ative a depuração USB." >&2
    exit 1
fi

sessoes=$(adb shell "ls $PASTA_TABLET/session_*.json 2>/dev/null" | tr -d '\r' || true)
if [ -z "$sessoes" ]; then
    echo "Não há sessões no tablet."
    exit 0
fi

echo "Sessões no tablet:"
adb shell "ls -l $PASTA_TABLET/session_*.json" | tr -d '\r'
echo
echo "$(echo "$sessoes" | wc -l) sessão(ões). Elas serão APAGADAS do tablet."
echo "Já copiou para o computador as que interessam? (tool/puxar_sessoes.sh TN)"
read -r -p "Apagar? [s/N] " resposta
if [ "$resposta" != "s" ] && [ "$resposta" != "S" ]; then
    echo "Nada foi apagado."
    exit 0
fi

adb shell "rm $PASTA_TABLET/session_*.json"
echo "Sessões apagadas do tablet."
