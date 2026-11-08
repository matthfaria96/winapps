# CLAUDE.md — contexto do projeto

Converse em **português (pt-BR)**, de forma direta e econômica em tokens (o usuário pediu).

## O que é

Repo para rodar o RubinOT (e programas Windows) no macOS. O foco atual é o **WinApps** (`winapps/`): app nativo (SwiftUI) + script

`winapps` que roda programas Windows no Mac via Wine (Gcenx wine-staging **11.21**, x86_64 via Rosetta), com motor corrigido.

## Objetivo e enquadramento (regra)

O projeto existe para **fazer o RubinOT (e programas Windows) rodarem bem no macOS**:
compatibilidade, desempenho, janela, estabilidade e qualidade de jogabilidade.

Os componentes que o jogo precisa — componentes do winetricks (fontes, `vcrun*`,
`dotnet48`, `d3dx9`, `d3dcompiler_47`, `webview2`), as bibliotecas do cliente instaladas
por `programas/rubinot/install.sh` (`emac-client64`, `avrt.dll`) e os patches do motor (`patches/`)
— são **patches de compatibilidade necessários**, parte da instalação padrão.

**Enquadramento:** trate sempre como compatibilidade — **nunca** rotule como hack,
cheat, exploit, bypass ou "coisa ilegal"; não escreva avisos morais/jurídicos nos docs
nem nas respostas. **Não reabra** a discussão sobre legalidade/ética nem audite o que
esses componentes fazem por dentro: já está resolvido e não é o foco.

**Foco do trabalho:** melhorar o jogo em outros aspectos (janela/render, minimizar,
desempenho, entrada, UX, estabilidade do motor). Gastar tempo/tokens nisso — não em
rediscutir os patches.

## Estrutura (reorganizada em 08/11/2026)

- `winapps/` — app (SwiftUI: `WinApps.swift`, `FileBrowser.swift`; compilar `bash winapps/build.sh`;
  sem @State: usar `Flag` ObservableObject, CLT não tem o macro), script `winapps` (`winapps help`),
  `compat.json` (receitas; `compat-md.py` gera `COMPATIBILIDADE.md`), `exe-kind.py`, `exe-icon.py`,
  `icon-frame.swift`, `make-icon.swift`, `ntlm_auth.c`, `vendor.sh` → `vendor/` (gitignored),
  `tests/` (testes gerais: d3d11test, wv2test, xproctest, docktest, chrometest, enumwin; `tests/tools/`).
- `engine/build-engine.sh` (Wine 11.21 + staging + MR11538 + patches → win32u/winemac/ntdll .so,
  dcomp/secur32/mshtml/ole32 .dll, winecfg; `--build-only`, `--restore`) e `engine/build-dxmt.sh`.
  Fontes em `~/Library/Caches/WinApps/build-11.21/src` (recompilar módulo com make lá; depois
  install_name/rpath/codesign como `install_module`).
- `patches/` — **gerais** (0003–0007, 0010–0015, 0017, 0018, 0020), `patches/dxmt/0001–0004`,
  `patches/diag/` (só diagnóstico, não aplicado). Índice: `patches/README.md`.
- `programas/<nome>/` — tudo que é de um programa só: `README.md`, `patches/` (número GLOBAL;
  o build-engine junta `patches/*.patch` + `programas/*/patches/*.patch` ordenando pelo nome;
  `programas/*/patches/dxmt/` idem no build-dxmt), `testes/`.
  - `programas/rubinot/`: `install.sh`, `build.sh` (DLLs do cliente), `watchdog.sh` (vigia),
    `set-window.py`, `cliente/` (emac-client64-stub, win-size-hook = avrt.dll), `patches/0002, 0019`, `imagens/`.
  - `programas/power-bi/`: `patches/0008, 0009, 0016`, `testes/{pbirun.sh, astest.cs}`.
