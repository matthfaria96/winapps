# WinApps

Runs Windows programs (`.exe`, `.msi`) on the Mac with its own compatibility engine. Each
program becomes a Mac app with its own name and icon.

- **If you use WinApps:** read the **[GUIDE.md](GUIDE.md)** ([GUIA.md](GUIA.md) in
  Portuguese). It's the same text the app shows under *Help → WinApps Guide* and in the ⋯
  menu. It covers installing programs, Power BI and similar programs, and what to do when
  something goes wrong.
- **This README** is for people who build and maintain WinApps.

## Building

```bash
bash engine/build-engine.sh --build-only   # engine with the fixes (~5 min the first time)
bash engine/build-dxmt.sh                  # DXMT with the fixes (~3 min)
cd winapps
bash vendor.sh                             # gathers everything in vendor/
bash build.sh                              # WinApps.app in ~/Applications
```

Both engine scripts need Homebrew; they install `bison`, `flex`, `freetype`, `autoconf`,
`mingw-w64`, `meson` and `ninja` if missing. `build-engine.sh` also needs the base engine
already downloaded (**Set Up Windows** or `winapps setup`), because it checks the new modules
against the originals. People who download the ready-made app need none of this.

The first time, **Set Up Windows** (or `winapps setup`) does the following:

1. installs Rosetta 2 if it's missing;
2. downloads the engine base (version 11.21; origin and licenses in
   [LICENSES.md](LICENSES.md)) (~225 MB) and swaps in the patched modules (originals kept as
   `*.orig`);
3. turns on DXMT (Direct3D 10/11 → Metal);
4. creates the Windows environment in the Mac's language, with the Mac's folders and look;
5. installs the base environment: fonts, Visual C++ 2008–2022, d3dx9, d3dcompiler_47,
   .NET Framework 4.8 (precompiled), WinRT metadata and WebView2 — everything the tested
   programs need. **A single environment for all programs** (nothing is duplicated);
   program recipes (e.g. `programas/rubinot/install.sh`) only add what is specific to them.

### What goes inside the app

| File | Purpose |
|---|---|
| `winapps` | the script that does all the work (the app just calls it) |
| `GUIDE.md`, `GUIA.md` | user guide shown in the app (English, Portuguese) |
| `LICENSES.md`, `LICENCAS.md` | credits and licenses (English, Portuguese) |
| `compat.json` | known programs: status, Verified badge, test date, fixes, shortcut name, components |
| `compat-md.py` | generates the compatibility tables at the repository root from `compat.json`; runs in `build.sh` |
| `exe-kind.py` | installer vs. standalone, program name, components (`--needs`), compatibility |
| `exe-icon.py` + `icon-frame` | the `.exe` icon on a white plate shaped like macOS icons |
| `ntlm_auth` | local Windows sign-in between processes of the same user (see below) |
| `vendor/winetricks`, `vendor/cabextract` | Windows components |
| `vendor/engine-11.21/` | `x86_64-unix/{win32u,winemac,ntdll}.so`, `x86_64-windows/{dcomp,secur32,mshtml,ole32}.dll`, `winecfg.exe`, `i386-windows/ole32.dll` |
| `vendor/dxmt-v0.80/` | official DXMT + `dxgi.dll`/`d3d11.dll` built with `patches/dxmt` |

The app copies these files to `~/Library/Application Support/WinApps/bin` and `vendor/`,
which is where the shortcuts use them from.

## Engine patches

General ones are in [`../patches/`](../patches/); those only one program uses live in
`../programas/<name>/patches/` (program in parentheses). `engine/build-engine.sh` applies all
of them in number order on top of the engine source (version 11.21, see LICENSES.md). It
checks that the new modules export the same functions and link against the same libraries
as the originals.

