#!/usr/bin/env python3
"""Escreve (ou ajusta) o config.otml do cliente RubinOT para abrir numa janela do tamanho pedido.

O cliente reescreve o config ao sair (window-size volta para 1490x714 e resetconfig: true),
por isso o ajuste tem que ser feito ANTES de cada abertura.
Uso: set-window.py <largura> <altura>
"""
import re
import sys
import os

W, H = int(sys.argv[1]), int(sys.argv[2])
prefix = os.environ.get("WINEPREFIX", "/Volumes/WinAppsDev/prefixes/rubinot")
path = os.path.join(prefix, "drive_c", "RubinOT", "bin", "config.otml")

text = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()

def put(key, value, text):
    line = f"{key}: {value}"
    if re.search(rf"(?m)^{re.escape(key)}:.*$", text):
        return re.sub(rf"(?m)^{re.escape(key)}:.*$", line, text, count=1)
    return text + ("" if text.endswith("\n") or not text else "\n") + line + "\n"

text = put("window-size", f"{W} {H}", text)
text = put("window-maximized", "false", text)
# o SDK do ExitLag grava log sem parar (chegou a 21 GB em 2 h nesta sessão)
text = put("exitlagdebugconfigenabled", "false", text)
# auto-reconexao: se o servidor derrubar por causa do EMAC, o cliente volta sozinho
lines = text.splitlines()
out, inside = [], False
for ln in lines:
    if ln.strip() == "autoReconnectSettings:":
        inside = True; out.append(ln); continue
    if inside:
        if ln.startswith("  ") and ln.rstrip().endswith(": false"):
            out.append(ln.rstrip()[:-6] + ": true"); continue
        if ln.strip() and not ln.startswith("  "):
            inside = False
    out.append(ln)
text = "\n".join(out) + "\n"
text = put("resetconfig", "false", text)
if len(sys.argv) > 3 and sys.argv[3] == "fullscreen":
    text = put("fullscreen", "true", text)
else:
    text = put("fullscreen", "false", text)

with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(text)
print(f"config.otml: window-size {W}x{H}, resetconfig false")
