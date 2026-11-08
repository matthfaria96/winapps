#!/usr/bin/env python3
"""Extrai o ícone principal de um .exe/.dll do Windows e grava um .icns do macOS.

Uso: python3 -I exe-icon.py programa.exe saida.icns
Só usa a biblioteca padrão + `sips`/`iconutil` do macOS; se houver o
binário `icon-frame` ao lado (build.sh), o ícone ganha a placa branca do macOS. Sai com código != 0 se o
arquivo não tiver ícone.
"""
import os
import struct
import subprocess
import sys
import tempfile

RT_ICON, RT_GROUP_ICON = 3, 14


def read_resources(data):
    if data[:2] != b"MZ":
        raise ValueError("não é um executável Windows")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("cabeçalho PE inválido")
    coff = pe + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    ddir = opt + (96 if magic == 0x10B else 112)
    res_rva, res_size = struct.unpack_from("<II", data, ddir + 2 * 8)
    if not res_rva:
        raise ValueError("sem recursos")

    sections = []
    sec = opt + opt_size
    for i in range(nsec):
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, sec + i * 40 + 8)
        sections.append((va, max(vsize, rawsize), rawptr))

    def rva2off(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError("RVA fora das seções")

    base = rva2off(res_rva)

    def entries(off):
        n_named, n_id = struct.unpack_from("<HH", data, base + off + 12)
        for i in range(n_named + n_id):
            name, target = struct.unpack_from("<II", data, base + off + 16 + i * 8)
            yield name, target

    out = {}
    for type_id, t_off in entries(0):
        if type_id not in (RT_ICON, RT_GROUP_ICON) or not t_off & 0x80000000:
            continue
        for name_id, n_off in entries(t_off & 0x7FFFFFFF):
            node = n_off
            while node & 0x80000000:  # desce até a folha (idioma)
                node = next(entries(node & 0x7FFFFFFF))[1]
            rva, size = struct.unpack_from("<II", data, base + node)
            off = rva2off(rva)
            out.setdefault(type_id, []).append((name_id, data[off:off + size]))
    return out


def best_icon(data):
    res = read_resources(data)
    icons = dict(res.get(RT_ICON, []))
    groups = res.get(RT_GROUP_ICON, [])
    if not groups or not icons:
        raise ValueError("sem ícone")
    grp = groups[0][1]  # o primeiro grupo é o ícone do programa
    count = struct.unpack_from("<H", grp, 4)[0]
    best = None
    for i in range(count):
        w, h, colors, _, planes, bits, size, icon_id = struct.unpack_from("<BBBBHHIH", grp, 6 + i * 14)
        w = w or 256
        score = (w, bits)
        if icon_id in icons and (best is None or score > best[0]):
            best = (score, (w, h, colors, planes, bits, icons[icon_id]))
    if best is None:
        raise ValueError("ícone referenciado não encontrado")
    w, h, colors, planes, bits, blob = best[1]
    # monta um .ico com uma única imagem (a maior)
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack("<BBBBHHII", w % 256, h % 256, colors, 0, planes, bits, len(blob), 6 + 16)
    return header + entry + blob


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        ico = best_icon(f.read())
    framer = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon-frame")
    with tempfile.TemporaryDirectory() as tmp:
        ico_path = os.path.join(tmp, "icon.ico")
        png_path = os.path.join(tmp, "icon.png")
        with open(ico_path, "wb") as f:
            f.write(ico)
        run = lambda *a: subprocess.run(a, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run("/usr/bin/sips", "-s", "format", "png", ico_path, "--out", png_path)
        if os.access(framer, os.X_OK):
            # ícone no padrão do macOS: placa branca "squircle" com o ícone dentro
            big = os.path.join(tmp, "framed.png")
            iconset = os.path.join(tmp, "AppIcon.iconset")
            run(framer, png_path, big)
            os.mkdir(iconset)
            for s in (16, 32, 128, 256, 512):
                for mult, suffix in ((1, ""), (2, "@2x")):
                    px = str(s * mult)
                    run("/usr/bin/sips", "-z", px, px, big, "--out",
                        os.path.join(iconset, f"icon_{s}x{s}{suffix}.png"))
            run("/usr/bin/iconutil", "-c", "icns", iconset, "-o", dst)
        else:
            run("/usr/bin/sips", "-z", "256", "256", png_path)
            run("/usr/bin/sips", "-s", "format", "icns", png_path, "--out", dst)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f"exe-icon: {e}", file=sys.stderr)
        sys.exit(1)
