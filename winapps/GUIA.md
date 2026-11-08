# Guia do WinApps

O WinApps roda programas do Windows (`.exe` e `.msi`) no Mac. Cada programa vira um app
do Mac, com nome e ícone próprios, sem precisar de uma máquina virtual.

## O que esperar

- **Programas leves e médios** (editores, utilitários, ferramentas .NET): abrem rápido e
  se comportam quase como apps do Mac.
- **Programas pesados** (Power BI e parecidos): funcionam, mas ficam mais lentos que num PC
  com Windows. O Mac traduz o processador (Rosetta) e o WinApps traduz o Windows ao mesmo
  tempo. A primeira abertura é a mais demorada.
- **Não funcionam:** jogos com proteção de kernel, o Office e o Teams atuais, e os apps da Adobe.
  Ao escolher um desses, o WinApps avisa antes de instalar.
- Em comparação com uma máquina virtual: o WinApps gasta bem menos memória e se integra ao
  Mac, mas a máquina virtual roda mais programas sem surpresas.

## Primeiros passos

1. Abra o **WinApps**.
2. Na primeira vez, clique em **Preparar o Windows**. Ele baixa o motor e já instala tudo o
   que os programas precisam: fontes, Visual C++, DirectX, .NET Framework 4.8 e WebView2.
   Leva uns 15 minutos e só acontece uma vez.
3. O WinApps passa a ser o app que abre arquivos `.exe` e `.msi`: dois cliques num deles no
   Finder já abrem no WinApps.

Todos os programas rodam no **mesmo ambiente Windows**: nada é copiado por programa, o que
deixa tudo mais leve.

## Instalar um programa

- Dê dois cliques no `.exe` ou `.msi` no Finder, arraste para a janela do WinApps ou clique
  em **Abrir programa** (⌘O). Também vale arrastar a **pasta** do programa ou um **.zip**.
- O WinApps descobre sozinho o que é o arquivo:
  - **instalador** (`.msi` e instaladores `.exe`): o programa é **instalado**. As telas de
    instalação aparecem; siga normalmente. No fim, marque quais programas vão para a
    biblioteca;
  - **programa solto** (um `.exe` que roda sem instalar): ele é **importado** para o WinApps
    na hora, abre e ganha um ícone na biblioteca e em Aplicativos. Um aviso confirma a
    importação; o arquivo original pode ser apagado depois. Se o `.exe` estiver na pasta
    própria do programa (com `.dll`, dados, subpastas), a pasta inteira vai junto; solto em
    Downloads, Mesa ou Documentos, só o `.exe` é copiado.
  - **pasta ou .zip**: a pasta inteira é importada e o WinApps acha o `.exe` principal. Se
    dentro houver um instalador, ele é instalado em vez de importado.
  - Na dúvida, o WinApps trata o arquivo como programa solto e importa.
- Se o programa estiver na lista de compatibilidade como **Não funciona**, o WinApps avisa
  antes e sugere uma alternativa.
- Um programa que já está instalado no Windows entra na biblioteca pelo menu ⋯ →
  **Avançado → Adicionar programa já instalado**.

## Selos de compatibilidade

Cada programa da biblioteca tem um selo. A aba **Compatibilidade** é uma tabela com busca e
filtro de todos os testados; clique numa linha para ver detalhes e as correções do WinApps.

- **Verificado**: testado de ponta a ponta, com correções próprias do WinApps. Garantido
  nesta versão (ex.: Power BI, Notepad++).
- **Funciona**: testado; abre e o uso principal funciona.
- **Parcial**: funciona com limitações (ex.: RubinOT).
- **Não funciona**: não roda no WinApps; há uma alternativa indicada.
- **Não testado**: ninguém conferiu ainda; pode funcionar.

A mesma lista está no repositório, em `COMPATIBILIDADE.md`.

## Como os programas aparecem no Mac

- Cada programa da biblioteca vira um app em **Aplicativos** e no Launchpad, com o ícone
  original numa placa branca no formato dos ícones do Mac.
- **Um ícone no Dock por programa.** Janelas de processos auxiliares (por exemplo o
  navegador embutido do Power BI) fazem parte do mesmo programa e não ganham ícone próprio.
- O nome do programa aparece na barra de menus. Programas com menu padrão do Windows
  também mostram o menu deles lá em cima.
- ⌘C, ⌘V, ⌘S, ⌘Z e os outros atalhos funcionam como o Ctrl do Windows.
- Depois de fechar um programa, o motor fica pronto por 10 minutos: reabrir é mais rápido.

### Programas com barra de título própria

Alguns programas desenham a própria barra de título, com os botões de minimizar,
maximizar e fechar à direita: Power BI, programas feitos com navegador embutido
(WebView2/Electron) e outros. Eles não ganham a moldura do Mac, mas se comportam como
janelas do Mac:

- arraste a barra do programa para mover a janela; numa janela maximizada, o arraste já a
  solta no tamanho anterior;
- solte no topo da tela para maximizar, ou na borda esquerda ou direita para ocupar metade
  da tela;
- puxe as bordas para redimensionar;
- no menu **Janela** da barra de menus ficam Minimizar, Zoom e as opções do macOS para
  preencher a tela ou pôr lado a lado.

