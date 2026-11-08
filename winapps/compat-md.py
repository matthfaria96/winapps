#!/usr/bin/env python3
"""Gera COMPATIBILIDADE.md (raiz do repositório) a partir de compat.json.

compat.json é a fonte única: o app usa as mesmas regras para os avisos ao abrir um
programa, os selos da biblioteca e a aba Compatibilidade.
Uso: python3 compat-md.py [saída.md]   (padrão: ../COMPATIBILIDADE.md)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "COMPATIBILIDADE.md")

BADGE = {"verificado": "✅ Verificado", "funciona": "🟢 Funciona",
         "parcial": "🟡 Parcial", "nao-funciona": "❌ Não funciona"}
COMPONENT = {"dotnet48": ".NET 4.8", "winrt-metadata": "WinRT", "webview2": "WebView2"}
ORDER = ["Produtividade", "Jogos", "Utilitários", "Não suportados", "Por tecnologia"]


def badge(r):
    return BADGE["verificado"] if r.get("verified") else BADGE.get(r.get("status", ""), r.get("status", ""))


def esc(s):
    return (s or "").replace("|", "\\|").replace("\n", " ")


def main():
    with open(os.path.join(HERE, "compat.json"), encoding="utf-8") as f:
        rules = json.load(f)["rules"]
    rules.sort(key=lambda r: (ORDER.index(r["category"]) if r.get("category") in ORDER else 99))

    n_ok = sum(1 for r in rules if r.get("kind") == "app" and r.get("status") == "funciona")
    n_ver = sum(1 for r in rules if r.get("verified"))
    out = [
        "# Compatibilidade do WinApps",
        "",
        f"**{n_ok} programas funcionando**, {n_ver} verificados com correções próprias.  ",
        "✅ Verificado = testado de ponta a ponta, com correções do WinApps · 🟢 Funciona = testado ·",
        "🟡 Parcial · ❌ Não funciona · fora da tabela = ⚪ Não testado.",
        "",
        "> Gerado de [`winapps/compat.json`](winapps/compat.json) por `winapps/compat-md.py` (não edite à mão).",
        "> O app mostra a mesma lista na aba **Compatibilidade**, com busca.",
        "",
        "| Programa | Situação | Categoria | Testado | Resumo | Correções |",
        "|---|---|---|---|---|:---:|",
    ]
    for r in rules:
        fixes = len(r.get("fixes", []))
        out.append(f"| [{esc(r['name'])}](#{slug(r['name'])}) | {badge(r)} | {esc(r.get('category'))} | "
                   f"{esc(r.get('tested')) or '—'} | {esc(r.get('summary'))} | {fixes or '—'} |")
    out += ["", "## Detalhes", ""]
    for r in rules:
        out.append(f'<details id="{slug(r["name"])}"><summary><b>{r["name"]}</b> — {badge(r)}</summary>')
        out.append("")
        out.append(r.get("why", ""))
        if r.get("alt"):
            out.append("")
            out.append(f"💡 {r['alt']}")
        if r.get("needs"):
            out.append("")
            out.append("**Precisa de:** " + ", ".join(COMPONENT.get(n, n) for n in r["needs"])
                       + " (já incluídos no ambiente do WinApps)")
        if r.get("fixes"):
            out.append("")
            out.append("**Correções do WinApps:**")
            out += [f"- {x}" for x in r["fixes"]]
        out += ["", "</details>", ""]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"gerado: {os.path.normpath(OUT)}")


def slug(name):
    import re
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


if __name__ == "__main__":
    main()
