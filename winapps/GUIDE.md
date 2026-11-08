# WinApps Guide

WinApps runs Windows programs (`.exe` and `.msi`) on your Mac. Each program becomes a Mac
app with its own name and icon, with no virtual machine.

## What to expect

- **Light and mid-size programs** (editors, utilities, .NET tools): open quickly and behave
  almost like Mac apps.
- **Heavy programs** (Power BI and similar): work, but run slower than on a Windows PC. Your
  Mac translates the processor (Rosetta) while WinApps translates Windows at the same time.
  The first launch is always the slowest.
- **Not supported:** games with kernel-level protection, current Office and Teams, and Adobe
  apps. If you pick one of these, WinApps tells you before installing.
- Compared with a virtual machine: WinApps uses much less memory and blends into the Mac,
  but a virtual machine runs more programs without surprises.

## Getting started

1. Open **WinApps**.
2. The first time, click **Set Up Windows**. It downloads the engine and installs everything
   programs need: fonts, Visual C++, DirectX, .NET Framework 4.8 and WebView2. It takes about
   15 minutes and only happens once.
3. WinApps becomes the app that opens `.exe` and `.msi` files: double-click one in the Finder
   and it opens in WinApps.

All programs share **one Windows environment**: nothing is duplicated per program, which
keeps everything lighter.

## Installing a program

- Double-click the `.exe` or `.msi` in the Finder, drag it onto the WinApps window, or click
  **Open Program** (⌘O). You can also drag in the program's **folder** or a **.zip**.
- WinApps works out what the file is on its own:
  - **installer** (`.msi` and `.exe` installers): the program is **installed**. The setup
    screens appear; follow them as usual. At the end, choose which programs go into the
    library;
  - **standalone program** (an `.exe` that runs without installing): it is **imported** into
    WinApps right away, opens, and gets an icon in the library and in Applications. A message
    confirms the import; you can delete the original file afterwards. If the `.exe` sits in
    the program's own folder (with `.dll` files, data, subfolders), the whole folder comes
    along; if it's loose in Downloads, Desktop or Documents, only the `.exe` is copied.
  - **folder or .zip**: the whole folder is imported and WinApps finds the main `.exe`. If
    there's an installer inside, it is installed instead of imported.
  - When in doubt, WinApps treats the file as a standalone program and imports it.
- If the program is listed as **Not supported** in the compatibility list, WinApps warns you
  first and suggests an alternative.
- A program that is already installed in Windows can be added to the library from the ⋯
  menu → **Advanced → Add Installed Program…**.

## Compatibility badges

Every program in the library has a badge. The **Compatibility** tab is a searchable,
filterable table of everything that has been tested; click a row to see details and the
WinApps fixes involved.

- **Verified**: tested end to end, with WinApps' own fixes. Guaranteed in this version
  (e.g. Power BI, Notepad++).
- **Works**: tested; it opens and the main tasks work.
- **Partial**: works with limitations (e.g. RubinOT).
- **Not supported**: doesn't run in WinApps; an alternative is suggested.
- **Not tested**: nobody has checked it yet; it may work.

The same list is in the repository, in `COMPATIBILITY.md`.

## How programs appear on your Mac

- Each program in the library becomes an app in **Applications** and Launchpad, with its
  original icon on a white plate shaped like Mac app icons.
- **One Dock icon per program.** Windows from helper processes (for example Power BI's
  built-in browser) belong to the same program and don't get their own icon.
- The program's name appears in the menu bar. Programs with a standard Windows menu also
  show their menus up there.
- ⌘C, ⌘V, ⌘S, ⌘Z and the other shortcuts work like Ctrl on Windows.
- After you quit a program, the engine stays ready for 10 minutes, so reopening is faster.

### Programs with their own title bar

Some programs draw their own title bar, with minimize, maximize and close buttons on the
right: Power BI, programs built on an embedded browser (WebView2/Electron) and others. They
don't get the Mac window frame, but they behave like Mac windows:

- drag the program's bar to move the window; on a maximized window, dragging restores it
  to its previous size;
- drop it at the top of the screen to maximize, or at the left or right edge to fill half
  the screen;
- drag the edges to resize;
- the **Window** menu in the menu bar has Minimize, Zoom and the macOS options to fill the
  screen or tile windows side by side.

