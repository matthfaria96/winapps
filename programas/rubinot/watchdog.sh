#!/bin/bash
# Reabre o RubinOT automaticamente quando o cliente sai sozinho (a sessão cai:
# o túnel do ExitLag e o canal do EMAC não sobrevivem no Wine).
#
# Desligar: touch "$HOME/Library/Application Support/WinApps/prefixes/default/.rubinot-sem-vigia"
# (o vigia também se desliga sozinho se a reabertura falhar 3 vezes seguidas)
set -u
# Mensagens em inglês ou português (WINAPPS_UI_LANG; sem ela, o 1º idioma do macOS)
case "${WINAPPS_UI_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')}" in
    pt*) UI_LANG=pt ;; *) UI_LANG=en ;;
esac
t() { if [ "$UI_LANG" = pt ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
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
        echo "$(date +%H:%M:%S) $(t "3 failures in a row; watchdog turned off (remove $FLAG to turn it back on)" \
                                    "3 falhas seguidas; vigia desligado (remova $FLAG para religar)")" >> "$LOG"
        touch "$FLAG"
        continue
    fi
    echo "$(date +%H:%M:%S) $(t "client quit; reopening (attempt $((falhas+1))/3)" "cliente saiu; reabrindo (falha $((falhas+1))/3)")" >> "$LOG"
    open "$APP"
    falhas=$((falhas+1)); aberto_em=$(date +%s)
done
