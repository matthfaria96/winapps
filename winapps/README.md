# WinApps

Roda programas do Windows (`.exe`, `.msi`) no Mac com um motor de compatibilidade próprio.
Cada programa vira um app
do Mac, com nome e ícone próprios.

- **Para quem usa:** leia o **[GUIA.md](GUIA.md)**. É o mesmo texto que aparece no app, em
  *Ajuda → Guia do WinApps* ou no menu ⋯. Ele cobre como instalar programas, o Power BI e
  programas parecidos, e o que fazer quando algo dá errado.
- **Este README** é para quem compila e mantém o WinApps.

## Compilar

```bash
bash engine/build-engine.sh --build-only   # motor com as correções (~5 min na 1ª vez)
bash engine/build-dxmt.sh                  # DXMT com as correções (~3 min)
cd winapps
bash vendor.sh                             # junta tudo em vendor/
bash build.sh                              # WinApps.app em ~/Applications
```

Os dois scripts do motor precisam do Homebrew; eles instalam `bison`, `flex`, `freetype`,
`autoconf`, `mingw-w64`, `meson` e `ninja` se faltarem. Quem baixa o app pronto não precisa
de nada disso.

Na primeira vez, **Preparar o Windows** (ou `winapps setup`) faz o seguinte:

1. instala o Rosetta 2, se faltar;
2. baixa a base do motor (versão 11.21; origem e licenças em [LICENCAS.md](LICENCAS.md))
   (~225 MB) e troca os módulos corrigidos (originais guardados como `*.orig`);
3. liga o DXMT (Direct3D 10/11 → Metal);
4. cria o ambiente Windows em português, com as pastas e o visual do Mac;
5. instala o ambiente base: fontes, Visual C++ 2008–2022, d3dx9, d3dcompiler_47,
   .NET Framework 4.8 (pré-compilado), metadados WinRT e WebView2 — tudo o que os programas
   testados precisam. **Um único ambiente para todos os programas** (nada é replicado);
   receitas de programas (ex.: `rubinot/install.sh`) só acrescentam o que é deles.

### O que vai dentro do app

| Arquivo | Para quê |
|---|---|
| `winapps` | o script que faz todo o trabalho (o app só chama ele) |
| `GUIA.md` | guia do usuário, exibido no app |
| `compat.json` | programas conhecidos: status, selo Verificado, data do teste, correções, nome do atalho, componentes |
| `compat-md.py` | gera `COMPATIBILIDADE.md` (raiz do repositório) a partir do `compat.json`; roda no `build.sh` |
| `exe-kind.py` | instalador × portátil, nome do programa, componentes (`--needs`), compatibilidade |
| `exe-icon.py` + `icon-frame` | ícone do `.exe` numa placa branca no formato do macOS |
| `ntlm_auth` | login Windows local entre processos do mesmo usuário (ver abaixo) |
| `vendor/winetricks`, `vendor/cabextract` | componentes do Windows |
| `vendor/engine-11.21/` | `x86_64-unix/{win32u,winemac,ntdll}.so`, `x86_64-windows/{dcomp,secur32}.dll` |
| `vendor/dxmt-v0.80/` | DXMT oficial + `dxgi.dll`/`d3d11.dll` compilados com `patches/dxmt` |

O app copia esses arquivos para `~/Library/Application Support/WinApps/bin` e `vendor/`,
que é de onde os atalhos usam.

## Correções no motor

Ficam em [`../patches/`](../patches/) e são aplicadas pelo `engine/build-engine.sh` sobre o
código-base do motor (versão 11.21, ver LICENCAS.md). Ele confere que os módulos novos exportam
as mesmas funções e ligam nas mesmas bibliotecas que os originais.

