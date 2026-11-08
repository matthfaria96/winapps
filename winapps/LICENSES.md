# Credits and licenses

## WinApps

WinApps is free software, distributed under the **GNU General Public License, version 3.0**
(GPL-3.0). The full text is in the `LICENSE` file at the root of the repository
(<https://github.com/matthfaria96/winapps>). This covers WinApps' own code: the app, the
`winapps` script, the tools and the program recipes.

The engine patches (`patches/` and `programas/*/patches/`) are licensed under the **GNU
Lesser General Public License, version 2.1 or later** (LGPL-2.1-or-later), the same license
as Wine, the code they modify.

WinApps also includes free software components. Their licenses require the notices below
to accompany the app and the source code of modified versions to be available.

## Engine

The WinApps engine is based on **Wine** (<https://www.winehq.org>), with the **Wine
Staging** patches and the macOS packaging by **Gcenx**
(<https://github.com/Gcenx/macOS_Wine_builds>).

- Copyright © 1993-2026 the Wine project authors.
- License: GNU Lesser General Public License, version 2.1 or later (LGPL-2.1+).
- WinApps' changes are in `patches/` and `programas/*/patches/` and are built by
  `engine/build-engine.sh`, under the same license.

## Graphics (Direct3D → Metal)

**DXMT** (<https://github.com/3Shain/dxmt>), copyright © 2023 Feifan He. MIT License.
WinApps' changes are in `patches/dxmt/` and are built by `engine/build-dxmt.sh`.

## Windows components

- **winetricks** (<https://github.com/Winetricks/winetricks>): LGPL-2.1+.
- **cabextract** (<https://www.cabextract.org.uk>): GPL-2.0+.
- Microsoft components (.NET Framework, Visual C++, WebView2, Windows SDK metadata) are
  downloaded from Microsoft's websites on the user's Mac, under Microsoft's licenses.
  WinApps does not redistribute them.
