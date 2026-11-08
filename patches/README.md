# Patches do motor

Correções **gerais** (servem a qualquer programa). As que só um programa precisa ficam na
pasta dele: `programas/<nome>/patches/`. O `engine/build-engine.sh` junta as duas origens e
aplica tudo na **ordem do número** (o número é global; não repetir).

| Patch | Módulo | Tema |
|---|---|---|
| `0003` | win32u | barra de menu presa na largura antiga |
| `0004` | winemac | menu do programa na barra do macOS |
| `0005` | winemac | DXMT (Direct3D 10/11 → Metal) |
| `0006` `0007` `0010`–`0013` | win32u, winemac, dcomp | janelas-filhas de outro processo (WebView2/Chromium) |
| `0014` `0015` | winemac | barra de título própria + barra/menus do Mac |
| `0017` | ntdll | nomes próprios (WinApps), motor como executável do atalho |
| `0018` | winecfg | "Configurações do Windows" |
| `0020` | winemac | superfície do DXMT acompanha o tamanho da janela |
| `dxmt/0001`–`0004` | DXMT | build sem compilador Metal, swapchains de composição, `SwapDeviceContextState` (`engine/build-dxmt.sh`) |
| `diag/` | kernelbase | **só diagnóstico** (DevTools no WebView2); não é aplicado pelo build |

Por programa:

- `programas/rubinot/patches/` — `0002` ole32, `0019` minimizar esconde o app
- `programas/power-bi/patches/` — `0008` ntdll, `0009` secur32, `0016` mshtml

Detalhes de cada um: [`winapps/README.md`](../winapps/README.md#engine-patches).