| Patch | Módulo | O que corrige |
|---|---|---|
| `0003` | win32u | barra de menu presa na largura antiga |
| `0004` | winemac | menu do programa na barra de menus do macOS (`NativeMenuBar`) |
| `0005` | winemac | tabela `macdrv_functions` para o DXMT |
| `0006` | win32u, winemac | janela-filha de **outro processo** (WebView2): a filha publica um `CAContext` (GDI ou Metal) e o processo dono da janela mostra com `CALayerHost` |
| `0007` | dcomp | DirectComposition liga a swapchain de composição do DXMT à janela |
| `0008` | ntdll | `NtImpersonateAnonymousToken` e uso de memória real no macOS (Analysis Services) |
| `0009` | secur32 | `ImpersonateSecurityContext` / `RevertSecurityContext` / `QuerySecurityContextToken` |
| `0010` | winemac | filhas remotas acompanham mudanças e troca de janela-mãe dos ancestrais |
| `0011` | winemac | processos auxiliares sem ícone próprio no Dock (`GroupHelperProcesses=n` desliga) |
| `0012` | winemac | filhas remotas empilhadas na ordem de pintura do Windows |
| `0013` | winemac | compõe as filhas remotas assim que a janela aparece (antes: só quando ficava ativa → tela cinza) |
| `0014` | winemac | programas com barra de título própria: sombra e redimensionamento do Mac, Janela → Preencher/lado a lado, arrastar a barra de janela maximizada a solta, soltar no topo maximiza e nas bordas encaixa na metade |
| `0015` | winemac | barra de título do Mac desenhada por cima da barra própria do programa (altura medida com `WM_NCHITTEST`), botões nativos, arrastar/duplo clique, menu Janela → "Mostrar a Barra do Programa"; menus do programa por receita (`MacMenu`, de `mac_menu` no `compat.json`) que apertam os atalhos dele; opção `MacTitleBar` (`winapps titlebar`) |
| `0016` | mshtml | o zoom que programas com DPI alto pedem ao HTML (ex.: 200% no Retina) passa a ser relativo à escala que o Gecko já aplica; antes ficava 4× e telas como o login do Power BI saíam cortadas |
| `0017` | ntdll | binários com nomes próprios (`WinApps`, `WinApps Server`); o motor pode ser o executável de um app (programa, pasta, log, idioma e "manter aquecido" vêm do ambiente) |
| `0018` | winecfg | título "Configurações do Windows" |
| `dxmt/0001` | DXMT | compila sem o compilador Metal (metallib do pacote oficial embutido) |
| `dxmt/0002–0003` | DXMT | `CreateSwapChainForComposition` (Chromium via DirectComposition) |
| `dxmt/0004` | DXMT | `SwapDeviceContextState` mínimo (usado pelo Direct2D; antes o programa caía) |

`winapps engine-patch` reinstala os módulos do `vendor/`; `bash engine/build-engine.sh
--restore` volta para os originais do Gcenx.

### Por que o WebView2 precisou de tudo isso

O WebView2 (Chromium) desenha numa janela-filha que pertence a outro processo
(`msedgewebview2.exe`), e no macOS um processo não pode desenhar na janela de outro. A
cadeia que funciona é esta:

1. o processo de GPU do Chromium apresenta pelo DirectComposition (`dcomp` + 0007);
2. o DXMT cria uma swapchain de composição (`patches/dxmt`) que desenha num `CAMetalLayer`
   dentro de um `CAContext` (0006);
3. o id do contexto vai num cabeçalho de 64 bytes em
   `$TMPDIR/winemac-remote-<uid>-<hash>/<janela-raiz>/<hwnd>-<n>.surf`;
4. o processo dono da janela mostra cada filha com um `CALayerHost`, na posição, na
   visibilidade e na ordem de pintura do Windows (0010, 0012).

O Power BI mantém 5 WebViews visíveis e sobrepostas e escolhe a ativa pela ordem de
empilhamento. Por isso o 0012 é necessário.

### Login Windows local (`ntlm_auth.c`)

O Power BI conversa com o Analysis Services local usando autenticação integrada do
Windows (NTLM). O motor delega o NTLM a um programa externo `ntlm_auth`, que não existe no
Mac. O `ntlm_auth` do WinApps só autentica processos do mesmo usuário: os dois lados
provam que leem a chave `~/Library/Application Support/WinApps/ntlm-local.key` (0600). O
script põe `bin/` no `PATH` do motor.

## Componentes

`winapps components <nome>` aceita os do winetricks e dois próprios:

| Componente | O que faz |
|---|---|
| `winrt-metadata` | baixa da Microsoft (NuGet `Microsoft.Windows.SDK.Contracts` 10.0.26100.1742, SHA-256 conferido) os `.winmd` reais e guarda os parciais do motor em `windows/WinMetadata.wine-bak`. Sem isso o Power BI falha com `TypeLoadException` |
| `webview2` | instala o WebView2 Runtime oficial (x64), se faltar |

Depois de `dotnet40`–`dotnet48`, o script volta o Windows para a versão 10, porque o
winetricks deixa em Windows 7. Os componentes que cada programa exige vêm do campo `needs`
no `compat.json` e da análise do `.exe` (`exe-kind.py --needs`).

## Instaladores e desempenho

- **Instaladores WiX "Burn" com interface .NET** (`mbahost.dll`, ex.: o do Power BI) travam
  no motor ao carregar a interface. O `winapps install` lê o manifesto do pacote, extrai os
  `.msi` embutidos com o `cabextract`, confere o SHA-1 e roda cada um com o `msiexec`.
  `WINAPPS_MSI_ARGS="/qn ACCEPT_EULA=1"` instala sem telas.
