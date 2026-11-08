#!/bin/bash
# Compila o avrt.dll (hook de tamanho da janela do RubinOT) para x64.
# O resultado deve ser copiado para <prefixo>/drive_c/RubinOT/bin/x64/avrt.dll
set -euo pipefail
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -shared -O2 -o avrt.dll win-size-hook.c win-size-hook.def
echo "gerado: $(pwd)/avrt.dll"
