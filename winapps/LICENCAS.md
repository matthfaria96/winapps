# Créditos e licenças

O WinApps inclui componentes de software livre. As licenças deles pedem que os avisos
abaixo acompanhem o app e que o código-fonte das versões modificadas esteja disponível.

## Motor

O motor do WinApps é baseado no **Wine** (<https://www.winehq.org>), com as correções do
**Wine Staging** e o empacotamento para macOS de **Gcenx**
(<https://github.com/Gcenx/macOS_Wine_builds>).

- Copyright © 1993-2026 the Wine project authors.
- Licença: GNU Lesser General Public License, versão 2.1 ou posterior (LGPL-2.1+).
- As modificações do WinApps estão em `patches/` e `programas/*/patches/` (motor) e são compiladas por
  `engine/build-engine.sh`, sob a mesma licença.

## Gráficos (Direct3D → Metal)

**DXMT** (<https://github.com/3Shain/dxmt>), copyright © 2023 Feifan He. Licença MIT.
As modificações do WinApps estão em `patches/dxmt/` e são compiladas por
`engine/build-dxmt.sh`.

## Componentes do Windows

- **winetricks** (<https://github.com/Winetricks/winetricks>): LGPL-2.1+.
- **cabextract** (<https://www.cabextract.org.uk>): GPL-3.0+.
- Os componentes da Microsoft (.NET Framework, Visual C++, WebView2, metadados do Windows
  SDK) são baixados dos sites da Microsoft na máquina do usuário, sob as licenças dela. O
  WinApps não os redistribui.

## WinApps

O código próprio do WinApps (app, script, ferramentas e correções) acompanha este
repositório. As correções do motor seguem a LGPL-2.1+, a licença do código que modificam.
