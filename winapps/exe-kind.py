#!/usr/bin/env python3
"""Tells whether a Windows file is an INSTALLER or a PORTABLE program.

Usage: python3 -I exe-kind.py file.exe
Prints one line:  installer<TAB>reason   or   portable<TAB>reason
(also --name, --compat, --needs, --clr, --mac-menu, --burn-msis, --gui-only)

Human-readable text follows WINAPPS_UI_LANG ("en"/"pt"); without it, the Mac's
first preferred language (pt* -> Portuguese, anything else -> English).
"""
import os
import re
import sys


def ui_lang():
    """Idioma das mensagens: "pt" ou "en" (padrão)."""
    v = os.environ.get("WINAPPS_UI_LANG", "")
    if not v:
        try:
            import subprocess
            out = subprocess.run(["/usr/bin/defaults", "read", "-g", "AppleLanguages"],
                                 capture_output=True, text=True, timeout=5).stdout
            v = next((ln.strip(' ",') for ln in out.splitlines()[1:] if ln.strip(' ",()')), "")
        except Exception:  # noqa: BLE001
            v = ""
    return "pt" if v.lower().startswith("pt") else "en"


LANG = ui_lang()


def tr(en, pt):
    return pt if LANG == "pt" else en


def loc(rule, key, default=""):
    """Campo de uma regra do compat.json no idioma da interface: rule["pt"][key] em
    português (se existir), senão o campo principal (inglês)."""
    if LANG == "pt":
        pt = rule.get("pt") or {}
        if key in pt:
            return pt[key]
    return rule.get(key, default)

HEAD = 8 * 1024 * 1024  # as assinaturas ficam no começo do arquivo

# (padrão em bytes, nome amigável) — ordem importa: o primeiro que bater ganha
SIGNATURES = [
    (b"Nullsoft Install System", "NSIS"),
    (b"NullsoftInst", "NSIS"),
    (b"InnoSetupLdrWindow", "Inno Setup"),
    (b"Inno Setup Setup Data", "Inno Setup"),
    (b"JR.Inno.Setup", "Inno Setup"),
    (b".wixburn", "WiX/Burn"),
    (b"InstallShield", "InstallShield"),
    (b"Advanced Installer", "Advanced Installer"),
    (b"SquirrelSetup", "Squirrel"),
    (b"Setup Factory", "Setup Factory"),
    (b"Wise Installation", "Wise"),
    (b"7zS.sfx", "7-Zip SFX"),
    (b";!@Install@!UTF-8!", "7-Zip SFX"),
]

NAME_HINT = re.compile(r"(setup|install|instal|installer|instalador)", re.I)


def utf16(s):
    return s.encode("utf-16-le")


def file_description(data):
    """Lê o valor de FileDescription do VERSIONINFO (UTF-16, alinhado em 4 bytes)."""
    key = utf16("FileDescription\0")
    i = data.find(key)
    if i < 0:
        return ""
    j = i + len(key)
    while j < len(data) and j % 4:  # padding até o próximo múltiplo de 4
        j += 1
    end = j
    while end + 1 < len(data) and data[end:end + 2] != b"\0\0" and end - j < 512:
        end += 2
    return data[j:end].decode("utf-16-le", "ignore").strip()


def version_string(data, key):
    """Valor de um campo do VERSIONINFO (UTF-16), ex.: ProductName.

    Cada campo é uma estrutura String {wLength, wValueLength, wType=1, szKey, valor};
    confere esse cabeçalho para não confundir com o mesmo texto em outro lugar do .exe."""
    k = utf16(key + "\0")
    i = data.find(k)
    while i >= 0:
        if i >= 6:
            length, vlen, typ = (int.from_bytes(data[i - 6 + n:i - 4 + n], "little") for n in (0, 2, 4))
            if typ == 1 and 0 < vlen < 512 and length >= 6 + len(k) + vlen * 2 - 4:
                j = i + len(k)
                while j % 4:  # padding até o próximo múltiplo de 4 (alinhamento da seção)
                    j += 1
                val = data[j:j + vlen * 2].decode("utf-16-le", "ignore")
                return val.split("\0")[0].strip()
        i = data.find(k, i + 2)
    return ""