WinApps also covers the program's bar with the **Mac title bar**, with the red, yellow and
green buttons. The green button maximizes and restores. An **Edit** menu (Undo, Copy,
Paste…) appears in the menu bar. Known programs, such as Power BI, also get their own menus
(File → Save…). Each item presses the program's keyboard shortcut. In Power BI, the Mac
title bar also has Save, Undo and Redo buttons and a **Sign In** button, and the **Power
BI** menu has "Sign In to Account…" and "Options and Settings…".

- To see the program's original bar (in Power BI it has search and sign-in): menu
  **Window → Show Program Title Bar**.
- To turn off the Mac title bar: in the WinApps ⋯ menu, **Advanced → Mac Title Bar for
  Programs with Custom Title Bars** (all programs), or right-click the program in the
  Library → **Mac Title Bar** (just that one).

## Files between the Mac and Windows

- In the programs' open and save dialogs:
  - **Windows (programs) (C:)** is where programs are installed;
  - **Mac (M:)** has your Mac folders (Desktop, Documents, Downloads, iCloud Drive…).
- The Windows Desktop, Documents and Downloads are the same folders as on your Mac.
- The **Files** tab in WinApps lets you copy and move files between the two sides.

## Power BI Desktop

Power BI Desktop works in WinApps. Tested: the start screen, blank report, sample data,
Power Query (Navigator), loading data and visuals.

### Installing it

1. Download the installer from Microsoft: **PBIDesktopSetup_x64.exe**, the download
   version, not the Microsoft Store one.
2. Open the file in WinApps. It shows *Power BI Desktop* with the **Verified** badge. What
   Power BI needs (.NET Framework 4.8, Windows metadata (WinRT) and WebView2) is already in
   the WinApps Windows environment.
3. The Power BI setup screens appear; follow them as usual. The original installer hangs on
   the Mac, so WinApps opens the package inside it directly: the screens look a little
   different from the ones on Windows.
4. At the end, the program joins the library as **Power BI**.

### Day to day

- Right after installing, WinApps spends about 5 minutes optimizing Power BI in the
  background. After that it opens much faster. The first launch is always the slowest.
- If a *"Something went wrong"* message appears on launch, close it and carry on.
- Opened reports and loaded data work as on Windows. Signing in to a Microsoft account and
  publishing to the service haven't been tested yet.
- A Power BI update may break something. If that happens, reinstall the previous version or
  wait for a new version of WinApps.

## Similar programs (.NET, WPF and WebView2)

Power BI combines the three hardest things for WinApps, so programs that use any of them
tend to work too:

- **.NET Framework with WPF screens:** WinApps installs Microsoft's .NET Framework 4.8 and
  precompiles .NET and the program, as Windows does, so they open faster.
- **.NET 6, 7, 8 or 9:** WinApps installs the runtime for the right version.
- **WebView2** (screens built with the Edge browser engine): WinApps installs the WebView2
  Runtime if it's missing, and the screens are drawn by your Mac's graphics (Metal).
- **Windows sign-in within the same computer** (programs that talk to a local service, like
  Power BI with Analysis Services): works between programs of the same user.

## Games

- Direct3D 10 and 11 graphics go straight to your Mac's graphics (Metal). Direct3D 12 is
  not supported.
- Game controllers work in light mode, which is the default. If a game doesn't recognize an
  Xbox or PlayStation controller properly, turn on ⋯ menu → **Advanced → Advanced Game
  Controllers**. It uses a little CPU all the time while any program is open.

## When something goes wrong

- **The program froze:** in the WinApps ⋯ menu choose **Quit All Windows Programs**, or run
  `winapps kill` in Terminal.
- **Blank or black screen:** quit and reopen the program. The first image of WebView2
  screens can take a few seconds.
- **Logs:** they're in `~/Library/Logs/WinApps/`, one file per program. Send that file along
  when asking for help.
- If the WinApps engine is updated, run `winapps rebuild` to recreate the shortcuts.

## Terminal (optional)

Everything the app does is also available through the `winapps` command. Run
`winapps help` to see the list. The most useful ones:

- `winapps install setup.exe`: installs a program;
- `winapps run program.exe`: opens a program without creating a shortcut;
- `winapps components`: reinstalls the Windows environment components.

## Credits

WinApps is free software and uses other free software components. Credits and licenses are
in the ⋯ menu → **About WinApps**.
