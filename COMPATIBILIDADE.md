# Compatibilidade do WinApps

**6 programas funcionando**, 2 verificados com correções próprias.  
✅ Verificado = testado de ponta a ponta, com correções do WinApps · 🟢 Funciona = testado ·
🟡 Parcial · ❌ Não funciona · fora da tabela = ⚪ Não testado.

> Gerado de [`winapps/compat.json`](winapps/compat.json) por `winapps/compat-md.py` (não edite à mão).
> O app mostra a mesma lista na aba **Compatibilidade**, com busca.

| Programa | Situação | Categoria | Testado | Resumo | Correções |
|---|---|---|---|---|:---:|
| [Power BI Desktop](#power-bi-desktop) | ✅ Verificado | Produtividade | 07/11/2026 | Relatórios, Power Query, Analysis Services e visuais | 4 |
| [RubinOT](#rubinot) | 🟡 Parcial | Jogos | 08/11/2026 | Joga bem, mas a sessão cai de vez em quando (reabre sozinho) | 5 |
| [Notepad++](#notepad) | ✅ Verificado | Utilitários | 07/11/2026 | Editar e salvar; menus na barra do Mac | 2 |
| [7-Zip](#7-zip) | 🟢 Funciona | Utilitários | 07/11/2026 | Abre; nome no Dock; menus na barra do Mac | — |
| [SumatraPDF](#sumatrapdf) | 🟢 Funciona | Utilitários | 07/11/2026 | Abre PDFs; barra do Mac automática | 1 |
| [PuTTY](#putty) | 🟢 Funciona | Utilitários | 07/11/2026 | Abre; nome no Dock; menus na barra do Mac | — |
| [Everything (busca de arquivos)](#everything-busca-de-arquivos) | 🟢 Funciona | Utilitários | 07/11/2026 | Abre; nome no Dock; menus na barra do Mac | — |
| [Microsoft Teams](#microsoft-teams) | ❌ Não funciona | Não suportados | — | Pacote MSIX da Microsoft Store não instala | — |
| [Microsoft Office (365 / 2016 ou mais novo)](#microsoft-office-365-2016-ou-mais-novo) | ❌ Não funciona | Não suportados | — | Instalador Click-to-Run não funciona | — |
| [Adobe Creative Cloud / Photoshop / Premiere](#adobe-creative-cloud-photoshop-premiere) | ❌ Não funciona | Não suportados | — | Depende de serviços e GPU não reproduzidos | — |
| [Jogo com proteção de kernel](#jogo-com-prote-o-de-kernel) | ❌ Não funciona | Por tecnologia | — | Anti-cheat de kernel exige um Windows real | — |
| [Programa com navegador embutido (WebView2)](#programa-com-navegador-embutido-webview2) | 🟢 Funciona | Por tecnologia | — | WebView2 já incluso e desenhado pelo Metal | — |
| [Jogo em Direct3D 12](#jogo-em-direct3d-12) | 🟡 Parcial | Por tecnologia | — | Sem Direct3D 12; use o modo Direct3D 11 do jogo | — |

## Detalhes

<details id="power-bi-desktop"><summary><b>Power BI Desktop</b> — ✅ Verificado</summary>

Funciona no motor do WinApps (testado em 07/11/2026): relatórios, Power Query, Analysis Services e visuais. Antes de instalar, o WinApps prepara o .NET Framework 4.8, os metadados do Windows (WinRT) e o WebView2. A 1ª abertura demora alguns minutos.

💡 Ao abrir, pode aparecer um aviso "Something went wrong": é só fechar. Atualizações do Power BI podem exigir uma versão nova do WinApps.

**Precisa de:** .NET 4.8, WinRT, WebView2 (já incluídos no ambiente do WinApps)

**Correções do WinApps:**
- WebView2 pelo Metal
- Login Windows local (Analysis Services)
- Barra e menus do Mac
- Zoom da tela de login

</details>

<details id="rubinot"><summary><b>RubinOT</b> — 🟡 Parcial</summary>

Testado em 08/11/2026: login, personagem no mapa, chat, inventário, loja e Battle Pass. A janela pode ser redimensionada à vontade (o jogo escala junto) e o X fecha o jogo. A sessão ainda cai de vez em quando (o cliente fecha sozinho); o vigia instalado com o jogo reabre o cliente automaticamente.

💡 Use o atalho RubinOT.app; o launcher não é necessário. A instalação usa a receita do WinApps (programas/rubinot/install.sh). Para não reabrir sozinho: crie o arquivo .rubinot-sem-vigia no ambiente.

**Precisa de:** WebView2 (já incluídos no ambiente do WinApps)

**Correções do WinApps:**
- Bibliotecas do cliente (emac, avrt)
- Janela com escala + X fecha
- Minimizar sem perder imagem
- Direct3D 11 pelo Metal
- Reabre sozinho se a sessão cair

</details>

<details id="notepad"><summary><b>Notepad++</b> — ✅ Verificado</summary>

Testado em 07/11/2026: editar e salvar arquivos, menus do programa na barra do Mac, Dock e Cmd-Tab com o nome certo.

**Correções do WinApps:**
- Menus na barra do Mac
- Direct2D estável

</details>

<details id="7-zip"><summary><b>7-Zip</b> — 🟢 Funciona</summary>

Testado em 07/11/2026: abre, nome certo no Dock, menus na barra do Mac.

</details>

<details id="sumatrapdf"><summary><b>SumatraPDF</b> — 🟢 Funciona</summary>

Testado em 07/11/2026: abre PDFs, barra de título do Mac aplicada automaticamente.

**Correções do WinApps:**
- Barra do Mac sobre a barra própria

</details>

<details id="putty"><summary><b>PuTTY</b> — 🟢 Funciona</summary>

Testado em 07/11/2026: abre, nome certo no Dock, menus na barra do Mac.

</details>

<details id="everything-busca-de-arquivos"><summary><b>Everything (busca de arquivos)</b> — 🟢 Funciona</summary>

Testado em 07/11/2026: abre, nome certo no Dock, menus na barra do Mac.

</details>

<details id="microsoft-teams"><summary><b>Microsoft Teams</b> — ❌ Não funciona</summary>

O Teams atual é distribuído como pacote MSIX da Microsoft Store, que o motor não instala.

💡 Use o Teams para Mac (oficial) ou teams.microsoft.com no navegador.

</details>

<details id="microsoft-office-365-2016-ou-mais-novo"><summary><b>Microsoft Office (365 / 2016 ou mais novo)</b> — ❌ Não funciona</summary>

O instalador Click-to-Run do Office recente não funciona no motor.

💡 Use o Office para Mac (oficial) ou office.com no navegador.

</details>

<details id="adobe-creative-cloud-photoshop-premiere"><summary><b>Adobe Creative Cloud / Photoshop / Premiere</b> — ❌ Não funciona</summary>

Os apps da Adobe dependem de serviços e de aceleração de GPU que o motor não reproduz.

💡 A Adobe tem versões oficiais para Mac.

</details>

<details id="jogo-com-prote-o-de-kernel"><summary><b>Jogo com proteção de kernel</b> — ❌ Não funciona</summary>

Este programa usa proteção de kernel, que exige um Windows de verdade.

💡 Veja se o jogo tem versão para Mac ou serviço de jogo na nuvem.

</details>

<details id="programa-com-navegador-embutido-webview2"><summary><b>Programa com navegador embutido (WebView2)</b> — 🟢 Funciona</summary>

Usa o WebView2 (navegador embutido do Edge). O WinApps instala o WebView2 Runtime se faltar e desenha as telas dele pelo Metal.

💡 Se alguma tela ficar em branco, feche e abra o programa de novo; a 1ª imagem pode levar alguns segundos.

**Precisa de:** WebView2 (já incluídos no ambiente do WinApps)

</details>

<details id="jogo-em-direct3d-12"><summary><b>Jogo em Direct3D 12</b> — 🟡 Parcial</summary>

Usa Direct3D 12, que o motor não suporta no Mac. Alguns jogos têm opção de Direct3D 11, que funciona.

💡 Procure nas opções do jogo um modo Direct3D 11 (ou -dx11 na linha de comando).

</details>