def find_rule(path, rules_path):
    """Primeira regra do compat.json que bate com o arquivo (o dicionário cru), ou None."""
    import json, mmap, re
    with open(rules_path, encoding="utf-8") as f:
        rules = json.load(f)["rules"]
    name = os.path.basename(path)
    with open(path, "rb") as f:
        head = f.read(HEAD)
        try:
            body = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        except ValueError:
            body = head
        product = " | ".join(v for v in (version_string(head, k) for k in
                             ("ProductName", "FileDescription", "CompanyName", "InternalName")) if v)
        for rule in rules:
            m = rule.get("match", {})
            hit = False
            if "file" in m and re.search(m["file"], name, re.I):
                hit = True
            if not hit and "product" in m and product and re.search(m["product"], product, re.I):
                hit = True
            if not hit and "content" in m:
                limit = min(len(body), 256 * 1024 * 1024)   # instaladores enormes: só os 256 MB iniciais
                if re.search(m["content"].encode(), body[:limit] if limit < len(body) else body):
                    hit = True
            if hit:
                return rule
    return None


def compat(path, rules_path):
    """Aviso de compatibilidade (textos no idioma da interface) da primeira regra que
    bate com o arquivo, ou None. "rule" = nome principal (inglês) da regra: chave estável
    para casar com o compat.json, igual em qualquer idioma."""
    rule = find_rule(path, rules_path)
    if rule is None:
        return None
    r = {k: loc(rule, k) for k in ("name", "status", "why", "alt", "tested", "category", "kind", "summary")}
    r["status"], r["tested"], r["kind"] = rule.get("status", ""), rule.get("tested", ""), rule.get("kind", "")
    r["rule"] = rule.get("name", "")
    r["needs"] = " ".join(rule.get("needs", []))
    r["verified"] = "1" if rule.get("verified") else ""
    r["fixes"] = "; ".join(loc(rule, "fixes", []))
    return r


GENERIC_EXE = {"app", "main", "launcher", "game", "start", "client", "program", "run"}


def app_name(path, rules_path):
    """Nome amigável para o atalho: 'app_name' da regra do compat.json, senão o
    ProductName do .exe (sem ®/™ e sem o nome da empresa na frente), senão o nome
    do arquivo (ou da pasta, se o .exe tiver nome genérico)."""
    if os.path.isfile(rules_path):
        rule = find_rule(path, rules_path)
        if rule and loc(rule, "app_name"):
            return loc(rule, "app_name")
    base = os.path.splitext(os.path.basename(path))[0]
    # nome do arquivo sem versão/arquitetura: "SumatraPDF-3.6.1-64" → "SumatraPDF"
    clean = re.sub(r"([-_ .]?(v?\d+([._]\d+)+|x64|x86|amd64|win64|win32|64bit|32bit|64|32|portable|setup))+$",
                   "", base, flags=re.I) or base
    try:
        with open(path, "rb") as f:
            head = f.read(HEAD)
            if not version_string(head, "ProductName") and os.path.getsize(path) <= 256 * 1024 * 1024:
                f.seek(0)
                head = f.read()   # recursos no fim de executáveis grandes
        product = re.sub(r"[®™©]|\(R\)|\(TM\)", "", version_string(head, "ProductName")).strip()
        product = re.sub(r"\s+(suite|portable|for windows|\(?(x64|64-bit|32-bit)\)?)$", "", product, flags=re.I).strip()
        company = version_string(head, "CompanyName").split(" ")[0]
        if company and product.lower().startswith(company.lower() + " "):
            product = product[len(company) + 1:].strip()
        if (product and len(product) <= 32 and not NAME_HINT.search(product)
                and not re.search(r"operating system|^windows$|^wine$", product, re.I)):
            return product.replace("/", "-").replace(":", "-")
    except OSError:
        pass
    if clean.lower() in GENERIC_EXE:
        folder = os.path.basename(os.path.dirname(os.path.abspath(path)))
        if folder:
            return folder
    return clean


