# Créditos e licenças

## WinApps

O WinApps é software livre, distribuído sob a **GNU General Public License, versão 3.0**
(GPL-3.0). O texto completo está no arquivo `LICENSE` na raiz do repositório
(<https://github.com/matthfaria96/winapps>). Isso vale para o código próprio do WinApps: o
app, o script `winapps`, as ferramentas e as receitas de programas.

As correções do motor (`patches/` e `programas/*/patches/`) seguem a **GNU Lesser General
Public License, versão 2.1 ou posterior** (LGPL-2.1-or-later), a mesma licença do Wine, o
código que elas modificam.

O WinApps também inclui componentes de software livre. As licenças deles pedem que os
avisos abaixo acompanhem o app e que o código-fonte das versões modificadas esteja
disponível.

## Motor

O motor do WinApps é baseado no **Wine** (<https://www.winehq.org>), com as correções do
**Wine Staging** e o empacotamento para macOS de **Gcenx**
(<https://github.com/Gcenx/macOS_Wine_builds>).

- Copyright © 1993-2026 the Wine project authors.
- Licença: GNU Lesser General Public License, versão 2.1 ou posterior (LGPL-2.1+).
- As modificações do WinApps estão em `patches/` e `programas/*/patches/` e são compiladas
  por `engine/build-engine.sh`, sob a mesma licença.

## Gráficos (Direct3D → Metal)

**DXMT** (<https://github.com/3Shain/dxmt>), copyright © 2023 Feifan He. Licença MIT.
As modificações do WinApps estão em `patches/dxmt/` e são compiladas por
`engine/build-dxmt.sh`.

## Componentes do Windows

- **winetricks** (<https://github.com/Winetricks/winetricks>): LGPL-2.1+.
- **cabextract** (<https://www.cabextract.org.uk>): GPL-2.0+.
- Os componentes da Microsoft (.NET Framework, Visual C++, WebView2, metadados do Windows
  SDK) são baixados dos sites da Microsoft no Mac do usuário, sob as licenças dela. O
  WinApps não os redistribui.
