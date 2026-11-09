#!/usr/bin/env python3
"""Generates COMPATIBILITY.md (English) and COMPATIBILIDADE.md (Brazilian Portuguese)
at the repository root from compat.json.

compat.json is the single source: the app uses the same rules for the notices shown when
opening a program, the library badges and the Compatibility tab. English comes from the
top-level fields; Portuguese from each rule's "pt" object (falling back to English).
Usage: python3 compat-md.py [output-dir]   (default: the repository root)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..")

FILES = {"en": "COMPATIBILITY.md", "pt": "COMPATIBILIDADE.md"}
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
COMPONENT = {"dotnet48": ".NET 4.8", "winrt-metadata": "WinRT", "webview2": "WebView2"}
# ordem das categorias (pelo nome em inglês, que é a chave)
ORDER = ["Productivity", "Engineering & CAD", "Design & Media", "Business & Finance", "Development & IT",
         "Science & Education", "Games", "Utilities", "Not supported", "By technology"]

TEXT = {
    "en": {
        "badge": {"verified": "✅ Verified", "funciona": "🟢 Works",
                  "parcial": "🟡 Partial", "nao-funciona": "❌ Doesn't work", "nao-testado": "⚪ Untested (wanted)"},
        "switch": "**English** · [Português](COMPATIBILIDADE.md)",
        "title": "# WinApps Compatibility",
        "count": "**{ok} programs working**, {ver} verified with WinApps fixes.  ",
        "legend": ["✅ Verified = tested end to end, with WinApps fixes · 🟢 Works = tested ·",
                   "🟡 Partial · ❌ Doesn't work · not listed = ⚪ Untested."],
        "note": ["> Generated from [`winapps/compat.json`](winapps/compat.json) by `winapps/compat-md.py` (don't edit by hand).",
                 "> The app shows the same list, with search, in the **Compatibility** tab."],
        "head": "| Program | Status | Category | Tested | Summary | Fixes |",
        "details": "## Details",
        "needs": "**Needs:** {list} (already included in the WinApps environment)",
        "fixes": "**WinApps fixes:**",
    },
    "pt": {
        "badge": {"verified": "✅ Verificado", "funciona": "🟢 Funciona",
                  "parcial": "🟡 Parcial", "nao-funciona": "❌ Não funciona", "nao-testado": "⚪ Não testado (procurado)"},
        "switch": "[English](COMPATIBILITY.md) · **Português**",
        "title": "# Compatibilidade do WinApps",
        "count": "**{ok} programas funcionando**, {ver} verificados com correções próprias.  ",
        "legend": ["✅ Verificado = testado de ponta a ponta, com correções do WinApps · 🟢 Funciona = testado ·",
                   "🟡 Parcial · ❌ Não funciona · fora da tabela = ⚪ Não testado."],
        "note": ["> Gerado de [`winapps/compat.json`](winapps/compat.json) por `winapps/compat-md.py` (não edite à mão).",
                 "> O app mostra a mesma lista na aba **Compatibilidade**, com busca."],
        "head": "| Programa | Situação | Categoria | Testado | Resumo | Correções |",
        "details": "## Detalhes",
        "needs": "**Precisa de:** {list} (já incluídos no ambiente do WinApps)",
        "fixes": "**Correções do WinApps:**",
    },
}


def loc(rule, key, lang, default=""):
    if lang == "pt" and key in (rule.get("pt") or {}):
        return rule["pt"][key]
    return rule.get(key, default)


def badge(r, lang):
    b = TEXT[lang]["badge"]
    return b["verified"] if r.get("verified") else b.get(r.get("status", ""), r.get("status", ""))


def tested(r, lang):
    d = r.get("tested") or ""
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", d)   # DD/MM/AAAA
    if lang == "en" and m:
        return f"{MONTHS[int(m.group(2)) - 1]} {int(m.group(1))}, {m.group(3)}"
    return d


def esc(s):
    return (s or "").replace("|", "\\|").replace("\n", " ")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def render(rules, lang):
    T = TEXT[lang]
    n_ok = sum(1 for r in rules if r.get("kind") == "app" and r.get("status") == "funciona")
    n_ver = sum(1 for r in rules if r.get("verified"))
    out = [T["switch"], "", T["title"], "", T["count"].format(ok=n_ok, ver=n_ver), *T["legend"], "",
           *T["note"], "", T["head"], "|---|---|---|---|---|:---:|"]
    for r in rules:
        name = loc(r, "name", lang)
        fixes = len(loc(r, "fixes", lang, []))
        out.append(f"| [{esc(name)}](#{slug(name)}) | {badge(r, lang)} | {esc(loc(r, 'category', lang))} | "
                   f"{esc(tested(r, lang)) or '—'} | {esc(loc(r, 'summary', lang))} | {fixes or '—'} |")
    out += ["", T["details"], ""]
    for r in rules:
        name = loc(r, "name", lang)
        out.append(f'<details id="{slug(name)}"><summary><b>{name}</b> — {badge(r, lang)}</summary>')
        out += ["", loc(r, "why", lang)]
        alt = loc(r, "alt", lang)
        if alt:
            out += ["", f"💡 {alt}"]
        if r.get("needs"):
            out += ["", T["needs"].format(list=", ".join(COMPONENT.get(n, n) for n in r["needs"]))]
        fixes = loc(r, "fixes", lang, [])
        if fixes:
            out += ["", T["fixes"]]
            out += [f"- {x}" for x in fixes]
        out += ["", "</details>", ""]
    return "\n".join(out)


def main():
    with open(os.path.join(HERE, "compat.json"), encoding="utf-8") as f:
        rules = json.load(f)["rules"]
    rules.sort(key=lambda r: ORDER.index(r["category"]) if r.get("category") in ORDER else 99)
    for lang, fname in FILES.items():
        path = os.path.normpath(os.path.join(OUT_DIR, fname))
        with open(path, "w", encoding="utf-8") as f:
            f.write(render(rules, lang))
        print(f"generated: {path}")


if __name__ == "__main__":
    main()