def burn_msis(manifest_path):
    """Pacotes .msi embutidos num instalador WiX Burn, na ordem da instalação.

    Lê o manifesto do pacote (arquivo "0" do 1º cabinet) e devolve linhas
    "<id no cabinet>\t<nome do .msi>\t<sha1>". Só para pacotes com interface .NET
    (mbahost.dll), que travam no Wine; nos outros, o instalador normal funciona."""
    import xml.etree.ElementTree as ET
    root = ET.parse(manifest_path).getroot()
    ns = root.tag.split("}")[0] + "}" if root.tag.startswith("{") else ""
    payloads = {p.get("Id"): p for p in root.iter(ns + "Payload")}
    if not any(p.get("FilePath", "").lower() == "mbahost.dll" for p in payloads.values()):
        return []
    out = []
    for pkg in root.iter(ns + "MsiPackage"):
        for ref in pkg.iter(ns + "PayloadRef"):
            p = payloads.get(ref.get("Id"))
            if (p is not None and p.get("Packaging") == "embedded" and p.get("Container")
                    and p.get("FilePath", "").lower().endswith(".msi")):
                out.append((p.get("SourcePath"), os.path.basename(p.get("FilePath").replace("\\", "/")),
                            (p.get("Hash") or "").lower()))
    return out


def classify(path):
    name = os.path.basename(path)
    if name.lower().endswith(".msi"):
        return "installer", tr("MSI package", "pacote MSI")
    with open(path, "rb") as f:
        data = f.read(HEAD)
    if data[:2] != b"MZ":
        return "portable", tr("not a standard Windows executable", "não é um executável Windows padrão")

    for sig, label in SIGNATURES:
        if sig in data:
            return "installer", tr(f"{label} installer", f"instalador {label}")

    desc = file_description(data)
    if desc and NAME_HINT.search(desc):
        return "installer", tr(f"file description: \"{desc}\"", f"descrição do arquivo: \"{desc}\"")

    if NAME_HINT.search(name):
        return "installer", tr("the file name says it's an installer", "o nome do arquivo indica instalador")

    if b'level="requireAdministrator"' in data or b"level='requireAdministrator'" in data:
        return "installer", tr("asks for administrator rights (typical of installers)",
                               "pede permissão de administrador (típico de instalador)")

    return "portable", tr("no sign of an installer", "nenhum sinal de instalador encontrado")


def is_console(path):
    """True se o .exe é de linha de comando (PE subsystem 3 = WINDOWS_CUI)."""
    try:
        with open(path, "rb") as f:
            data = f.read(4096)
        pe = int.from_bytes(data[0x3C:0x40], "little")
        if data[:2] != b"MZ" or data[pe:pe + 4] != b"PE\0\0":
            return False
        subsystem = int.from_bytes(data[pe + 24 + 68:pe + 24 + 70], "little")
        return subsystem == 3
    except (OSError, ValueError):
        return False


def clr_header(data):
    """True se o executável é .NET (diretório 14 = COM descriptor/CLR preenchido)."""
    try:
        pe = int.from_bytes(data[0x3C:0x40], "little")
        if data[:2] != b"MZ" or data[pe:pe + 4] != b"PE\0\0":
            return False
        opt = pe + 24
        magic = int.from_bytes(data[opt:opt + 2], "little")
        ddir = opt + (96 if magic == 0x10B else 112)
        rva = int.from_bytes(data[ddir + 14 * 8:ddir + 14 * 8 + 4], "little")
        return rva != 0
    except ValueError:
        return False