- **.NET pré-compilado (`winapps optimize [programa.exe]`).** No Windows o .NET Framework
  vem compilado para o processador (NGEN); sem isso, cada abertura recompila tudo e o
  Rosetta ainda traduz o resultado. O serviço de pré-compilação (`mscorsvw.exe`) trava em
  loop no motor e fica desligado; o `ngen` síncrono funciona e liga o `mscorsvw` só durante
  a chamada. O log fica em `~/Library/Logs/WinApps/ngen.log`.
- **Controles de jogo (`winapps gamepad`).** O backend SDL do `winebus` consulta os
  controles sem parar: ~7% de CPU contínuo por ambiente aberto (medido no
  `winedevice.exe`: 2 s de CPU a cada 30 s). O padrão é só IOHID (`Enable SDL`=0).

## Terminal

| Comando | O que faz |
|---|---|
| `winapps setup` | baixa o motor e cria o ambiente |
| `winapps install setup.exe` | roda o instalador e lista os `.exe` novos |
| `winapps shortcut "<.exe>" ["Nome"]` | cria `~/Applications/Nome.app`; sem nome, usa o `compat.json` ou o nome do produto |
| `winapps name <.exe>` | o nome que o atalho receberia |
| `winapps run programa.exe` | executa direto |
| `winapps detect` / `needs` / `compat` `<arquivo>` | análise do arquivo |
| `winapps components [nomes]` | instala componentes (sem nomes: os essenciais) |
| `winapps list` / `remove Nome` / `rebuild` | atalhos (o `rebuild` mantém o ambiente de cada um) |
| `winapps dxmt on\|off\|status` | Direct3D 10/11 via Metal |
| `winapps gamepad on\|off\|status` | controles de jogo via SDL (padrão: off, sem gasto de CPU) |
| `winapps optimize [programa.exe]` | pré-compila o .NET Framework (sem argumento) ou um programa .NET |
| `winapps menubar <prog.exe>\|--all on\|off` | menu do programa na barra do Mac |
| `winapps engine-patch` | reinstala o motor corrigido do `vendor/` |
| `winapps kill` / `config` / `tidy` / `drive` | fechar tudo / configurações do Windows / pastas e idioma / abrir o C: |

## Onde fica cada coisa

- Motor: `~/Library/Application Support/WinApps/motor` (pasta interna; não é um app do macOS)
- Ambiente Windows: `~/Library/Application Support/WinApps/prefixes/default` (um só, para todos
  os programas; `WINAPPS_PREFIX` existe só para testes de desenvolvimento)
- Atalhos: `~/Applications/*.app`. O executável de cada atalho **é o motor**, com o nome do
  programa (`Contents/MacOS/<Nome>`, assinado localmente); as configurações vão no
  `LSEnvironment` do `Info.plist` (`WINEPREFIX`, `WINAPPS_PROGRAM`, `WINAPPS_LOG`,
  `WINAPPS_LANG`, `WINAPPS_PERSIST`). Assim o macOS (Dock, Cmd-Tab, Monitor de Atividade,
  apps de prévia de janelas como o Sirena) vê um app só, com o ID, o nome e o ícone do atalho.
  O `Info.plist` também guarda `WinAppsExe` e `WinAppsPrefix`.
- Logs: `~/Library/Logs/WinApps/`; downloads em cache: `~/Library/Caches/WinApps/downloads`

## Testes

`tests/` tem programas mínimos para isolar problemas. Para compilá-los, use
`x86_64-w64-mingw32-gcc` ou `tests/tools/build-tests.sh`.

| Teste | O que verifica |
|---|---|
| `d3d11test.c` | triângulo Direct3D 11 (DXMT) |
| `wv2test.c` | WebView2 mínimo; `popup` abre uma 2ª WebView numa janela pop-up |
| `xproctest.c` | um processo pinta dentro da janela de outro (GDI e `d3d`) |
| `docktest.c` | processo-filho com janela não ganha ícone no Dock |

Ferramentas em `tests/tools/`: `wv2run.sh`, `pbirun.sh`, `cdp.py` (DevTools),
`mdmp.py` (crash dumps), `devinstall.sh` e `dxmt-devinstall.sh` (instalar módulos durante
o desenvolvimento).

## Limitações conhecidas

- O motor depende do Rosetta 2, que a Apple vai restringir a partir do macOS 28.
- Não funcionam: jogos com proteção de kernel, Office/Teams atuais (Click-to-Run/MSIX), Adobe, Direct3D 12.
- Power BI: o login na conta Microsoft e a publicação no serviço não foram testados. Às
  vezes um diálogo HTML aparece deslocado.

## Créditos e licenças

O motor e os componentes incluídos são software livre. Os avisos, as licenças e onde estão
as modificações ficam em [LICENCAS.md](LICENCAS.md), que acompanha o app.
