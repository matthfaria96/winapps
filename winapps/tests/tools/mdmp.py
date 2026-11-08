#!/usr/bin/env python3
"""mdmp.py <arquivo.dmp> — resumo de um minidump do Chromium: exceção, módulo+offset, tipo do processo."""
import struct, sys, re
d = open(sys.argv[1], "rb").read()
if len(d) < 32: sys.exit("vazio")
_, _, n, rva = struct.unpack_from("<IIII", d, 0)
st = {}
for i in range(n):
    t, size, r = struct.unpack_from("<III", d, rva + i * 12); st[t] = (r, size)
def rstr(r):
    k = struct.unpack_from("<I", d, r)[0]; return d[r+4:r+4+k].decode("utf-16-le", "ignore")
mods = []
if 4 in st:
    r, _ = st[4]; k = struct.unpack_from("<I", d, r)[0]
    for i in range(k):
        b, s = struct.unpack_from("<QI", d, r + 4 + i * 108)
        mods.append((b, s, rstr(struct.unpack_from("<I", d, r + 4 + i * 108 + 20)[0]).split("\\")[-1]))
def where(a):
    m = [f"{nm}+0x{a-b:x}" for b, s, nm in mods if b <= a < b + s]; return m[0] if m else "?"
if 6 in st:
    r, _ = st[6]
    code, flags, rec, addr = struct.unpack_from("<IIQQ", d, r + 8)
    print(f"exceção 0x{code:08x} em {where(addr)}")
    # pilha bruta: endereços de retorno plausíveis no contexto da thread que falhou
for k in (b"ptype",):
    i = d.find(k)
    if i >= 0: print(re.sub(rb"[^ -~]+", b" ", d[i:i+40]).decode())