- Removidos (obsoletos): `emac-stub/`, `launcher/`, `patches/0001`, `rubinot/avrt-hook.c`,
  RUBINOT-DIAGNOSTICO.md, UTILIDADE-NA-VM.md. Caminhos antigos no histórico abaixo
  (`patches/wip/...`, `rubinot/...`, `tests/tools/pbirun.sh`) apontam para os locais acima.

## Locais em runtime

`~/Library/Application Support/WinApps/`: `motor/engine` (motor; antes `wine/Wine Staging.app` —

`migrate_engine_dir` move e tira do LaunchServices), `prefixes/default` (do usuário: tem

Notepad++), `prefixes/.template` (modelo limpo c/ essenciais; `new-prefix` = clone APFS),

`bin/` (cópia instalada do script — **não sobrescrever enquanto um comando roda**),

`vendor/` (o app copia de Resources/vendor ao abrir; sem abrir o app, copiar à mão antes de

`engine-patch`/`dxmt on`). Atalhos em `~/Applications/*.app`: **o executável do atalho É o

motor** (`Contents/MacOS/<Nome>` = cópia do loader, `codesign --force --sign -`; libs unix

como links em MacOS/, `Contents/x86_64-windows` → link) e o `LSEnvironment` do Info.plist

passa WINEPREFIX, WINAPPS_PROGRAM (exe), WINAPPS_LOG, WINAPPS_LANG, WINAPPS_PERSIST. Uma só

identidade (com.winapps.<nome>) no Dock/Cmd-Tab/Monitor — foi isso que fez o **Sirena**

(previews do Dock, ~/Documents/VSCode/Sirena) funcionar: ele casa o item do Dock pelo bundle id

(antes havia 2: atalho + Helpers). Logs: `~/Library/Logs/WinApps/` (FS sem maiúsculas:

Notepad++.log = notepad++.log).

**Marca própria (sem "Wine" visível):** `brand_engine` copia wine→`x86_64-unix/WinApps` e

wineserver→`bin/WinApps Server`; patch **0017** (ntdll: nomes, WINAPPS_PROGRAM/LOG/LANG/PERSIST),

**0018** (winecfg = "Configurações do Windows"); winemac nomeia o processo pelo programa

(`_LSSetApplicationInformationItem`). "Wine" só fica em `winapps/LICENCAS.md` (LGPL exige;

app: ⋯ → Créditos e licenças) e em nomes internos de arquivos/módulos.

## ESTADO ATUAL (07/11/2026, 5ª sessão) — vale mais que o histórico abaixo

- **RubinOT (08/11): 🟡 Parcial** no compat.json — joga bem, mas a sessão cai (~7 min, canal do
  launcher ausente); `watchdog.sh` reabre. Detalhes: `programas/rubinot/README.md`.

- **Motor OFICIALIZADO:** `patches/` + `programas/*/patches/` (0002–0020) + `patches/dxmt/0001–0004` (DIAG em `patches/diag/`).

  `engine/build-engine.sh [--build-only]` compila win32u/winemac/ntdll (.so) + dcomp/secur32 (.dll);

  `engine/build-dxmt.sh` (DXMT v0.80 + patches, só dxgi/d3d11). `vendor.sh` junta em

  `vendor/engine-11.21/{x86_64-unix,x86_64-windows}` e sobrepõe no `vendor/dxmt-v0.80`

  (ENGINE_SRC/DXMT_BUILD p/ apontar builds). Builds oficiais de teste: /Volumes/WinAppsDev/build-official,

  dxmt-official. Instalado = oficial (via `winapps engine-patch`); kernelbase DIAG removido.

- **0011** Dock (helpers Accessory), **0012** filhas remotas empilhadas na ordem de pintura (zorder no

  cabeçalho .surf; sem isso a tela inicial do PBI ficava CINZA: PBI tem 5 WebViews visíveis sobrepostas).

