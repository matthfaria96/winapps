#!/bin/bash
# Compila o stub do anti-cheat do cliente (emac-client64.dll, x64).
# O cliente importa por GetProcAddress 10 símbolos: CLHB CLVER PF SLG SWND USR USR2 USR3 USR4 USRLGT.
# O stub só devolve 0 (sucesso) e registra as chamadas em bin/x64/emac-stub-calls.log.
set -euo pipefail
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -shared -O2 -o emac-client64-stub.dll emac-client64-stub.c emac-client64.def
echo "gerado: $(pwd)/emac-client64-stub.dll"
