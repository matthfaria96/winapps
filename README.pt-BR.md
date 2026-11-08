# WinApps

[English](README.md) · **Português**

Programas do Windows no Mac, como se fossem apps do Mac — grátis e de código aberto. O
WinApps abre arquivos `.exe` e `.msi` em Macs com Apple Silicon sem máquina virtual e
transforma cada programa num app de verdade: nome e ícone próprios no Dock e no ⌘ Tab, menus
na barra do macOS, botões de janela do Mac, minimizar, tela cheia e encaixar como qualquer
app. Por baixo há um motor de compatibilidade baseado no Wine Staging 11.21 com **correções
próprias** que o Wine oficial não tem — é isso que faz programas como o Power BI Desktop
funcionarem aqui. A interface está em inglês e em português do Brasil.

## Recursos

- **App nativo do Mac** (SwiftUI) para instalar, abrir e organizar programas do Windows —
  sem linha de comando.
- **Cada programa vira um app** em Aplicativos e no Launchpad, com um ícone no Dock, nome
  próprio no ⌘ Tab e no Monitor de Atividade e o ícone original numa placa branca no estilo
  do Mac. Processos auxiliares (como um navegador embutido) ficam dentro do programa, sem
  ícones extras no Dock.
- **Menus na barra do macOS.** Programas com menu padrão do Windows mostram o menu lá em
  cima; programas conhecidos ganham menus do Mac que apertam os atalhos deles.
- **Barra de título do Mac sobre barras próprias.** Programas que desenham a própria barra
  (Power BI, apps WebView2 e Electron) ganham os botões vermelho, amarelo e verde, arrastar,
  encaixar no topo ou na metade da tela e as opções de preencher e lado a lado do menu Janela.
- **Instalar arrastando.** Solte um `.exe`, `.msi`, pasta ou `.zip` na janela: o WinApps
  distingue instalador de programa solto e faz o certo.
- **Lista de compatibilidade embutida**, com selos (Verificado, Funciona, Parcial, Não
  funciona) e aviso antes de instalar algo que não roda.
- **Navegador de arquivos** para copiar e mover arquivos entre o Mac e o Windows; a Mesa, os
  Documentos e os Downloads do Windows são as pastas do Mac.
- **Painel de armazenamento** com o espaço do motor, do ambiente Windows e de cada programa,
  e um botão para liberar os arquivos temporários.
- **Um só ambiente Windows** para todos os programas, preparado uma vez com fontes, Visual
  C++, DirectX, .NET Framework 4.8 e WebView2.
- **Direct3D 10/11 → Metal** (DXMT) incluído, e **WebView2** desenhado pelo Metal.
- ⌘C, ⌘V, ⌘S, ⌘Z e os outros atalhos funcionam como o Ctrl do Windows.

## Por que WinApps

| | Wine puro | CrossOver | **WinApps** |
|---|:---:|:---:|:---:|
| Preço | grátis | pago (assinatura anual) | **grátis** |
| Código aberto | sim | parcial | **sim** |
| Base do motor | — | versão própria da CodeWeavers | **Wine Staging 11.21** (recente) |
| App nativo do Mac para instalar e abrir programas | não (linha de comando) | sim | **sim** |
| Cada programa como app próprio (Dock, ⌘ Tab, ícone) | não | parcial | **sim** |
| Menus do programa na barra do macOS | não | não | **sim** |
| Barra de título do Mac sobre a barra própria do programa | não | não | **sim** |
| WebView2 (navegador embutido de apps modernos) desenhado pelo Metal | não | limitado | **sim** |
| Direct3D 10/11 → Metal incluído | não | sim (D3DMetal) | **sim** (DXMT) |
| Power BI Desktop | não abre | não suportado | **funciona** |
| Direct3D 12 | não | sim (D3DMetal) | ainda não |
| Suporte comercial | não | sim | comunidade |

O objetivo é ser a forma mais simples e mais bem integrada de usar programas do Windows no
Mac — sem pagar licença e acompanhando as versões novas do motor. O CrossOver ainda leva
vantagem em jogos Direct3D 12 e tem suporte pago.

## Compatibilidade

- **macOS 14 (Sonoma)** ou mais novo.
- Mac com **Apple Silicon**.
- Precisa do **Rosetta 2** (o motor é x86_64); o WinApps instala se faltar.

Lista completa e atualizada em **[COMPATIBILIDADE.md](COMPATIBILIDADE.md)** (a mesma da aba
Compatibilidade do app). Destaques:

- ✅ **Power BI Desktop** — relatórios, Power Query, Analysis Services e visuais (verificado)
- ✅ **Notepad++** — menus na barra do Mac (verificado)
- 🟡 **RubinOT** — joga bem; a sessão ainda cai de vez em quando (o WinApps reabre sozinho)
- 🟢 7-Zip, SumatraPDF, PuTTY, Everything e programas com WebView2

Não funcionam (exigem um Windows de verdade): jogos com proteção de kernel,
Office e Teams atuais, apps da Adobe.