O WinApps também troca a barra do programa pela **barra de título do Mac**, com os botões
vermelho, amarelo e verde. O verde maximiza e restaura. Na barra de menus aparece um menu
**Editar** (Desfazer, Copiar, Colar…). Programas conhecidos, como o Power BI, ganham também
menus próprios (Arquivo → Salvar…). Cada item aperta o atalho de teclado do programa. No
Power BI, a barra do Mac tem também os botões Salvar, Desfazer e Refazer e o botão **Entrar**,
e o menu **Power BI** tem "Entrar na Conta…" e "Opções e Configurações…".

- Para ver a barra original do programa (no Power BI ela tem a busca e o login): menu
  **Janela → Mostrar a Barra do Programa**.
- Para desligar a barra do Mac: no menu ⋯ do WinApps, **Avançado → Barra de título do Mac
  em programas com barra própria** (todos), ou botão direito no programa na Biblioteca →
  **Barra de título do Mac** (só ele).

## Arquivos entre o Mac e o Windows

- Nas janelas de abrir e salvar dos programas:
  - **Windows (programas) (C:)** é onde os programas ficam instalados;
  - **Mac (M:)** tem suas pastas do Mac (Mesa, Documentos, Downloads, iCloud Drive…).
- A Área de Trabalho, os Documentos e os Downloads do Windows são as mesmas pastas do Mac.
- Na aba **Arquivos** do WinApps você copia e move arquivos entre os dois lados.

## Power BI Desktop

O Power BI Desktop funciona no WinApps. Foram testados a tela inicial, o relatório em
branco, os dados de exemplo, o Power Query (Navegador), o carregamento dos dados e os
visuais.

### Como instalar

1. Baixe o instalador no site da Microsoft: **PBIDesktopSetup_x64.exe**, a versão para
   download e não a da Microsoft Store.
2. Abra o arquivo no WinApps. Ele mostra *Power BI Desktop* com o selo **Verificado**. O
   que o Power BI precisa (.NET Framework 4.8, metadados do Windows (WinRT) e WebView2) já
   vem no ambiente Windows do WinApps.
3. As telas de instalação do Power BI aparecem; siga normalmente. O instalador original
   trava no Mac, então o WinApps abre direto o pacote que vem dentro dele: as telas são um
   pouco diferentes das do Windows.
4. No fim, o programa entra na biblioteca como **Power BI**.

### No dia a dia

- Logo depois de instalar, o WinApps passa uns 5 minutos otimizando o Power BI em segundo
  plano. Depois disso ele abre bem mais rápido. A primeira abertura é sempre a mais lenta.
- Se aparecer o aviso *"Something went wrong"* ao abrir, feche-o e continue.
- Os relatórios abertos e os dados carregados funcionam como no Windows. O login na conta
  Microsoft e a publicação no serviço ainda não foram testados.
- Uma atualização do Power BI pode quebrar algo. Se isso acontecer, reinstale a versão
  anterior ou espere uma versão nova do WinApps.

## Programas parecidos (.NET, WPF e WebView2)

O Power BI junta as três coisas mais difíceis para o WinApps, então programas que usam
alguma delas tendem a funcionar também:

- **.NET Framework com telas WPF:** o WinApps instala o .NET Framework 4.8 da Microsoft e
  pré-compila o .NET e o programa, como o Windows faz, para eles abrirem mais rápido.
- **.NET 6, 7, 8 ou 9:** o WinApps instala o runtime da versão certa.
- **WebView2** (telas feitas com o navegador do Edge): o WinApps instala o WebView2 Runtime
  se ele faltar, e as telas são desenhadas pela placa de vídeo do Mac (Metal).
- **Login do Windows dentro do próprio computador** (programas que conversam com um serviço
  local, como o Power BI com o Analysis Services): funciona entre programas do mesmo usuário.

## Jogos

- Os gráficos Direct3D 10 e 11 vão direto para a placa de vídeo do Mac (Metal). O Direct3D 12
  não funciona.
- Controles de jogo funcionam no modo leve, que é o padrão. Se um jogo não reconhecer bem o
  controle de Xbox ou PlayStation, ligue no menu ⋯ → **Avançado → Controles de jogo avançados**.
  Ela usa um pouco de CPU o tempo todo enquanto algum programa estiver aberto.

## Quando algo dá errado

- **O programa travou:** no menu ⋯ do WinApps escolha **Fechar todos os programas
  Windows**, ou rode `winapps kill` no Terminal.
- **Tela em branco ou preta:** feche e abra o programa de novo. A primeira imagem de telas
  WebView2 pode demorar alguns segundos.
- **Registros (logs):** ficam em `~/Library/Logs/WinApps/`, um arquivo por programa. Mande
  esse arquivo junto quando for pedir ajuda.
- Se o motor do WinApps for atualizado, rode `winapps rebuild` para refazer os atalhos.

## Terminal (opcional)

Tudo o que o app faz também existe no comando `winapps`. Rode `winapps help` para ver a
lista. Os mais úteis:

- `winapps install setup.exe`: instala um programa;
- `winapps run programa.exe`: abre um programa sem criar atalho;
- `winapps components`: reinstala os componentes do ambiente Windows.

## Créditos

O WinApps é software livre e usa outros componentes de software livre. Os créditos e as
licenças ficam no menu ⋯ → **Sobre o WinApps** (antes chamado "Créditos e licenças").
