# gerente.html — Link dos gerentes

- Mostra só as solicitações `pendente` dos CCs ligados ao e-mail do gerente em `gerentes_cc`,
  criadas a partir de **01/10/2026** (`DATA_INICIO_GERENTES`).
- Sem informações de compras (busca em `sc_pedidos_v2` e coluna "Em compra" removidas; aba "Acompanhar SCs" escondida).
- Consumo paginado (antes cortava em 1000 linhas e itens ficavam sem consumo).
- Cada card matricial é identificado por `mat-<id da solicitação>` (antes a justificativa abria no card errado).
- **Justificativa obrigatória só quando a quantidade AUMENTA.**
- Botão **↺** volta à quantidade original e desfaz recusa.
- **Rascunho**: automático no navegador (localStorage, 7 dias) + botão **💾 Salvar rascunho** na tabela
  `rascunhos_gerente` (abre em qualquer computador; vale o mais recente).
- Ao avaliar, grava `qtd_gerente` (não é mais sobrescrito pelo master).
- Valor estimado pelo último preço de compra.
