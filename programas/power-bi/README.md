# Power BI Desktop no WinApps

**Situação: ✅ Verificado** (07/11/2026) — relatórios, Power Query, Analysis Services e visuais.

## Instalação

A receita está no `winapps/compat.json` (`needs`: `dotnet48`, `winrt-metadata`, `webview2`;
depois do .NET o ambiente vai para `win10`). Basta `winapps install <PBIDesktopSetup_x64.exe>`:
o instalador WiX Burn trava no motor, então o WinApps extrai os `.msi` do pacote e roda o
`msiexec`. NGEN do .NET roda sozinho em 2º plano (abertura cai de ~90 s para ~46 s).

## Correções próprias (`patches/`)

| Patch | Módulo | O que resolve |
|---|---|---|
| `0008` | ntdll | `NtImpersonateAnonymousToken` (msmdsrv abortava) e `PagefileUsage` real no macOS (Analysis Services em "Low Memory") |
| `0009` | secur32 | `Impersonate`/`Revert`/`QuerySecurityContextToken` (login Windows local PBI ↔ Analysis Services) |
| `0016` | mshtml | zoom do login (WinForms WebBrowser/Gecko) relativo à escala de DPI — antes saía cortado |

Também usa, das gerais: WebView2 (`0006`, `0007`, `0010`–`0013`, `dxmt/0002`–`0003`), barra do
Mac (`0014`, `0015`) e o `ntlm_auth` do WinApps (`winapps/ntlm_auth.c`, precisa estar no PATH).

## Testes (`testes/`) — diagnóstico

- `pbirun.sh [log]` — abre o PBI no ambiente `teste-wv2`, fecha o aviso inicial, clica em "Blank report".
- `astest.cs` — conecta no Analysis Services local via ADOMD (compilar com o `csc` do .NET 4.8 do ambiente).
