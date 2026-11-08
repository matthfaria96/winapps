# WinApps

**English** · [Português](README.pt-BR.md)

Run Windows programs on your Mac as if they were Mac apps — free and open source. WinApps
opens `.exe` and `.msi` files on Apple Silicon Macs without a virtual machine, and turns each
program into a real Mac app: its own name and icon in the Dock and ⌘ Tab, menus in the macOS
menu bar, Mac window buttons, minimize, full screen and tiling like any other app. Under the
hood is a compatibility engine built on Wine Staging 11.21 with **fixes of its own** that
upstream Wine doesn't have — that's what makes programs like Power BI Desktop work here. The
interface is in English and Brazilian Portuguese.

## Features

- **A native Mac app** (SwiftUI) to install, open and manage Windows programs — no command
  line needed.
- **Each program becomes its own app** in Applications and Launchpad, with one Dock icon, its
  name in ⌘ Tab and Activity Monitor, and its original icon on a Mac-style white plate.
  Helper processes (like an embedded browser) stay inside the program instead of adding
  extra Dock icons.
- **Menus in the macOS menu bar.** Programs with a standard Windows menu show it at the top
  of the screen; known programs get Mac menus that trigger their own shortcuts.
- **Mac title bar over custom title bars.** Programs that draw their own bar (Power BI,
  WebView2 and Electron apps) get the red, yellow and green buttons, dragging, snapping to
  the top or half of the screen, and the Window menu's fill and tile options.
- **Drag and drop install.** Drop an `.exe`, `.msi`, folder or `.zip` on the window: WinApps
  tells installers from standalone programs and does the right thing.
- **Built-in compatibility list** with badges (Verified, Works, Partial, Not supported) and a
  warning before installing something that won't run.
- **File browser** to copy and move files between the Mac and Windows; the Windows Desktop,
  Documents and Downloads are your Mac folders.
- **Storage view** showing how much space the engine, the Windows environment and each
  program use, with a button to free up temporary files.
- **One shared Windows environment**, set up once with fonts, Visual C++, DirectX, .NET
  Framework 4.8 and WebView2.
- **Direct3D 10/11 → Metal** (DXMT) included, and **WebView2** drawn through Metal.
- ⌘C, ⌘V, ⌘S, ⌘Z and the other shortcuts work like Ctrl on Windows.

## Why WinApps

| | Plain Wine | CrossOver | **WinApps** |
|---|:---:|:---:|:---:|
| Price | free | paid (yearly subscription) | **free** |
| Open source | yes | partly | **yes** |
| Engine base | — | CodeWeavers' own version | **Wine Staging 11.21** (recent) |
| Native Mac app to install and open programs | no (command line) | yes | **yes** |
| Each program as its own app (Dock, ⌘ Tab, icon) | no | partly | **yes** |
| Program menus in the macOS menu bar | no | no | **yes** |
| Mac title bar over the program's own title bar | no | no | **yes** |
| WebView2 (embedded browser in modern apps) drawn through Metal | no | limited | **yes** |
| Direct3D 10/11 → Metal included | no | yes (D3DMetal) | **yes** (DXMT) |
| Power BI Desktop | doesn't open | not supported | **works** |
| Direct3D 12 | no | yes (D3DMetal) | not yet |
| Commercial support | no | yes | community |

The goal is to be the simplest, best-integrated way to use Windows programs on a Mac —
without a license fee, and keeping up with new engine releases. CrossOver still leads on
Direct3D 12 games and offers paid support.

## Compatibility

- **macOS 14 (Sonoma)** or later.
- **Apple Silicon** Mac.
- **Rosetta 2** is required (the engine is x86_64); WinApps installs it if it's missing.

Full, up-to-date list in **[COMPATIBILITY.md](COMPATIBILITY.md)** (the same list as the app's
Compatibility tab). Highlights:

- ✅ **Power BI Desktop** — reports, Power Query, Analysis Services and visuals (verified)
- ✅ **Notepad++** — menus in the Mac menu bar (verified)
- 🟡 **RubinOT** — plays well; the session still drops now and then (WinApps reopens it
  automatically)
- 🟢 7-Zip, SumatraPDF, PuTTY, Everything and programs that use WebView2

Not supported (they need a real Windows): games with kernel-level protection, current
Office and Teams, Adobe apps.

Limitations:

- The engine depends on Rosetta 2, which Apple will restrict starting with macOS 28.
- Heavy programs run slower than on a Windows PC.

