# WinApps

**Programas do Windows no Mac, como se fossem apps do Mac — grátis e de código aberto.**

O WinApps roda `.exe` e `.msi` no macOS (Apple Silicon) sem máquina virtual. Cada programa
vira um app de verdade no Mac: nome e ícone próprios no Dock e no Cmd-Tab, menus na barra do
macOS, janela com os botões do Mac, minimizar/tela cheia/encaixar como qualquer app.

Por baixo há um motor de compatibilidade (baseado no Wine Staging 11.21) com **correções
próprias** que o Wine oficial não tem — é isso que faz programas como o Power BI e o RubinOT
funcionarem aqui.

## Por que WinApps

| | Wine puro | CrossOver | **WinApps** |
|---|:---:|:---:|:---:|
| Preço | grátis | pago (assinatura anual) | **grátis** |
| Código aberto | sim | parcial | **sim** |
| Base do motor | — | versão própria da CodeWeavers | **Wine Staging 11.21** (recente) |
| App nativo do Mac para instalar e abrir programas | não (linha de comando) | sim | **sim** |
| Cada programa como app próprio (Dock, Cmd-Tab, ícone) | não | parcial | **sim** |
| Menus do programa na barra do macOS | não | não | **sim** |
| Barra de título do Mac sobre a barra própria do programa | não | não | **sim** |
| WebView2 (navegador embutido de apps modernos) desenhado pelo Metal | não | limitado | **sim** |
| Direct3D 10/11 → Metal (DXMT) já incluso | não | sim (D3DMetal) | **sim** |
| Power BI Desktop | não abre | não suportado | **funciona** |
| Direct3D 12 | não | sim (D3DMetal) | ainda não |
| Suporte comercial | não | sim | comunidade |

O objetivo é ser a forma mais simples e mais bem integrada de usar programas do Windows no
Mac — sem pagar licença e acompanhando as versões novas do motor.

## O que funciona

Lista completa e atualizada em **[COMPATIBILIDADE.md](COMPATIBILIDADE.md)** (a mesma da aba
Compatibilidade do app). Destaques:

- ✅ **Power BI Desktop** — relatórios, Power Query, Analysis Services e visuais
- ✅ **Notepad++** — menus na barra do Mac
- 🟡 **RubinOT** — joga bem; a sessão ainda cai de vez em quando (o WinApps reabre sozinho)
- 🟢 7-Zip, SumatraPDF, PuTTY, Everything e programas com WebView2

Não funcionam (exigem um Windows de verdade): jogos com proteção de kernel, Office e Teams
atuais, Adobe.

## Como usar

1. Compile e instale o app: `bash winapps/build.sh` (vai para `~/Applications/WinApps.app`).
2. Abra o **WinApps** e clique em **Preparar o Windows** (uma vez, ~15 min): baixa o motor e
   instala fontes, Visual C++, DirectX, .NET Framework 4.8 e WebView2.
3. Dê dois cliques num `.exe` ou `.msi`: o WinApps instala e cria o app do programa em
   `~/Applications`.

Guia completo: **[winapps/GUIA.md](winapps/GUIA.md)** (também no app, em *Ajuda → Guia*).
Também dá para usar pelo terminal: `winapps help`.

## Organização do repositório

| Pasta | O quê |
|---|---|
| [`winapps/`](winapps/) | app (SwiftUI), script `winapps`, receitas de programas (`compat.json`), testes gerais — técnico em [README](winapps/README.md) |
| [`engine/`](engine/) | compila o motor com as correções (`build-engine.sh`) e o DXMT (`build-dxmt.sh`) |
| [`patches/`](patches/) | correções **gerais** do motor e do DXMT ([índice](patches/README.md)) |
| [`programas/`](programas/) | o que é de um programa só: [RubinOT](programas/rubinot/), [Power BI](programas/power-bi/) — README, patches próprios e testes |

Programa novo com correção própria → `programas/<nome>/{README.md,patches/,testes/}`; o
`engine/build-engine.sh` já aplica `programas/*/patches/*.patch` (o número do patch é global).

## Limitações

- Precisa do Rosetta 2 (o motor é x86_64); a Apple vai restringir o Rosetta a partir do macOS 28.
- Programas pesados ficam mais lentos que num PC com Windows.

## Créditos e licenças

O WinApps é construído sobre o [Wine](https://www.winehq.org/) (LGPL), o Wine Staging, os
builds do [Gcenx](https://github.com/Gcenx/macOS_Wine_builds) e o
[DXMT](https://github.com/3Shain/dxmt). Detalhes em [winapps/LICENCAS.md](winapps/LICENCAS.md).