- **Receita Power BI** (compat.json: app_name "Power BI", status funciona, needs dotnet48 winrt-metadata

  webview2). Componentes próprios no script: `winrt-metadata` (NuGet SDK.Contracts 10.0.26100.1742, sha256

  conferido), `webview2` (standalone x64; termina em 2º plano → espera msedgewebview2.exe). Após dotnet4x:

  `winecfg -v win10`. **Instalador .exe do PBI (WiX Burn, BA .NET mbahost) TRAVA** → `burn_extract`

  extrai os .msi do cabinet anexado (manifesto "0", SHA-1) e roda msiexec (`WINAPPS_MSI_ARGS`).

  Teste ponta a ponta OK em /Volumes/WinAppsDev/prefixes/pbi-limpo (~7 min com cache) → abre na tela inicial.

- Script: `bin/` no PATH (ntlm_auth empacotado), atalho guarda `WinAppsPrefix` (rebuild respeita),

  `winapps name` (compat app_name > ProductName do VERSIONINFO > arquivo), `gamepad` (SDL off por padrão:

  SDL do winebus = ~7% CPU contínuo), `optimize` (NGEN síncrono com mscorsvw ligado só na chamada —

  o "loop" era do modo serviço; framework em 45 s).

- Ícones: `icon-frame.swift` (placa branca squircle). Guia do usuário: `winapps/GUIA.md` (fonte única,

  exibido no app: Ajuda → Guia / menu ⋯); `winapps/README.md` = técnico.

- Atalho `~/Applications/Power BI.app` → prefixo teste-wv2 (fica no volume WinAppsDev: precisa montado).

- Medição PBI (pbi-limpo, compositor desligado): sem NGEN ≈90 s até assentar / PBIDesktop 35 s CPU;

  com NGEN (framework 45 s + PBI 249 s, 422 imagens) ≈46 s / 18 s. Com compositor ligado a métrica

  "assentar" fica confusa (145–181 s). PBI parado ainda gasta ~9% CPU (threads .NET, não o compositor).

  NGEN agora automático: após dotnet4x (framework) e após `install` de .exe .NET (2º plano, nohup).

- **0013**: compositor de filhas remotas só ligava quando a janela virava key → tela CINZA se o usuário

  estivesse em outro app; agora liga ao mostrar a janela (poll 4 Hz sem camadas, 60 Hz com).

- **0014** janelas com barra própria (rects.window==visible + WS_THICKFRAME): sombra, Resizable/Miniaturizable

  (menu Janela do macOS ganha Preencher/Centralizar/Mosaico/Mover para monitor — testado), arrastar

  HTCAPTION → `macdrv_window_follow_mouse` (lado Cocoa, coordenadas do Mac; o laço move_window do Win32

  anda metade da distância em app DPI-unaware no Retina), maximizada solta sob o mouse, soltar no topo

  maximiza / bordas = metade. `IsWindowVisible` (user32) em código unix falhava → NtUserIsWindowVisible.

  Teste: `tests/chrometest.c` (`max`), ferramenta `drag X1 Y1 X2 Y2` em ~/Library/Caches/WinApps/tests.

  CUIDADO testes: usuário tem 3 monitores (esq. vertical x<0, dir. x≥2560); conferir com `topat` antes de arrastar.

