#!/bin/bash
# Compila as bibliotecas do cliente RubinOT (x64, mingw) em cliente/:
#   emac-client64-stub.dll  biblioteca de compatibilidade (10 símbolos: CLHB CLVER PF SLG SWND
#                           USR USR2 USR3 USR4 USRLGT; devolve sucesso e registra em
#                           bin/x64/emac-stub-calls.log)
#   avrt.dll                janela com escala + X fecha (win-size-hook.c; log bin/x64/avrt-hook.log)
# Depois: bash install.sh (copia para C:\RubinOT\bin\x64).
set -euo pipefail
cd "$(dirname "$0")/cliente"
CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || export PATH="$(brew --prefix mingw-w64)/bin:$PATH"
$CC -shared -O2 -o emac-client64-stub.dll emac-client64-stub.c emac-client64.def
$CC -shared -O2 -o avrt.dll win-size-hook.c win-size-hook.def
echo "gerados: $PWD/{emac-client64-stub.dll,avrt.dll}"
