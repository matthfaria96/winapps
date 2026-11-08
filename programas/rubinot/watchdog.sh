#!/bin/bash
# Reabre o RubinOT automaticamente quando o cliente sai sozinho (a sessão cai:
# o túnel do ExitLag e o canal do EMAC não sobrevivem no Wine).
#
# Desligar: touch "$HOME/Library/Application Support/WinApps/prefixes/default/.rubinot-sem-vigia"
# (o vigia também se desliga sozinho se a reabertura falhar 3 vezes seguidas)
set -u
FLAG="$HOME/Library/Application Support/WinApps/prefixes/default/.rubinot-sem-vigia"
APP="$HOME/Applications/RubinOT.app"
INTERVALO="${RUBINOT_VIGIA_INTERVALO:-8}"
LOG=/tmp/rubinot-vigia.log
falhas=0
aberto_em=0
while true; do
    sleep "$INTERVALO"
    [ -f "$FLAG" ] && continue
    if pgrep -f '/MacOS/RubinOT$' >/dev/null 2>&1; then
        # se ficou vivo mais de 60 s depois da reabertura, zera o contador de falhas
        if [ "$aberto_em" -gt 0 ] && [ $(( $(date +%s) - aberto_em )) -gt 60 ]; then
            falhas=0; aberto_em=0
        fi
        continue
    fi
    # cliente não está rodando: espera um ciclo para confirmar que não é fechamento
    sleep "$INTERVALO"
    pgrep -f '/MacOS/RubinOT$' >/dev/null 2>&1 && continue
    if [ "$falhas" -ge 3 ]; then
        echo "$(date +%H:%M:%S) 3 falhas seguidas; vigia desligado (crie/remova $FLAG para religar)" >> "$LOG"
        touch "$FLAG"
        continue
    fi
    echo "$(date +%H:%M:%S) cliente saiu; reabrindo (falha $((falhas+1))/3)" >> "$LOG"
    open "$APP"
    falhas=$((falhas+1)); aberto_em=$(date +%s)
done