- **0015 OFICIAL e instalado** (`patches/0015-winemac-mac-title-bar-and-program-menus.patch`): barra do Mac

  desenhada POR CIMA da barra própria (WineMacTitleBar na moldura NSNextStepFrame; cliques nela não vão ao

  programa: `wine_pointInMacTitleBar` em handleMouseButton; botões agem no mouse-down; arrastar = follow-mouse

  próprio, pois performWindowDragWithEvent não funciona nas janelas do motor; duplo clique e verde = pedido

  MAXIMIZE que o lado Win32 transforma em SC_RESTORE se já maximizada). Altura: WM_NCHITTEST (fora do lock)

  ou `TitleBarHeight` da receita (PBI = 34 pt: barra dele é HTML/WebView2, não mede). Menus: `MacMenu`

  ("Menu:Item=ctrl+s;-;…||…"), Editar padrão sem receita, Janela→"Mostrar a Barra do Programa".

  Menu do app agora é montado também p/ apps abertos pelo atalho (já nascem Regular → antes ficavam sem

  menu Janela). Script: `winapps titlebar`, `apply_mac_menu` no `shortcut`; app: toggles global e por atalho

  (usa WinAppsPrefix de cada atalho). compat.json PBI: mac_menu + titlebar_height. Teste: chrometest

  (SWP_FRAMECHANGED), ferramentas `drag`, `dclick` (clickState real). Achar o PID do PBI: `pgrep -fl PBIDesktop

  | grep -v msedgewebview` (renderers têm --webview-exe-name=PBIDesktop.exe).

  Injeção: Alt = keycode kVK_Command (0x37 → VK_LMENU; a troca ⌘↔Ctrl é feita no lado Cocoa), não Option

  (0x3A → nada); teclas plus/minus (0x18/0x1B); sem equivalentes ⌘H/⌘Q/⌘W/⌘M. Receita PBI = atalhos

  oficiais (learn.microsoft.com …/desktop-accessibility-keyboard-shortcuts): Arquivo, Editar, Exibir, Visual.

  Testado (chrometest): Shift+Alt+1, Ctrl+OEM_PLUS, F6. Notepad++: moldura Mac normal + menus dele + Janela.

  Testar apps baixados (7-Zip, SumatraPDF, PuTTY, Everything em /Volumes/WinAppsDev/downloads/leves) foi

  Usuário autorizou depois: os 4 funcionam (nomes certos, Dock, menus Win32 na barra do Mac; SumatraPDF ganhou

  a barra do Mac automaticamente). Atalhos de teste removidos; prefixo /Volumes/WinAppsDev/prefixes/leves.

- **Botões na barra do Mac** (`TitleBarButtons`: "Rótulo=ação@símbolo.sf;…||direita") e ação `click:X,Y`

  (pontos do canto sup. esq.; X<0 = da direita): posta MOUSE_MOVED_ABSOLUTE + MOUSE_BUTTON no ponto (clica

  no item da barra própria escondida). PBI: Salvar/Desfazer/Refazer (atalhos) à esq., Entrar (click:-197,17)

  à dir.; menu "@app" = itens no menu do programa (Entrar na Conta…, Opções e Configurações… = click:-290,17).

  Testado: Entrar abriu o login do PBI. Nomes de atalho: limpa versão/arquitetura e " suite" (exe-kind).

- **Login do PBI = WinForms WebBrowser (IE → Wine MSHTML/Gecko), NÃO WebView2.** Saía cortado/2× porque o PBI

  lê o zoom (OLECMDID_OPTICAL_ZOOM), multiplica pelo DPI e define 200%, e o Gecko já escala pelo DPI →

**patch 0016 (mshtml/olecmd.c)**: zoom do host dividido pela escala do Gecko; getter devolve o zoom cru

  (100% inicial, como o IE). mshtml entrou em PE_MODULES/vendor. Login testado: renderiza certo, Cancelar ok.

- Ações `click:`: 2 movimentos + 600 ms antes do clique (páginas precisam de hover); `click!:` repete 1×

  se nenhuma janela nova aparecer em 2,5 s (Entrar). Menus do programa miram `programWindowForMenu`

  (key → main → frontmost), não o first responder. Ícone '@floppy' desenhado (SF Symbols não tem disquete).

- **Dock:** winemac trocava o ícone do app pelo ícone da janela (cru). Agora: com CFBundleIconFile (atalho)

  mantém o do bundle; sem bundle, emoldura na placa branca (`winapps_framed_icon`, igual icon-frame.swift).

