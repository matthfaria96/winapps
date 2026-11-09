#!/bin/bash
# Recompila os módulos do motor (Wine Staging 11.21 do Gcenx) que têm correções
# nossas e troca no WinApps, guardando os originais (*.orig).
# Patches: gerais em patches/ e de cada programa em programas/<nome>/patches/; são
# aplicados todos juntos, na ordem do número (0002…0020), não importa a pasta.
#
#   0002  ole32.dll   [rubinot] RevokeDragDrop em janela de outro processo (RubinOT 32-bit x WebView2 64-bit)
#   0003  win32u.so   barra de menu presa na largura antiga (Notepad++ com 2 itens por linha)
#   0004  winemac.so  menu do programa na barra de menus do macOS (opção NativeMenuBar)
#   0005  winemac.so  tabela macdrv_functions para o DXMT (Direct3D 10/11 -> Metal)
#   0006  win32u/winemac  janelas-filhas de OUTRO processo (WebView2: CAContext/CALayerHost)
#   0007  dcomp.dll   DirectComposition liga swapchains de composição do DXMT à janela
#   0008  ntdll.so    [power-bi] NtImpersonateAnonymousToken + memória real no macOS (Power BI/msmdsrv)
#   0009  secur32.dll [power-bi] Impersonate/Revert/QuerySecurityContextToken (login Windows local)
#   0010  winemac.so  filhas remotas acompanham mudanças/reparent da janela-mãe
#   0011  winemac.so  processos auxiliares (ex.: WebView2) sem ícone próprio no Dock
#   0012  winemac.so  filhas remotas empilhadas na ordem do Windows (várias WebViews sobrepostas)
#   0013  winemac.so  compõe as filhas remotas mesmo sem a janela estar ativa (tela cinza)
#   0014  winemac.so  janelas com barra própria: sombra, redimensionar/encaixar no Mac, soltar maximizada
#   0015  winemac.so  barra de título do Mac sobre a barra própria + menus do programa por receita
#   0016  mshtml.dll  [power-bi] zoom pedido pelo programa relativo à escala de DPI do Gecko (login do Power BI cortado)
#   0017  ntdll.so    nomes próprios (WinApps/WinApps Server), motor como executável do app, idioma
#   0018  winecfg.exe título "Configurações do Windows"
#   0019  winemac.so  [rubinot] minimizar o RubinOT esconde o app (o cliente perde a imagem)
#   0020  winemac.so  superfície do DXMT acompanha o tamanho da janela; imagem esticada (RubinOT)
#
# Uso:  bash engine/build-engine.sh                        # compila e instala
#       bash engine/build-engine.sh --build-only           # só compila (para o vendor.sh)
#       bash engine/build-engine.sh --rebuild-module ntdll # reusa a árvore e recompila só um módulo
#       bash engine/build-engine.sh --restore              # volta para os originais
#
# Variáveis de ambiente:
#   ARCH=x86_64|arm64   lado Unix do motor (padrão x86_64, que roda via Rosetta).
#                       ARCH=arm64 é PREPARAÇÃO: o Wine 11.21 ainda não roda nativo em
#                       mac arm64 (falta o runtime arm64 do upstream); o script deixa
#                       pronto o alvo, o build só passa quando o Wine suportar. O lado
#                       Windows (PE) acompanha: aarch64. Para emular x86_64 PE depois,
#                       use  PE_ARCHS=aarch64,x86_64 ARCH=arm64. -> PE_ARCHS, PE32_MODULES
#   MACOSX_DEPLOYMENT_TARGET=10.15   versão mínima do macOS que o motor exige.
#                       NÃO baixar/alterar sem querer: módulo compilado com o SDK da
#                       máquina (ex.: 27.2) só carrega em macOS >= 27.2 (dyld recusa).
#   JOBS, WORK, INSTALL=0|1
set -euo pipefail

VER=11.21
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------- alvo do build
ARCH="${ARCH:-x86_64}"
DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
case "$ARCH" in
    x86_64)
        UNIX_ARCH=x86_64; PE_ARCH=x86_64; CC_ARCH=x86_64
        PE_ARCHS="${PE_ARCHS:-i386,x86_64}"
        PE_FILE_RE='PE32+.*x86-64'
        TRIPLE=x86_64-apple-darwin
        ;;
    arm64)
        UNIX_ARCH=aarch64; PE_ARCH=aarch64; CC_ARCH=arm64
        PE_ARCHS="${PE_ARCHS:-aarch64}"
        PE_FILE_RE='PE32+.*Aarch64'
        TRIPLE=                     # build nativo: sem --build/--host
        echo "!! ARCH=arm64: alvo preparado, mas o Wine $VER ainda não roda nativo em"
        echo "   macOS arm64 (runtime arm64 do upstream em desenvolvimento)."
        echo "   O configure/make provavelmente vai falhar; ver README do projeto."
        ;;
    *) echo "ARCH inválido: $ARCH (use x86_64 ou arm64)" >&2; exit 1 ;;
esac
export MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"

