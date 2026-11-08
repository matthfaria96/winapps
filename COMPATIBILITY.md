**English** · [Português](COMPATIBILIDADE.md)

# WinApps Compatibility

**6 programs working**, 2 verified with WinApps fixes.  
✅ Verified = tested end to end, with WinApps fixes · 🟢 Works = tested ·
🟡 Partial · ❌ Doesn't work · not listed = ⚪ Untested.

> Generated from [`winapps/compat.json`](winapps/compat.json) by `winapps/compat-md.py` (don't edit by hand).
> The app shows the same list, with search, in the **Compatibility** tab.

| Program | Status | Category | Tested | Summary | Fixes |
|---|---|---|---|---|:---:|
| [Power BI Desktop](#power-bi-desktop) | ✅ Verified | Productivity | Nov 7, 2026 | Reports, Power Query, Analysis Services and visuals | 4 |
| [RubinOT](#rubinot) | 🟡 Partial | Games | Nov 8, 2026 | Plays well, but the session drops now and then (reopens automatically) | 5 |
| [Notepad++](#notepad) | ✅ Verified | Utilities | Nov 7, 2026 | Edit and save; menus in the Mac menu bar | 2 |
| [7-Zip](#7-zip) | 🟢 Works | Utilities | Nov 7, 2026 | Opens; right name in the Dock; menus in the Mac menu bar | — |
| [SumatraPDF](#sumatrapdf) | 🟢 Works | Utilities | Nov 7, 2026 | Opens PDFs; Mac title bar applied automatically | 1 |
| [PuTTY](#putty) | 🟢 Works | Utilities | Nov 7, 2026 | Opens; right name in the Dock; menus in the Mac menu bar | — |
| [Everything (file search)](#everything-file-search) | 🟢 Works | Utilities | Nov 7, 2026 | Opens; right name in the Dock; menus in the Mac menu bar | — |
| [Microsoft Teams](#microsoft-teams) | ❌ Doesn't work | Not supported | — | Microsoft Store MSIX package doesn't install | — |
| [Microsoft Office (365 / 2016 or newer)](#microsoft-office-365-2016-or-newer) | ❌ Doesn't work | Not supported | — | Click-to-Run installer doesn't work | — |
| [Adobe Creative Cloud / Photoshop / Premiere](#adobe-creative-cloud-photoshop-premiere) | ❌ Doesn't work | Not supported | — | Relies on services and GPU features that aren't reproduced | — |
| [Game with kernel-level protection](#game-with-kernel-level-protection) | ❌ Doesn't work | By technology | — | Kernel-level protection requires a real Windows PC | — |
| [Program with a built-in browser (WebView2)](#program-with-a-built-in-browser-webview2) | 🟢 Works | By technology | — | WebView2 included and drawn through Metal | — |
| [Direct3D 12 game](#direct3d-12-game) | 🟡 Partial | By technology | — | No Direct3D 12; use the game's Direct3D 11 mode | — |

## Details

<details id="power-bi-desktop"><summary><b>Power BI Desktop</b> — ✅ Verified</summary>

Works in the WinApps engine (tested on Nov 7, 2026): reports, Power Query, Analysis Services and visuals. Before installing, WinApps sets up .NET Framework 4.8, the Windows metadata (WinRT) and WebView2. The first launch takes a few minutes.

💡 When it opens, a "Something went wrong" message may appear: just close it. Power BI updates may require a newer version of WinApps.

**Needs:** .NET 4.8, WinRT, WebView2 (already included in the WinApps environment)

**WinApps fixes:**
- WebView2 through Metal
- Local Windows sign-in (Analysis Services)
- Mac title bar and menus
- Sign-in screen zoom

</details>

<details id="rubinot"><summary><b>RubinOT</b> — 🟡 Partial</summary>

Tested on Nov 8, 2026: login, character on the map, chat, inventory, store and Battle Pass. You can resize the window freely (the game scales with it) and the close button quits the game. The session still drops now and then (the client closes on its own); the watchdog installed with the game reopens the client automatically.

💡 Use the RubinOT.app shortcut; the launcher isn't needed. Installation uses the WinApps recipe (programas/rubinot/install.sh). To stop it from reopening automatically, create a file named .rubinot-sem-vigia in the environment folder.

**Needs:** WebView2 (already included in the WinApps environment)

**WinApps fixes:**
- Client libraries (emac, avrt)
- Scalable window + close button quits
- Minimize without losing the picture
- Direct3D 11 through Metal
- Reopens automatically if the session drops

</details>

<details id="notepad"><summary><b>Notepad++</b> — ✅ Verified</summary>

Tested on Nov 7, 2026: editing and saving files, the program's menus in the Mac menu bar, and the right name in the Dock and Cmd-Tab.

**WinApps fixes:**
- Menus in the Mac menu bar
- Stable Direct2D

</details>

<details id="7-zip"><summary><b>7-Zip</b> — 🟢 Works</summary>

Tested on Nov 7, 2026: opens, shows the right name in the Dock, menus in the Mac menu bar.

</details>

<details id="sumatrapdf"><summary><b>SumatraPDF</b> — 🟢 Works</summary>

Tested on Nov 7, 2026: opens PDFs; the Mac title bar is applied automatically.

**WinApps fixes:**
- Mac title bar over the program's own

</details>

<details id="putty"><summary><b>PuTTY</b> — 🟢 Works</summary>

Tested on Nov 7, 2026: opens, shows the right name in the Dock, menus in the Mac menu bar.

</details>

<details id="everything-file-search"><summary><b>Everything (file search)</b> — 🟢 Works</summary>

Tested on Nov 7, 2026: opens, shows the right name in the Dock, menus in the Mac menu bar.

</details>

<details id="microsoft-teams"><summary><b>Microsoft Teams</b> — ❌ Doesn't work</summary>

Today's Teams ships as an MSIX package from the Microsoft Store, which the engine can't install.

💡 Use the official Teams for Mac or teams.microsoft.com in your browser.

</details>

<details id="microsoft-office-365-2016-or-newer"><summary><b>Microsoft Office (365 / 2016 or newer)</b> — ❌ Doesn't work</summary>

The Click-to-Run installer of recent Office versions doesn't work in the engine.

💡 Use the official Office for Mac or office.com in your browser.

</details>

<details id="adobe-creative-cloud-photoshop-premiere"><summary><b>Adobe Creative Cloud / Photoshop / Premiere</b> — ❌ Doesn't work</summary>

Adobe apps depend on services and GPU acceleration that the engine doesn't reproduce.

💡 Adobe has official Mac versions.

</details>

<details id="game-with-kernel-level-protection"><summary><b>Game with kernel-level protection</b> — ❌ Doesn't work</summary>

This program uses kernel-level protection, which requires a real Windows PC.

💡 Check whether the game has a Mac version or a cloud gaming service.

</details>

<details id="program-with-a-built-in-browser-webview2"><summary><b>Program with a built-in browser (WebView2)</b> — 🟢 Works</summary>

Uses WebView2 (Edge's built-in browser). WinApps installs the WebView2 Runtime if it's missing and draws its screens through Metal.

💡 If a screen stays blank, quit and reopen the program; the first image may take a few seconds.

**Needs:** WebView2 (already included in the WinApps environment)

</details>

<details id="direct3d-12-game"><summary><b>Direct3D 12 game</b> — 🟡 Partial</summary>

Uses Direct3D 12, which the engine doesn't support on the Mac. Some games have a Direct3D 11 option, which works.

💡 Look for a Direct3D 11 mode in the game's options (or -dx11 on the command line).

</details>