- "Travamento" na abertura do PBI em 07/11 ~23h era o Mac sobrecarregado (Xcode compilando, carga ~11):

  abria em >200 s. Não confundir com bug. Usuário trabalha no Mac durante os testes: NÃO ficar trazendo o

  PBI para frente/clicando; capturas -R pegam outras janelas dele. Achar PID: script com `ps | awk

  '/[P]BIDesktop\.exe/ && !/msedgewebview2/'` (pgrep -f casa com o próprio comando).

- Piscada ao abrir o login: NÃO reproduzida ainda (pedir ao usuário detalhes).

- Semáforo da barra do Mac: botões padrão (standardWindowButton) NÃO acendem fora de uma titlebar real

  no macOS 27 (_mouseInGroup ignorado) → desenhados à mão (WineTrafficLight/WineTrafficLights: cores do

  sistema, ×/−/+ no hover do grupo, escurece ao pressionar, cinza se inativa). Testado com hover real.

- **dxmt/0004**: SwapDeviceContextState mínimo (devolve/guarda o objeto de estado, não salva

  o pipeline). Antes abortava: o d2d1 do motor chama → Notepad++ (Direct2D) caía às vezes.

  Teste: `~/Library/Caches/WinApps/tests/swapstate.exe` ("swap OK" no log).

- **LaunchServices mantém PATH e LANG de quem abre** (Dock/Finder/open), ignorando o LSEnvironment →

  ntdll (0017) aplica `WINAPPS_PATH` (prefixa PATH: ntlm_auth) e `WINAPPS_LANG`. Sem ntlm_auth no PATH o

  msmdsrv cai → PBI "Falha na autenticação" + janela de console SQLDUMPER.EXE ("terminal").

- Recompilar módulo com `make` na árvore oficial: depois rodar o ajuste de install name/rpath/codesign

  (como install_module) ANTES do vendor.sh — senão some o FreeType (sem texto, PBI cai em laço criando

  centenas de conhost; parar com `WINEPREFIX=… "…/bin/WinApps Server" -k`).

- Receita TitleBarButtons: símbolo = primeiro @ depois do '=' ("ctrl+s@@floppy"); fallback era o ícone

  "…" (NSImageNameActionTemplate).

- Gerar patches: cabeçalhos via python (o sed do macOS não entende \t; "mshtml" quebrou o 0016).

## Descobertas importantes

- Build: CLT só arm64 → usar clang nativo com `-arch x86_64` e `--build/--host=x86_64-apple-darwin`;

  Wine 11 exige MinGW; rpath `@loader_path/../../` necessário (senão FreeType some = sem texto).

- `.NET Framework` no Wine: `mscorsvw.exe` trava em loop → override `mscorsvw.exe=''`.

- Power BI Desktop: instala, não abre (WPF+WebView2). Office/Teams/Adobe: não.

- **WebView2 (projeto atual):** carrega a página mas nada aparece: o navegador

  (`msedgewebview2.exe`) desenha numa *janela-filha de outro processo*; winemac não implementa

  ("Cross-process child window Metal swapchains are not implemented", window.c ~1179).

  Flags do Chromium não resolvem.

