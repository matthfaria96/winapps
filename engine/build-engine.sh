#!/bin/bash
# Recompila os módulos do motor (Wine Staging 11.21 do Gcenx) que têm correções
# nossas em patches/ e troca no WinApps, guardando os originais (*.orig).
#
#   0002  ole32.dll   RevokeDragDrop em janela de outro processo (RubinOT 32-bit x WebView2 64-bit)
#   0003  win32u.so   barra de menu presa na largura antiga (Notepad++ com 2 itens por linha)
#   0004  winemac.so  menu do programa na barra de menus do macOS (opção NativeMenuBar)
#   0005  winemac.so  tabela macdrv_functions para o DXMT (Direct3D 10/11 -> Metal)
#   0006  win32u/winemac  janelas-filhas de OUTRO processo (WebView2: CAContext/CALayerHost)
#   0007  dcomp.dll   DirectComposition liga swapchains de composição do DXMT à janela
#   0008  ntdll.so    NtImpersonateAnonymousToken + memória real no macOS (Power BI/msmdsrv)
#   0009  secur32.dll Impersonate/Revert/QuerySecurityContextToken (login Windows local)
#   0010  winemac.so  filhas remotas acompanham mudanças/reparent da janela-mãe
#   0011  winemac.so  processos auxiliares (ex.: WebView2) sem ícone próprio no Dock
#   0012  winemac.so  filhas remotas empilhadas na ordem do Windows (várias WebViews sobrepostas)
#   0013  winemac.so  compõe as filhas remotas mesmo sem a janela estar ativa (tela cinza)
#   0014  winemac.so  janelas com barra própria: sombra, redimensionar/encaixar no Mac, soltar maximizada
#   0015  winemac.so  barra de título do Mac sobre a barra própria + menus do programa por receita
#   0016  mshtml.dll  zoom pedido pelo programa relativo à escala de DPI do Gecko (login do Power BI cortado)
#   0017  ntdll.so    nomes próprios (WinApps/WinApps Server), motor como executável do app, idioma
#   0018  winecfg.exe título "Configurações do Windows"
#   0020  winemac.so  superfície do DXMT acompanha o tamanho da janela; imagem esticada (RubinOT)
#
# Uso:  bash engine/build-engine.sh               # compila e instala
#       bash engine/build-engine.sh --build-only  # só compila (para o vendor.sh)
#       bash engine/build-engine.sh --restore     # volta para os originais
set -euo pipefail

VER=11.21
MODULES="win32u winemac.drv ntdll"   # partes Unix (.so)
PE_MODULES="dcomp secur32 mshtml ole32"    # DLLs Windows (x86_64-windows/*.dll)
PE32_MODULES="ole32"                 # DLLs Windows 32-bit (i386-windows/*.dll)
PE_PROGRAMS="winecfg"                # programas Windows (x86_64-windows/*.exe)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HOME/Library/Caches/WinApps/build-$VER}"
UNIX="$HOME/Library/Application Support/WinApps/motor/engine/Contents/Resources/wine/lib/wine/x86_64-unix"
[ -d "$UNIX" ] || UNIX="$(ls -d "$HOME/Library/Application Support/WinApps/wine/"*.app/Contents/Resources/wine/lib/wine/x86_64-unix 2>/dev/null | head -1)"
PE="$UNIX/../x86_64-windows"
PE32="$UNIX/../i386-windows"
JOBS="$(sysctl -n hw.ncpu)"
EXTRA_EXPORTS='_macdrv_functions'   # 0005: tabela usada pelo DXMT (Direct3D -> Metal)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mErro:\033[0m %s\n' "$*" >&2; exit 1; }
so_name() { local m="${1%.drv}"; echo "$m.so"; }          # winemac.drv -> winemac.so
rpaths() { otool -l "$1" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}'; }
linked() { otool -L "$1" | tail -n +3 | awk '{print $1}' | sort; }

[ -d "$UNIX" ] || die "motor não encontrado em $UNIX (rode 'winapps setup' antes)"