| Patch | Module | What it fixes |
|---|---|---|
| `0003` | win32u | menu bar stuck at the old width |
| `0004` | winemac | the program's menu in the macOS menu bar (`NativeMenuBar`) |
| `0005` | winemac | `macdrv_functions` table for DXMT |
| `0006` | win32u, winemac | child window owned by **another process** (WebView2): the child publishes a `CAContext` (GDI or Metal) and the process that owns the window shows it with a `CALayerHost` |
| `0007` | dcomp | DirectComposition binds DXMT's composition swapchain to the window |
| `0008` | ntdll (power-bi) | `NtImpersonateAnonymousToken` and real memory usage on macOS (Analysis Services) |
| `0009` | secur32 (power-bi) | `ImpersonateSecurityContext` / `RevertSecurityContext` / `QuerySecurityContextToken` |
| `0010` | winemac | remote children follow changes and reparenting of their ancestors |
| `0011` | winemac | helper processes without their own Dock icon (`GroupHelperProcesses=n` turns it off) |
| `0012` | winemac | remote children stacked in Windows paint order |
| `0013` | winemac | composites remote children as soon as the window appears (before: only once it became active → gray screen) |
| `0014` | winemac | programs with their own title bar: Mac shadow and resizing, Window → Fill/tile, dragging a maximized window's bar restores it, dropping at the top maximizes and at the edges snaps to half |
| `0015` | winemac | Mac title bar drawn over the program's own bar (height measured with `WM_NCHITTEST`), native buttons, drag/double-click, Window → "Show Program Title Bar"; program menus from recipes (`MacMenu`, from `mac_menu` in `compat.json`) that press the program's shortcuts; `MacTitleBar` option (`winapps titlebar`) |
| `0016` | mshtml (power-bi) | the zoom high-DPI programs ask HTML for (e.g. 200% on Retina) becomes relative to the scale Gecko already applies; before it ended up 4× and screens like the Power BI sign-in were cut off |
| `0017` | ntdll | binaries with their own names (`WinApps`, `WinApps Server`); the engine can be an app's executable (program, folder, log, language and "keep warm" come from the environment) |
| `0018` | winecfg | "Windows Settings" title |
| `0019` | winemac (rubinot) | minimizing RubinOT hides the app (the client loses its image when miniaturized) |
| `0020` | winemac | DXMT surface follows the window size; image stretched to the view |
| `0002` | ole32 (rubinot) | `RevokeDragDrop` on another process's window (32- and 64-bit) |
| `dxmt/0001` | DXMT | builds without the Metal compiler (metallib from the official package embedded) |
| `dxmt/0002–0003` | DXMT | `CreateSwapChainForComposition` (Chromium via DirectComposition) |
| `dxmt/0004` | DXMT | minimal `SwapDeviceContextState` (used by Direct2D; before, the program crashed) |

`winapps engine-patch` reinstalls the modules from `vendor/`; `bash engine/build-engine.sh
--restore` goes back to Gcenx's originals.

### Why WebView2 needed all of this

WebView2 (Chromium) draws into a child window that belongs to another process
(`msedgewebview2.exe`), and on macOS one process can't draw into another's window. The
chain that works is:

1. Chromium's GPU process presents through DirectComposition (`dcomp` + 0007);
2. DXMT creates a composition swapchain (`patches/dxmt`) that draws into a `CAMetalLayer`
   inside a `CAContext` (0006);
3. the context id goes into a 64-byte header at
   `$TMPDIR/winemac-remote-<uid>-<hash>/<root-window>/<hwnd>-<n>.surf`;
4. the process that owns the window shows each child with a `CALayerHost`, at the Windows
   position, visibility and paint order (0010, 0012).

Power BI keeps 5 visible, overlapping WebViews and picks the active one by stacking order.
That's why 0012 is needed.

### Local Windows sign-in (`ntlm_auth.c`)

Power BI talks to the local Analysis Services using integrated Windows authentication
(NTLM). The engine delegates NTLM to an external `ntlm_auth` program, which doesn't exist on
the Mac. WinApps' `ntlm_auth` only authenticates processes of the same user: both sides
prove they can read the key `~/Library/Application Support/WinApps/ntlm-local.key` (0600).
The script puts `bin/` on the engine's `PATH`.

## Components

`winapps components <name>` accepts the winetricks ones and two of its own:

| Component | What it does |
|---|---|
| `winrt-metadata` | downloads the real `.winmd` files from Microsoft (NuGet `Microsoft.Windows.SDK.Contracts` 10.0.26100.1742, SHA-256 checked) and keeps the engine's partial ones in `windows/WinMetadata.wine-bak`. Without this, Power BI fails with `TypeLoadException` |
| `webview2` | installs the official WebView2 Runtime (x64) if it's missing |

After `dotnet40`–`dotnet48`, the script sets Windows back to version 10, because winetricks
leaves it at Windows 7. The components each program requires come from the `needs` field in
`compat.json` and from analyzing the `.exe` (`exe-kind.py --needs`).

## Installers and performance