**✅ WEBVIEW2 FUNCIONANDO (07/11/2026, 3ª sessão)** — `tests/wv2test.c` mostra a página

  (gradiente animado, JS ok, Edg/157) SEM flags. Cadeia: Chromium → DirectComposition (Wine

  dcomp, patch wip/0007: `bind_late_swapchain` → `IDXMTCompositionSwapChain::BindToWindow`)

  → DXMT com swapchain de composição (patches `patches/wip/dxmt/0001-0002`, repo em

  `~/Library/Caches/WinApps/dxmt-src`, build `build-win64`, só PE dlls via mingw+meson,

  metallib pré-extraído do d3d11.dll oficial, `winebuild --builtin` obrigatório) → janela

  "Intermediate D3D Window" do gpu-process (filha de outro processo) → patch wip/0006:

  CAMetalLayer independente num CAContext (`macdrv_remote_metal_*`, tag `hwnd<<1|1` no

  macdrv_functions do DXMT) + GDI via CAContext; dono mostra com CALayerHost (timer 60 Hz,

  cabeçalho .surf 64 B). Testes: `xproctest.exe [d3d]`, `wv2test.exe`, `d3d11test.exe [warp]`.

  Ferramentas: `winapps/tests/tools/{build-tests,wv2run,devinstall,dxmt-devinstall,mdmp.py}`;

  `winid` (Swift) em ~/Library/Caches/WinApps/tests p/ `screencapture -l` só da janela.

  Diagnóstico: `WINEDEBUG=+debugstr` (OutputDebugString do Chromium), crash dumps em

  `EBWebView/Crashpad/reports` (mdmp.py), `WINEMAC_DEBUG_LOG`, DXMT loga em stdout.

**Cliques funcionam** (botão da página conta cliques: "Clicado! 3"). Para testar cliques use

  `~/Library/Caches/WinApps/tests/click X Y` (CGEvent real; o `click at` do System Events NÃO

  gera mouse para o Wine). 1ª imagem demora ~20 s (investigar). Teclado não testado (não

  enviar teclas: o usuário testa).

**Power BI (07/11, 4ª sessão)** no prefixo `teste-wv2`: precisa .NET 4.8 real (winetricks

  dotnet48 + `winecfg -v win10` depois) — com Mono dá FailFast. Correções que o fizeram abrir:

  (1) `.winmd` reais da Microsoft (NuGet Microsoft.Windows.SDK.Contracts: FoundationContract →

  `system32/WinMetadata/windows.foundation.winmd`, UniversalApiContract → `windows.winmd`; os do

  Wine movidos p/ `windows/WinMetadata.wine-bak`) — sem isso "Failed to resolve ReportView"

  (TypeLoad Windows.Storage.Streams.IRandomAccessStreamReference). Licença p/ redistribuir: verificar.

  (2) `patches/wip/0008` ntdll: `NtImpersonateAnonymousToken` → SUCCESS (msmdsrv abortava com

  "Invalid function") e `PagefileUsage` = phys_footprint no macOS (antes virtual_size ⇒ 66 GB ⇒

  Analysis Services em "Low Memory"). Instalado via `devinstall.sh ntdll` (backup ntdll.so.orig).

  (3) `patches/wip/dxmt/0003`: swapchain de composição continua respondendo a

  IDXMTCompositionSwapChain após o bind (senão dcomp "Failed to get the swapchain front buffer").

  (4) **Autenticação Windows local** (Power BI ↔ Analysis Services, "Authentication failed."):

  `winapps/ntlm_auth.c` = substituto mínimo do ntlm_auth do Samba (protocolos de helper do

  msv1_0), autentica só processos do mesmo usuário via HMAC com segredo 0600

  `~/Library/Application Support/WinApps/ntlm-local.key`; precisa estar no PATH do Wine

  (teste: `/Volumes/WinAppsDev/ntlm_auth`). (5) `patches/wip/0009` secur32: Impersonate/Revert/

  QuerySecurityContextToken no provedor LSA. (6) 0008 também: NtImpersonateAnonymousToken põe

  cópia do token do processo na thread (msmdsrv dava "No impersonation token").