if [ "${1:-}" = "--restore" ]; then
    for m in $MODULES; do
        so="$(so_name "$m")"
        [ -f "$UNIX/$so.orig" ] && cp "$UNIX/$so.orig" "$UNIX/$so.new" && mv -f "$UNIX/$so.new" "$UNIX/$so" && say "$so original restaurado."
    done
    for m in $PE_MODULES; do
        [ -f "$PE/$m.dll.orig" ] && cp "$PE/$m.dll.orig" "$PE/$m.dll.new" && mv -f "$PE/$m.dll.new" "$PE/$m.dll" && say "$m.dll original restaurado."
    done
    for m in $PE32_MODULES; do
        [ -f "$PE32/$m.dll.orig" ] && cp "$PE32/$m.dll.orig" "$PE32/$m.dll.new" && mv -f "$PE32/$m.dll.new" "$PE32/$m.dll" && say "$m.dll (32-bit) original restaurado."
    done
    for m in $PE_PROGRAMS; do
        [ -f "$PE/$m.exe.orig" ] && cp "$PE/$m.exe.orig" "$PE/$m.exe.new" && mv -f "$PE/$m.exe.new" "$PE/$m.exe" && say "$m.exe original restaurado."
    done
    exit 0
fi

# ---------------------------------------------------------------- dependências
command -v brew >/dev/null || die "Homebrew não encontrado"
for f in bison flex freetype autoconf mingw-w64; do brew list "$f" >/dev/null 2>&1 || brew install "$f"; done
FT_INC="$(brew --prefix freetype)/include/freetype2"
export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$(brew --prefix mingw-w64)/bin:$PATH"

# ---------------------------------------------------------------- fontes
mkdir -p "$WORK"; cd "$WORK"
[ -f "wine-$VER.tar.xz" ]    || curl -fL -o "wine-$VER.tar.xz"    "https://dl.winehq.org/wine/source/11.x/wine-$VER.tar.xz"
[ -f "staging-$VER.tar.gz" ] || curl -fL -o "staging-$VER.tar.gz" "https://github.com/wine-staging/wine-staging/archive/refs/tags/v$VER.tar.gz"
# patch que o Gcenx aplica nos builds dele (Vulkan/MoltenVK)
[ -f mr11538.patch ]         || curl -fL -o mr11538.patch         "https://gitlab.winehq.org/wine/wine/-/merge_requests/11538.patch"

say "Preparando as fontes (Wine $VER + Staging + patches)…"
rm -rf src "wine-staging-$VER"
mkdir src && tar xf "wine-$VER.tar.xz" -C src --strip-components 1
tar xzf "staging-$VER.tar.gz"
python3 "wine-staging-$VER/staging/patchinstall.py" --all -d "$WORK/src" >staging.log 2>&1 \
    || die "falha ao aplicar o Wine Staging (veja $WORK/staging.log)"
( cd src && patch -p1 --forward <"$WORK/mr11538.patch" >/dev/null )
for p in "$HERE"/patches/000[2-9]-*.patch "$HERE"/patches/00[1-9][0-9]-*.patch; do
    [ -f "$p" ] || continue
    say "Aplicando $(basename "$p")"
    ( cd src && patch -p1 --forward <"$p" >/dev/null ) || die "patch não aplicou: $p"
done

# ---------------------------------------------------------------- compilação
# As ferramentas da Apple são só arm64: o clang nativo gera x86_64 e o configure
# é informado de que o sistema é x86_64 (os auxiliares do build rodam via Rosetta).
say "Configurando (x86_64)…"
cd src
export MACOSX_DEPLOYMENT_TARGET=10.15
./configure --enable-archs=i386,x86_64 --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
    --disable-tests --without-x \
    CC="clang -arch x86_64" \
    FREETYPE_CFLAGS="-I$FT_INC" FREETYPE_LIBS="-lfreetype" \
    ac_cv_lib_soname_freetype=libfreetype.6.dylib \
    ac_cv_lib_soname_vulkan=libvulkan.1.dylib \
    >"$WORK/configure.log" 2>&1 || die "configure falhou (veja $WORK/configure.log)"

targets=""
for m in $MODULES; do targets="$targets dlls/$m/$(so_name "$m")"; done
for m in $PE_MODULES; do targets="$targets dlls/$m/x86_64-windows/$m.dll"; done
for m in $PE32_MODULES; do targets="$targets dlls/$m/i386-windows/$m.dll"; done
for m in $PE_PROGRAMS; do targets="$targets programs/$m/x86_64-windows/$m.exe"; done
say "Compilando:$targets"
make -j"$JOBS" $targets >"$WORK/make.log" 2>&1 || die "make falhou (veja $WORK/make.log)"