- **WiX "Burn" installers with a .NET interface** (`mbahost.dll`, e.g. Power BI's) hang in
  the engine while loading the interface. `winapps install` reads the bundle manifest,
  extracts the embedded `.msi` files with `cabextract`, checks their SHA-1 and runs each one
  with `msiexec`. `WINAPPS_MSI_ARGS="/qn ACCEPT_EULA=1"` installs without any screens.
- **Precompiled .NET (`winapps optimize [program.exe]`).** On Windows, the .NET Framework
  comes compiled for the processor (NGEN); without that, every launch recompiles everything
  and Rosetta then translates the result. The precompilation service (`mscorsvw.exe`) loops
  in the engine and stays off; synchronous `ngen` works and turns `mscorsvw` on only for the
  duration of the call. The log is at `~/Library/Logs/WinApps/ngen.log`.
- **Game controllers (`winapps gamepad`).** The `winebus` SDL backend polls controllers
  nonstop: ~7% CPU continuously per open environment (measured on `winedevice.exe`: 2 s of
  CPU every 30 s). The default is IOHID only (`Enable SDL`=0).

## Terminal

| Command | What it does |
|---|---|
| `winapps setup` | downloads the engine and creates the environment |
| `winapps install setup.exe` | runs the installer and lists the new `.exe` files |
| `winapps shortcut "<.exe>" ["Name"]` | creates `~/Applications/Name.app`; without a name, uses `compat.json` or the product name |
| `winapps name <.exe>` | the name the shortcut would get |
| `winapps run program.exe` | runs it directly |
| `winapps detect` / `needs` / `compat` `<file>` | file analysis |
| `winapps components [names]` | installs components (no names: the essentials) |
| `winapps list` / `remove Name` / `rebuild` | shortcuts (`rebuild` keeps each one's environment) |
| `winapps dxmt on\|off\|status` | Direct3D 10/11 via Metal |
| `winapps gamepad on\|off\|status` | game controllers via SDL (default: off, no CPU cost) |
| `winapps optimize [program.exe]` | precompiles the .NET Framework (no argument) or a .NET program |
| `winapps menubar <prog.exe>\|--all on\|off` | the program's menu in the Mac menu bar |
| `winapps titlebar <prog.exe>\|--all on\|off` | the Mac title bar over the program's own bar |
| `winapps engine-patch` | reinstalls the patched engine from `vendor/` |
| `winapps kill` / `config` / `tidy` / `drive` | quit everything / Windows settings / folders and language / open C: |

## Where things live

- Engine: `~/Library/Application Support/WinApps/motor` (internal folder; not a macOS app)
- Windows environment: `~/Library/Application Support/WinApps/prefixes/default` (just one, for
  all programs; `WINAPPS_PREFIX` exists only for development tests)
- Shortcuts: `~/Applications/*.app`. Each shortcut's executable **is the engine**, named after
  the program (`Contents/MacOS/<Name>`, signed locally); settings go in the `Info.plist`
  `LSEnvironment` (`WINEPREFIX`, `WINAPPS_PROGRAM`, `WINAPPS_LOG`, `WINAPPS_LANG`,
  `WINAPPS_PERSIST`). That way macOS (Dock, ⌘ Tab, Activity Monitor, window preview apps
  like Sirena) sees a single app, with the shortcut's ID, name and icon. The `Info.plist`
  also stores `WinAppsExe` and `WinAppsPrefix`.
- Logs: `~/Library/Logs/WinApps/`; cached downloads: `~/Library/Caches/WinApps/downloads`

## Tests

`tests/` has minimal programs to isolate problems. Build them with
`x86_64-w64-mingw32-gcc` or `tests/tools/build-tests.sh`.

| Test | What it checks |
|---|---|
| `d3d11test.c` | Direct3D 11 triangle (DXMT) |
| `wv2test.c` | minimal WebView2; `popup` opens a 2nd WebView in a pop-up window |
| `xproctest.c` | one process paints inside another's window (GDI and `d3d`) |
| `docktest.c` | a child process with a window doesn't get a Dock icon |

Tools in `tests/tools/`: `wv2run.sh`, `cdp.py` (DevTools), `mdmp.py` (crash dumps),
`devinstall.sh` and `dxmt-devinstall.sh` (install modules during development). Tests for a
single program live in `../programas/<name>/testes/`.

## Known limitations

- The engine depends on Rosetta 2, which Apple will restrict starting with macOS 28.
- Not supported: games with kernel-level protection, current Office/Teams (Click-to-Run/MSIX),
  Adobe, Direct3D 12.
- Power BI: signing in to a Microsoft account and publishing to the service haven't been
  tested. An HTML dialog sometimes appears out of place.

## Credits and licenses

WinApps is GPL-3.0; the engine patches are LGPL-2.1-or-later. The engine and the included
components are free software. Notices, licenses and where the changes live are in
[LICENSES.md](LICENSES.md) ([LICENCAS.md](LICENCAS.md) in Portuguese), which ships with the
app.