## Installation

Pick one:

1. **Terminal, one line (recommended).** Paste this into Terminal:
   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s winapps
   ```
   It downloads the latest release from GitHub, checks its SHA-256, installs WinApps in
   Applications and opens it. There's no macOS warning, because files downloaded by `curl`
   don't get the "downloaded from the internet" mark. Run the same line again to update. The
   script is open: [install.sh](https://witchmymac.com/install.sh).
2. **Download the DMG** from [Releases](https://github.com/matthfaria96/winapps/releases) or
   [witchmymac.com](https://witchmymac.com), drag WinApps to Applications, then allow it once
   with:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/WinApps.app"
   ```
   It only removes the "downloaded from the internet" mark from that app.
3. **Download the DMG** and allow it in System Settings: open the app, click OK on the
   warning, then go to System Settings › Privacy & Security and click Open Anyway.

On first launch, click **Set Up Windows** (about 15 minutes, once): it downloads the engine
and installs fonts, Visual C++, DirectX, .NET Framework 4.8 and WebView2. Then double-click
any `.exe` or `.msi`: WinApps installs it and creates the program's app in `~/Applications`.

User guide: **[winapps/GUIDE.md](winapps/GUIDE.md)** (also in the app, under Help → WinApps
Guide). Everything also works from Terminal: `winapps help`.

## Building

Requires the Xcode Command Line Tools, Homebrew and Python 3. The engine scripts install
what they need from Homebrew (`bison`, `flex`, `freetype`, `autoconf`, `mingw-w64`, `meson`,
`ninja`). They patch the engine that **Set Up Windows** downloads and check the new modules
against the originals, so set up the Windows environment once before building the engine.

```sh
bash engine/build-engine.sh --build-only   # engine modules with the WinApps fixes (~5 min the first time)
bash engine/build-dxmt.sh                  # DXMT (Direct3D 10/11 → Metal) with the WinApps fixes (~3 min)
bash winapps/vendor.sh                     # gathers winetricks, cabextract, DXMT and the engine modules in winapps/vendor/
bash winapps/build.sh                      # builds WinApps.app (universal) into ~/Applications
```

`build-engine.sh` downloads Wine 11.21, Wine Staging and the patch used in the Gcenx macOS builds,
applies `patches/` and `programas/*/patches/` in number order and builds only the modules
that change. `build.sh` takes an optional destination folder. Technical details are in
[winapps/README.md](winapps/README.md).

## Repository layout

| Folder | Contents |
|---|---|
| [`winapps/`](winapps/) | the app (SwiftUI), the `winapps` script, program recipes (`compat.json`), general tests — technical docs in its [README](winapps/README.md) |
| [`engine/`](engine/) | builds the engine with the fixes (`build-engine.sh`) and DXMT (`build-dxmt.sh`) |
| [`patches/`](patches/) | **general** engine and DXMT fixes ([index](patches/README.md)) |
| [`programas/`](programas/) | anything specific to one program: [RubinOT](programas/rubinot/), [Power BI](programas/power-bi/) — README, its own patches and tests |

A new program with its own fix goes in `programas/<name>/{README.md,patches/,testes/}`;
`engine/build-engine.sh` already applies `programas/*/patches/*.patch` (patch numbers are
global).

## Credits and license

WinApps is distributed under the **GPL-3.0** (see [LICENSE](LICENSE)). The engine patches
are LGPL-2.1-or-later, like Wine. WinApps is built on these open source projects, each under
its own license:

| Part | Based on | License |
|---|---|---|
| Engine | [Wine](https://www.winehq.org/) + [Wine Staging](https://github.com/wine-staging/wine-staging) | LGPL-2.1+ |
| macOS builds | [Gcenx](https://github.com/Gcenx/macOS_Wine_builds) | LGPL-2.1+ |
| Direct3D 10/11 → Metal | [DXMT](https://github.com/3Shain/dxmt) | MIT |
| Windows components | [winetricks](https://github.com/Winetricks/winetricks) | LGPL-2.1+ |
| Cabinet extraction | [cabextract](https://www.cabextract.org.uk) | GPL-2.0+ |

Notices and where the changes live: [winapps/LICENSES.md](winapps/LICENSES.md). Microsoft
components (.NET Framework, Visual C++, WebView2) are downloaded from Microsoft on your Mac,
under Microsoft's licenses; WinApps doesn't redistribute them.