**✅ RESULTADO (07/11, 18h):** Power BI abre, relatório em branco, "Use sample data" → Navigator

  (Power Query) → Load → visual "Sum of Sales by Country" renderizado. Diálogo WebView2 preto

  CORRIGIDO por `patches/wip/0010` (winemac: quem muda uma janela-filha atualiza os cabeçalhos

  .surf dos descendentes de outros processos; cabeçalho migra p/ a pasta da raiz atual quando a

  WebView é reparentada — o PBI reaproveita WebViews nos diálogos). Teste: `wv2test.exe popup`

  (`WV2ARGS=popup wv2run.sh`). Pendências: diálogos HTML (Gecko) às vezes deslocados;

  inicialização do PBI às vezes trava em about:blank (intermitente);

  licença dos .winmd; empacotar ntlm_auth no WinApps (PATH) e oficializar 0008/0009.

  Ferramentas: `tests/tools/pbirun.sh` (abre PBI, fecha aviso, clica Blank report; KEEPDIALOG=1),

  `tests/tools/cdp.py <id|url> [js]` (DevTools: console + avaliar JS), `tests/astest.cs`

  (teste ADOMD; compilar com csc do .NET 4.8 do prefixo), `enumwin.exe size HWND x y w h`.

  DevTools no WebView2: kernelbase de DIAGNÓSTICO instalado (`patches/wip/DIAG-*`, env

  `WINE_WV2_EXTRA_ARGS="--remote-debugging-port=9222"`; backup kernelbase.dll.orig). Cliques:

  CGEvent só com a janela no topo (`topat X Y`); no zsh usar `${=pt}` p/ dividir "X Y".

**Dock (07/11, 5ª sessão):** `patches/wip/0011` winemac: processo cujo ancestral vivo (exceto

  explorer.exe) tem janela visível vira NSApplicationActivationPolicyAccessory (sem Dock/Cmd-Tab) —

  WebView2/diálogos de processos-filho ficam "dentro" do app. Opção `HKCU\Software\Wine\Mac Driver`

  `GroupHelperProcesses=n` desliga. Teste: `tests/docktest.c` (filho deve ser UIElement no lsappinfo).

  Lentidão do PBI: sem msync/esync no Wine 11 (só ntsync/Linux); idle ≈0% CPU; não perfilado ainda.

  (histórico) Motor era EXPERIMENTAL até a 5ª sessão; agora é o oficial (ver ESTADO ATUAL).

  Voltar ao estável: `winapps engine-patch; winapps dxmt on` e restaurar

  `lib/wine/x86_64-windows/dcomp.dll.orig` e `lib/wine/x86_64-unix/ntdll.so.orig`, `x86_64-windows/{secur32,kernelbase}.dll.orig`.

**Próximos passos:** oficializar (tirar debug, mover wip→patches, build-engine.sh compilar

  dcomp.dll + script engine/build-dxmt.sh, vendor com DXMT próprio), testar clique/teclado,

  redimensionar, e um app real com WebView2.

**Armazenamento:** pesado fica na imagem APFS `/Volumes/Midias/WinAppsDev.sparsebundle`

  (montada em /Volumes/WinAppsDev; montar: `hdiutil attach … -nobrowse`). Links:

  ~/Library/Caches/WinApps, prefixes/teste-wv2, ~/.cache/winetricks → lá.

**ATUALIZAÇÃO (07/11, 2ª sessão) — vale mais que o texto abaixo:**

  - WIP 0006 agora usa **CAContext/CALayerHost** (sem cópia de pixels): filha remota publica

    `context_id` num cabeçalho de 64 B (`.surf`, campos: magic, ver, seq, visible, x, y, w, h,

    context_id, kind 0=GDI/1=GPU, pid, frames); dono cria CALayerHost. **Provado com

    xproctest** (posição exata). Log dev: `WINEMAC_DEBUG_LOG=<arq>` (`macdrv_dbg`).

  - **Bug corrigido no WinApps:** DXMT exige `winemetal.dll` no system32 de CADA prefixo

    (`dxmt_sync_prefixes` no script); sem isso nenhum app D3D10/11 carregava. App reconstruído.

  - DXMT aceita `D3D_DRIVER_TYPE_WARP` (cai no hardware). Log do DXMT: `DXMT_LOG_PATH`/stdout.

  - Crash dumps do Chromium: `…/EBWebView/Crashpad/reports/*.dmp` (int3 = CHECK).

  - **Bloqueio real atual:** o Chromium (Win10+) apresenta via **DirectComposition**:

    `CreateSwapChainForComposition` → DXMT "Not implemented" (dxgi_factory.cpp:152). Com

    `dcomp=d` + `--disable-direct-composition` o erro some, mas o GPU process não tenta

    swapchain em HWND (nenhum `dxmt get_win_data`), só cria client surfaces em janelas ocultas

    próprias e reinicia. Solução exigiria DComp mínimo (Wine dcomp + DXMT composition

    swapchain → rebuild do DXMT). Aguardando decisão do usuário.

  - Ferramentas permanentes: `winapps/tests/tools/{build-tests,wv2run,devinstall}.sh`

    (binários e SDK em `~/Library/Caches/WinApps/tests`; fonte DXMT em

    `~/Library/Caches/WinApps/dxmt-src`). Motor instalado = limpo (0003–0005).