# ---------------------------------------------------------------- conferências e instalação
install_module() {  # install_module <módulo>
    local m="$1" so new orig rp ref
    so="$(so_name "$m")"
    new="$WORK/src/dlls/$m/$so"
    orig="$UNIX/$so"; [ -f "$UNIX/$so.orig" ] && orig="$UNIX/$so.orig"

    say "Conferindo $so com o original…"
    lipo -archs "$new" | grep x86_64 >/dev/null || die "$so não é x86_64"
    # mesmo "install name", mesmas referências e mesmos rpaths do original
    install_name_tool -id "$(otool -D "$orig" | tail -1)" "$new" 2>/dev/null
    for ref in $(linked "$new"); do
        case "$ref" in /*|@*) ;; *) install_name_tool -change "$ref" "@rpath/$ref" "$new" 2>/dev/null ;; esac
    done
    for rp in $(rpaths "$orig"); do
        rpaths "$new" | grep -x "$rp" >/dev/null || install_name_tool -add_rpath "$rp" "$new"
    done
    codesign --force -s - "$new" >/dev/null 2>&1

    # mesmas funções exportadas do original; extras só os previstos pelos nossos patches
    diff <(nm -gU "$orig" | awk '{print $3}' | sort) \
         <(nm -gU "$new" | awk '{print $3}' | grep -vxE "$EXTRA_EXPORTS" | sort) \
        >"$WORK/$so.exports.diff" || die "$so: funções exportadas diferentes (veja $WORK/$so.exports.diff)"
    diff <(linked "$orig") <(linked "$new") >"$WORK/$so.libs.diff" \
        || die "$so: bibliotecas ligadas diferentes (veja $WORK/$so.libs.diff)"
    diff <(rpaths "$orig") <(rpaths "$new") >/dev/null || die "$so: rpaths diferentes do original"
    for s in $(strings "$orig" | grep -E '^lib[A-Za-z0-9_.+-]+\.dylib$' | sort -u); do
        strings "$new" | grep -x "$s" >/dev/null || die "$so: não carrega $s como o original"
    done

    [ "${INSTALL:-1}" = 1 ] || { say "$so conferido."; return 0; }
    [ -f "$UNIX/$so.orig" ] || cp "$UNIX/$so" "$UNIX/$so.orig"
    cp "$new" "$UNIX/$so.new" && mv -f "$UNIX/$so.new" "$UNIX/$so"   # troca atômica
    say "$so instalado (original em $so.orig)."
}
install_pe_module() {  # install_pe_module <módulo>  (DLL "builtin" do Wine)
    local m="$1" new="$WORK/src/dlls/$1/x86_64-windows/$1.dll"
    file "$new" | grep -q 'PE32+.*x86-64' || die "$m.dll não é PE x86-64"
    [ "$(dd if="$new" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ] || die "$m.dll não está marcada como builtin"
    [ -f "$PE/$m.dll.orig" ] || cp "$PE/$m.dll" "$PE/$m.dll.orig"
    cp "$new" "$PE/$m.dll.new" && mv -f "$PE/$m.dll.new" "$PE/$m.dll"
    say "$m.dll instalado (original em $m.dll.orig)."
}

install_pe32_module() {  # install_pe32_module <módulo>  (DLL "builtin" 32-bit)
    local m="$1" new="$WORK/src/dlls/$1/i386-windows/$1.dll"
    file "$new" | grep -q 'PE32 executable.*Intel 80386' || die "$m.dll (32-bit) não é PE i386"
    [ "$(dd if="$new" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ] || die "$m.dll (32-bit) não está marcada como builtin"
    [ -d "$PE32" ] || die "pasta i386-windows do motor não encontrada"
    [ -f "$PE32/$m.dll.orig" ] || cp "$PE32/$m.dll" "$PE32/$m.dll.orig"
    cp "$new" "$PE32/$m.dll.new" && mv -f "$PE32/$m.dll.new" "$PE32/$m.dll"
    say "$m.dll (32-bit) instalado (original em $m.dll.orig)."
}
if [ "${1:-}" = "--build-only" ]; then
    # só ajusta install name/rpath/assinatura (o vendor.sh copia daqui)
    for m in $MODULES; do INSTALL=0 install_module "$m"; done
    say "Compilado em $WORK/src/dlls (não instalado)."
    exit 0
fi
for m in $MODULES; do install_module "$m"; done
for m in $PE_MODULES; do install_pe_module "$m"; done
for m in $PE32_MODULES; do install_pe32_module "$m"; done
for m in $PE_PROGRAMS; do
    new="$WORK/src/programs/$m/x86_64-windows/$m.exe"
    [ -f "$PE/$m.exe.orig" ] || cp "$PE/$m.exe" "$PE/$m.exe.orig"
    cp "$new" "$PE/$m.exe.new" && mv -f "$PE/$m.exe.new" "$PE/$m.exe" && say "$m.exe instalado"
done

say "Pronto! Feche e abra os programas Windows para usar a versão nova."
