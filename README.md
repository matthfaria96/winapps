# RubinOT no macOS (Apple Silicon)

Este repositório reúne o **WinApps** (programas Windows no Mac) e o ambiente do
**RubinOT** rodando no motor do WinApps.

- **Usar o WinApps:** [winapps/GUIA.md](winapps/GUIA.md) — o mesmo texto que o app mostra
  em *Ajuda → Guia*.
- **Técnico do WinApps:** [winapps/README.md](winapps/README.md).
- **RubinOT:** [RUBINOT-21.md](RUBINOT-21.md) — instalação, componentes de
  compatibilidade, correções do motor e ajustes do cliente (janela e minimizar).
- **Programas testados:** [COMPATIBILIDADE.md](COMPATIBILIDADE.md) — tabela gerada de
  `winapps/compat.json` (a mesma que o app mostra na aba Compatibilidade).

## Ambiente do RubinOT

- Mesmo ambiente Windows de todos os programas: `~/Library/Application Support/WinApps/prefixes/default`
- App: `~/Applications/RubinOT.app` (abre `C:\RubinOT\bin\x64\rubinot_dx.exe`)
- Bibliotecas de compatibilidade, hook de janela e instalador: `rubinot/install.sh`

## Componentes (winetricks)

O ambiente usa os componentes padrão do WinApps: fontes, Visual C++ 2008–2022, DirectX
(`d3dx9`, `d3dcompiler_47`) e o WebView2 — instalados por `winapps setup` e
`winapps components`. São dependências necessárias; não precisam ser investigadas.