Limitações:

- O motor depende do Rosetta 2, que a Apple vai restringir a partir do macOS 28.
- Programas pesados ficam mais lentos que num PC com Windows.

## Instalação

Escolha um:

1. **Terminal, uma linha (recomendado).** Cole isto no Terminal:
   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s winapps
   ```
   Ele baixa a versão mais nova do GitHub, confere o SHA-256, instala o WinApps em
   Aplicativos e abre. Não aparece aviso do macOS, porque arquivos baixados pelo `curl` não
   ganham a marca de "baixado da internet". Rode a mesma linha de novo para atualizar. O
   script é aberto: [install.sh](https://witchmymac.com/install.sh).
2. **Baixe o DMG** em [Releases](https://github.com/matthfaria96/winapps/releases) ou em
   [witchmymac.com](https://witchmymac.com), arraste o WinApps para Aplicativos e libere uma
   vez com:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/WinApps.app"
   ```
   Ele só tira daquele app a marca de "baixado da internet".
3. **Baixe o DMG** e libere nos Ajustes do Sistema: abra o app, clique em OK no aviso e vá
   em Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim.

Na primeira abertura, clique em **Preparar o Windows** (uns 15 minutos, uma vez só): ele
baixa o motor e instala fontes, Visual C++, DirectX, .NET Framework 4.8 e WebView2. Depois,
dê dois cliques em qualquer `.exe` ou `.msi`: o WinApps instala e cria o app do programa em
`~/Applications`.

Guia do usuário: **[winapps/GUIA.md](winapps/GUIA.md)** (também no app, em Ajuda → Guia do
WinApps). Tudo também funciona pelo Terminal: `winapps help`.

## Compilar

Precisa das Ferramentas de Linha de Comando do Xcode, do Homebrew e do Python 3. Os scripts
do motor instalam pelo Homebrew o que faltar (`bison`, `flex`, `freetype`, `autoconf`,
`mingw-w64`, `meson`, `ninja`). Eles corrigem o motor que o **Preparar o Windows** baixa e
conferem os módulos novos contra os originais, então prepare o ambiente Windows uma vez
antes de compilar o motor.

```sh
bash engine/build-engine.sh --build-only   # módulos do motor com as correções (~5 min na 1ª vez)
bash engine/build-dxmt.sh                  # DXMT (Direct3D 10/11 → Metal) com as correções (~3 min)
bash winapps/vendor.sh                     # junta winetricks, cabextract, DXMT e o motor em winapps/vendor/
bash winapps/build.sh                      # compila o WinApps.app (universal) em ~/Applications
```

O `build-engine.sh` baixa o Wine 11.21, o Wine Staging e o patch que o Gcenx usa nos builds
dele, aplica `patches/` e `programas/*/patches/` na ordem do número e compila só os módulos
que mudam. O `build.sh` aceita uma pasta de destino opcional. Detalhes técnicos em
[winapps/README.md](winapps/README.md) (em inglês).

## Organização do repositório

| Pasta | O quê |
|---|---|
| [`winapps/`](winapps/) | app (SwiftUI), script `winapps`, receitas de programas (`compat.json`), testes gerais — técnico no [README](winapps/README.md) |
| [`engine/`](engine/) | compila o motor com as correções (`build-engine.sh`) e o DXMT (`build-dxmt.sh`) |
| [`patches/`](patches/) | correções **gerais** do motor e do DXMT ([índice](patches/README.md)) |
| [`programas/`](programas/) | o que é de um programa só: [RubinOT](programas/rubinot/), [Power BI](programas/power-bi/) — README, patches próprios e testes |

Programa novo com correção própria → `programas/<nome>/{README.md,patches/,testes/}`; o
`engine/build-engine.sh` já aplica `programas/*/patches/*.patch` (o número do patch é global).

## Créditos e licença

O WinApps é distribuído sob a **GPL-3.0** (veja [LICENSE](LICENSE)). As correções do motor
seguem a LGPL-2.1-or-later, como o Wine. O WinApps é construído sobre estes projetos de
código aberto, cada um com sua licença:

| Parte | Baseado em | Licença |
|---|---|---|
| Motor | [Wine](https://www.winehq.org/) + [Wine Staging](https://github.com/wine-staging/wine-staging) | LGPL-2.1+ |
| Builds para macOS | [Gcenx](https://github.com/Gcenx/macOS_Wine_builds) | LGPL-2.1+ |
| Direct3D 10/11 → Metal | [DXMT](https://github.com/3Shain/dxmt) | MIT |
| Componentes do Windows | [winetricks](https://github.com/Winetricks/winetricks) | LGPL-2.1+ |
| Extração de cabinets | [cabextract](https://www.cabextract.org.uk) | GPL-2.0+ |

Avisos e onde ficam as modificações: [winapps/LICENCAS.md](winapps/LICENCAS.md). Os
componentes da Microsoft (.NET Framework, Visual C++, WebView2) são baixados da Microsoft no
seu Mac, sob as licenças dela; o WinApps não os redistribui.
