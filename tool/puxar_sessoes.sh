#!/usr/bin/env bash
# Copia as sessões de métricas do tablet para a pasta do teste informado.
# Não apaga nada no tablet (para isso, use tool/limpar_tablet.sh).
#
# Uso: tool/puxar_sessoes.sh T1|T2|T3
set -euo pipefail

PASTA_TABLET=/sdcard/Android/data/br.com.tcc.tcc_ela_eye_tracking_interface/files/typing_metrics
RAIZ=$(cd "$(dirname "$0")/.." && pwd)

teste=${1:-}
case "$teste" in
    T1 | T2 | T3) ;;
    *)
        echo "Uso: $0 T1|T2|T3" >&2
        exit 1
        ;;
esac
destino="$RAIZ/sessoes/$teste"
mkdir -p "$destino"

if ! adb get-state >/dev/null 2>&1; then
    echo "Nenhum tablet conectado. Ligue o cabo USB e ative a depuração USB." >&2
    exit 1
fi

sessoes=$(adb shell "ls $PASTA_TABLET/session_*.json 2>/dev/null" | tr -d '\r' || true)
if [ -z "$sessoes" ]; then
    echo "Não há sessões no tablet."
    exit 0
fi

copiadas=0
for caminho in $sessoes; do
    nome=$(basename "$caminho")
    # Uma sessão que já está em outro teste ficou no tablet por engano.
    outro=$(find "$RAIZ/sessoes" -name "$nome" -not -path "$destino/*" | head -n 1)
    if [ -n "$outro" ]; then
        echo "pulada:  $nome (já está em ${outro#"$RAIZ"/})"
        continue
    fi
    adb pull "$caminho" "$destino/$nome" >/dev/null
    echo "copiada: $nome -> sessoes/$teste/"
    copiadas=$((copiadas + 1))
done

echo
echo "$copiadas sessão(ões) copiada(s) para sessoes/$teste/."
echo "Próximos passos: conferir as sessões, rodar tool/limpar_tablet.sh e depois python tool/gerar_tabela.py."