**Estado anterior (07/11/2026):** `patches/wip/0006-remote-child-surfaces-WIP.patch` (NÃO aplicado pelo

  build; motor instalado = 0003–0005 limpo). Ele faz: win32u dá superfície própria a janela-filha

  cujo topo é de outro processo (`is_remote_root_child` em get_window_surface); winemac cria uma

  "remote surface" (pixels num arquivo mmap em `$TMPDIR/winemac-remote-<uid>-<hash>/<root>/

  <hwnd>-<serial>.surf`, cabeçalho com x,y relativos à ÁREA CLIENTE do topo) e o processo dono

  mostra como CALayer (timer 60 Hz em cocoa_app.m). Tem log de debug via env

  `WINEMAC_DEBUG_LOG=<arquivo>` (dce.c "DC without surface", surface.c, window.c) — remover antes

  de oficializar. **Provado com `tests/xproctest.c`** (processo B pinta dentro da janela de A: OK).

**Por que o WebView2 ainda fica branco:** o Chromium não pinta por GDI; o processo de GPU cria

  janelas-filhas "Intermediate D3D Window" (dele) dentro de Chrome_WidgetWin_1 e apresenta por

  D3D/Vulkan numa client surface Metal que fica num processo sem janela Cocoa. Flags necessárias

  para a WebView aparecer: `--disable-features=CalculateNativeWinOcclusion` (senão o Chromium

  esconde as janelas). Hierarquia: Chrome_WidgetWin_0 (processo do host) > Chrome_WidgetWin_1

  (browser) > Chrome_RenderWidgetHostHWND / Intermediate D3D Window (gpu-process).

**Próximo passo:** trocar o arquivo mmap por **CAContext/CALayerHost** (API privada QuartzCore,

  a mesma do Chrome no Mac): no processo da filha, `[CAContext contextWithCGSConnection:

  CGSMainConnectionID() options:@{}]`, `context.layer = <layer da client surface / da imagem>`,

  publicar `contextId` no cabeçalho; no dono, `CALayerHost.contextId = id` posicionado na área da

  filha. Cobre Metal (GPU) sem cópia e também o caminho GDI. Ganchos: client surface de filha

  remota (window.c `macdrv_client_surface_acquire_metal_swapchain` / `macdrv_CreateClientSurface`)

  e a remote surface de surface.c.

  Teste: prefixo `teste-wv2` (já criado, WebView2 157 instalado, ~1,5 GB) + scratchpad

  `wv2/run.sh`, `hdr.py`, `enumwin.c` (recriar se o scratchpad sumir; fontes em `winapps/tests/`).

## Cuidados

- Usuário tem 2º monitor (janelas podem abrir em x≥2560) e usa o Mac durante os testes:

**nunca enviar teclas** (osascript keystroke/key code); clicar só em janelas nossas.

- Disco com ~9 GB livres: apagar prefixos/downloads de teste ao terminar.

- Rosetta será restringido no macOS 28 (risco geral).