def needs(path):
    """Componentes de que o programa/instalador precisa além do que o motor já tem.

    - .NET moderno (6/7/8/9): <programa>.runtimeconfig.json ao lado do .exe
    - .NET Framework com WPF (o Wine Mono não tem WPF): .NET Framework 4.8
    - instaladores que exigem o .NET Framework (ex.: Power BI): .NET Framework 4.8
    """
    import json, re
    found = []
    base, _ = os.path.splitext(path)
    cfg = base + ".runtimeconfig.json"
    if os.path.isfile(cfg):
        try:
            with open(cfg, encoding="utf-8-sig") as f:
                opts = json.load(f).get("runtimeOptions", {})
            fws = opts.get("frameworks") or [opts.get("framework", {})]
            for fw in fws:
                name, ver = fw.get("name", ""), fw.get("version", "")
                major = ver.split(".")[0]
                if major in ("6", "7", "8", "9"):
                    found.append(("dotnetdesktop" if "WindowsDesktop" in name else "dotnet") + major)
        except (OSError, ValueError):
            pass
    with open(path, "rb") as f:
        data = f.read(HEAD)
    if clr_header(data) and not found:
        with open(path, "rb") as f:
            whole = f.read()
        if b"PresentationFramework" in whole or b"PresentationCore" in whole:
            found.append("dotnet48")
    elif re.search(rb"NETFRAMEWORK45|NetFx4[5-8]|NetFx46[12]|NetFx47[12]|NetFx48|WIX_IS_NETFRAMEWORK", data):
        found.append("dotnet48")
    return sorted(set(found))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--compat":
        import json
        rules = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compat.json")
        r = compat(sys.argv[2], rules) if os.path.isfile(rules) else None
        print(json.dumps(r, ensure_ascii=False) if r else "")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--clr":
        with open(sys.argv[2], "rb") as f:
            print("yes" if clr_header(f.read(4096)) else "no")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--burn-msis":
        for src, name, sha in burn_msis(sys.argv[2]):
            print(f"{src}\t{name}\t{sha}")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--mac-menu":
        # receita de menus do Mac ("Menu:Item=ctrl+s;-;…||…") para o motor (MacMenu)
        rules = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compat.json")
        rule = find_rule(sys.argv[2], rules) if os.path.isfile(rules) else None
        if rule:
            menus = []
            for m in loc(rule, "mac_menu", []):
                items = ["-" if it == "-" else f"{it[0]}={it[1]}" for it in m.get("items", [])]
                menus.append(m["title"] + ":" + ";".join(items))
            print("||".join(menus))
            if rule.get("titlebar_height"):
                print(f"TitleBarHeight={rule['titlebar_height']}")
            tb = loc(rule, "titlebar_buttons", None)
            if tb:
                side = lambda items: ";".join(f"{b[0]}={b[1]}@{b[2]}" if len(b) > 2 else f"{b[0]}={b[1]}" for b in items)
                print("TitleBarButtons=" + side(tb.get("left", [])) + "||" + side(tb.get("right", [])))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--name":
        rules = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compat.json")
        print(app_name(sys.argv[2], rules))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--needs":
        found = needs(sys.argv[2])
        rules = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compat.json")
        hit = compat(sys.argv[2], rules) if os.path.isfile(rules) else None
        if hit and hit.get("needs"):   # componentes exigidos pela regra (ex.: Power BI)
            found += [n for n in hit["needs"].split() if n not in found]
        print(" ".join(found))
        return 0
    if len(sys.argv) == 2 and sys.argv[1] == "--gui-only":
        # filtro: lê caminhos da entrada e devolve só os programas com janela
        for line in sys.stdin:
            path = line.rstrip("\n")
            if path and not is_console(path):
                print(path)
        return 0
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    kind, why = classify(sys.argv[1])
    print(f"{kind}\t{why}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print("portable\t" + tr(f"couldn't analyze it ({e})", f"não consegui analisar ({e})"))
        sys.exit(0)
