# index.html — Painel master

## Aba Solicitações
- Carrega só solicitações `pendente` e `aguardando_master` (bem mais leve).
- Cards agrupados por **mesma matrícula + janela de 3 min**, ou pelo campo `grupo_envio` quando preenchido
  (função `_chaveGrupo`).
- Colunas do card: consumo, **estoque da filial = posição gravada no envio** (com a data; sem "ao vivo"),
  cobertura, qtd digitada, total, **qtd gerente** (`qtd_gerente`; mostra "—" até o gerente avaliar),
  justificativa do gerente, último pedido, **qtd master**, **Ação** e colunas por CC.
- **Coluna Ação** (`_htmlAcao`): estoque no envio − consumo até o início do período
  (1º dia do mês daqui a 2 meses) comparado com a Qtd master →
  ✅ estoque cobre / 🟡 complementar (comprar N) / 🔴 comprar tudo / ⚪ sem posição.
  Mostra sempre o **sugerido** (consumo × meses do pedido − estoque que sobra) e um alerta discreto
  **⚠ N× consumo** quando o pedido passa de 1,5× o esperado.
- **Consumo (out/2026)**: média = total dos **últimos 6 meses ÷ 6** (meses sem saída contam zero), igual em
  painel, formulário e gerente. Tipo de saída: 🟢 regular (5–6 meses com saída), 🟡 intermitente (3–4),
  🔸 pontual (1–2). No pontual a meta é ter **o maior pico** em estoque (não média × período) e o estoque
  não é descontado até o início do período. Antes a média dividia só pelos meses com saída (inflava ~5× nos pontuais).
- Botão **↺** por item: volta ao valor do gerente (ou do almoxarife).
- Registro de quem alterou no master: "✎ usuário · data" (colunas `master_alterado_por/em`).
- Salvar em lotes paralelos de 10 (antes era um item por vez).
- **Valor estimado** usa o **último preço de compra** (`ultimo_preco_compra`); sem pedido, preço do cadastro;
  custo médio da filial só se não estiver distorcido (>5× fora do cadastro).
- Todas as buscas paginadas têm `.order('id')` (sem isso a paginação pulava linhas e sumia histórico de consumo).

## Aba Visão Gerentes
- Um card por gerente (recolhido), abas por status: Em aberto / Avaliadas / Aprovadas / Parciais / Recusadas.
- Só solicitações a partir de **01/10/2026**.
- `gerentes_cc.cc` é número e `solicitacoes.cc` é texto — sempre comparar como texto.

## Aba Mobilização → ver `docs/mobilizacao.md`