case ",$PE_ARCHS," in
    *,i386,*) PE32_ENABLED=1 ;;
    *)        PE32_ENABLED=0 ;;
esac
PE32_ARCH=i386
PE32_FILE_RE='PE32 executable.*Intel 80386'

MODULES="win32u winemac.drv ntdll"   # partes Unix (.so)
PE_MODULES="dcomp secur32 mshtml ole32"    # DLLs Windows (x86_64-windows/*.dll)
[ "$PE32_ENABLED" = 1 ] && PE32_MODULES="ole32"   # DLLs Windows 32-bit (i386-windows/*.dll)
PE32_MODULES="${PE32_MODULES:-}"     # 0002: RevokeDragDrop (RubinOT 32-bit)
PE_PROGRAMS="winecfg"                # programas Windows (x86_64-windows/*.exe)
WORK="${WORK:-$HOME/Library/Caches/WinApps/build-$VER}"
UNIX="$HOME/Library/Application Support/WinApps/motor/engine/Contents/Resources/wine/lib/wine/$UNIX_ARCH-unix"
[ -d "$UNIX" ] || UNIX="$(ls -d "$HOME/Library/Application Support/WinApps/wine/"*.app/Contents/Resources/wine/lib/wine/$UNIX_ARCH-unix 2>/dev/null | head -1)"
PE="$UNIX/../$PE_ARCH-windows"
PE32="$UNIX/../$PE32_ARCH-windows"
JOBS="$(sysctl -n hw.ncpu)"
EXTRA_EXPORTS='_macdrv_functions'   # 0005: tabela usada pelo DXMT (Direct3D -> Metal)

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mErro:\033[0m %s\n' "$*" >&2; exit 1; }
so_name() { local m="${1%.drv}"; echo "$m.so"; }          # winemac.drv -> winemac.so
rpaths() { otool -l "$1" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}'; }
linked() { otool -L "$1" | tail -n +3 | awk '{print $1}' | sort; }
minos() { otool -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/{f=1} f&&/^ *minos /{print $2; exit}'; }
# too_new <alvo> <referência>: verdadeiro se <alvo> exige macOS mais novo que <referência>
too_new() {
    awk -v a="$1" -v b="$2" 'BEGIN{
        n=split(a,x,"."); m=split(b,y,".");
        for(i=1;i<=(n>m?n:m);i++){ if(x[i]+0>y[i]+0) exit 0; if(x[i]+0<y[i]+0) exit 1 }
        exit 1
    }'
}

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
# --rebuild-module reusa a árvore já preparada (não baixa nem reaplica patches)
REBUILD=0
if [ "${1:-}" = "--rebuild-module" ]; then REBUILD=1; shift; fi

if [ "$REBUILD" = 0 ]; then
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
# patches/NNNN-*.patch + programas/*/patches/NNNN-*.patch, ordenados pelo nome do arquivo
for p in $(for f in "$HERE"/patches/[0-9][0-9][0-9][0-9]-*.patch "$HERE"/programas/*/patches/[0-9][0-9][0-9][0-9]-*.patch; do
               [ -f "$f" ] && printf '%s %s\n' "$(basename "$f")" "$f"; done | sort | cut -d' ' -f2-); do
    say "Aplicando $(basename "$p")"
    ( cd src && patch -p1 --forward <"$p" >/dev/null ) || die "patch não aplicou: $p"
done

# ---------------------------------------------------------------- compilação
# As ferramentas da Apple são só arm64: o clang nativo gera x86_64 e o configure
# é informado de que o sistema é x86_64 (os auxiliares do build rodam via Rosetta).
say "Configurando ($ARCH, macOS >= $DEPLOY_TARGET, PE: $PE_ARCHS)…"
cd src
./configure --enable-archs="$PE_ARCHS" ${TRIPLE:+--build=$TRIPLE} ${TRIPLE:+--host=$TRIPLE} \
    --disable-tests --without-x \
    CC="clang -arch $CC_ARCH" \
    FREETYPE_CFLAGS="-I$FT_INC" FREETYPE_LIBS="-lfreetype" \
    ac_cv_lib_soname_freetype=libfreetype.6.dylib \
    ac_cv_lib_soname_vulkan=libvulkan.1.dylib \
    >"$WORK/configure.log" 2>&1 || die "configure falhou (veja $WORK/configure.log)"

targets=""
for m in $MODULES; do targets="$targets dlls/$m/$(so_name "$m")"; done
for m in $PE_MODULES; do targets="$targets dlls/$m/$PE_ARCH-windows/$m.dll"; done
for m in $PE32_MODULES; do targets="$targets dlls/$m/$PE32_ARCH-windows/$m.dll"; done
for m in $PE_PROGRAMS; do targets="$targets programs/$m/$PE_ARCH-windows/$m.exe"; done
say "Compilando:$targets"
make -j"$JOBS" $targets >"$WORK/make.log" 2>&1 || die "make falhou (veja $WORK/make.log)"
else
    # ------------------------------------------------------------ rebuild de módulo
    [ $# -gt 0 ] || die "uso: --rebuild-module <módulo>…  (ex.: --rebuild-module ntdll winemac.drv)"
    [ -d "$WORK/src" ] || die "árvore não encontrada em $WORK/src (rode o build completo antes)"
    cd "$WORK/src"
    say "Recompilando ($ARCH, macOS >= $DEPLOY_TARGET): $*"
    for m in "$@"; do
        so="$(so_name "$m")"
        # força recompilar o módulo inteiro: só o .so não basta, os .o continuam com
        # o deployment target antigo e o make não sabe que a variável de ambiente mudou
        find "dlls/$m" \( -name '*.c' -o -name '*.h' -o -name '*.idl' \) -exec touch {} +
        rm -f "dlls/$m/$so" "dlls/$m"/*.o
    done
    targets=""
    for m in "$@"; do targets="$targets dlls/$m/$(so_name "$m")"; done
    make -j"$JOBS" $targets >"$WORK/make-rebuild.log" 2>&1 || die "make falhou (veja $WORK/make-rebuild.log)"
fi

# ---------------------------------------------------------------- conferências e instalação
install_module() {  # install_module <módulo>
    local m="$1" so new orig rp ref want have
    so="$(so_name "$m")"
    new="$WORK/src/dlls/$m/$so"
    orig="$UNIX/$so"; [ -f "$UNIX/$so.orig" ] && orig="$UNIX/$so.orig"

    say "Conferindo $so com o original…"
    lipo -archs "$new" | grep -qw "$CC_ARCH" || die "$so não é $CC_ARCH"
    # mesmo "install name", mesmas referências e mesmos rpaths do original
    install_name_tool -id "$(otool -D "$orig" | tail -1)" "$new" 2>/dev/null
    for ref in $(linked "$new"); do
        case "$ref" in /*|@*) ;; *) install_name_tool -change "$ref" "@rpath/$ref" "$new" 2>/dev/null ;; esac
    done
    for rp in $(rpaths "$orig"); do
        rpaths "$new" | grep -x "$rp" >/dev/null || install_name_tool -add_rpath "$rp" "$new"
    done
    codesign --force -s - "$new" >/dev/null 2>&1

    # o módulo não pode exigir um macOS mais novo que o original: dyld recusa carregar
    # um .so cujo minos é maior que a versão do sistema (era o caso ao recompilar com
    # 'make' na mão sem MACOSX_DEPLOYMENT_TARGET: clang usa a versão do SDK, ex. 27.2)
    want="$(minos "$orig")"; have="$(minos "$new")"
    [ -n "$have" ] || die "$so sem LC_BUILD_VERSION (não sei o deployment target)"
    if [ -n "$want" ] && too_new "$have" "$want"; then
        die "$so exige macOS $have, mas o original exige $want (export MACOSX_DEPLOYMENT_TARGET=$want)"
    fi
    say "  deployment target: $have (original: ${want:-?})"

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
    local m="$1" new="$WORK/src/dlls/$1/$PE_ARCH-windows/$1.dll"
    file "$new" | grep -q "$PE_FILE_RE" || die "$m.dll não é PE $PE_ARCH"
    [ "$(dd if="$new" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ] || die "$m.dll não está marcada como builtin"
    [ -f "$PE/$m.dll.orig" ] || cp "$PE/$m.dll" "$PE/$m.dll.orig"
    cp "$new" "$PE/$m.dll.new" && mv -f "$PE/$m.dll.new" "$PE/$m.dll"
    say "$m.dll instalado (original em $m.dll.orig)."
}

install_pe32_module() {  # install_pe32_module <módulo>  (DLL "builtin" 32-bit)
    local m="$1" new="$WORK/src/dlls/$1/$PE32_ARCH-windows/$1.dll"
    file "$new" | grep -q "$PE32_FILE_RE" || die "$m.dll (32-bit) não é PE $PE32_ARCH"
    [ "$(dd if="$new" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ] || die "$m.dll (32-bit) não está marcada como builtin"
    [ -d "$PE32" ] || die "pasta $PE32_ARCH-windows do motor não encontrada"
    [ -f "$PE32/$m.dll.orig" ] || cp "$PE32/$m.dll" "$PE32/$m.dll.orig"
    cp "$new" "$PE32/$m.dll.new" && mv -f "$PE32/$m.dll.new" "$PE32/$m.dll"
    say "$m.dll (32-bit) instalado (original em $m.dll.orig)."
}

if [ "$REBUILD" = 1 ]; then
    for m in "$@"; do INSTALL="${INSTALL:-0}" install_module "$m"; done
    say "Recompilado e conferido (INSTALL=${INSTALL:-0}). vendor.sh copia daqui."
    exit 0
fi

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
    new="$WORK/src/programs/$m/$PE_ARCH-windows/$m.exe"
    [ -f "$PE/$m.exe.orig" ] || cp "$PE/$m.exe" "$PE/$m.exe.orig"
    cp "$new" "$PE/$m.exe.new" && mv -f "$PE/$m.exe.new" "$PE/$m.exe" && say "$m.exe instalado"
done

say "Pronto! Feche e abra os programas Windows para usar a versão nova."
