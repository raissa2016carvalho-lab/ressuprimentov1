# Outras telas

## ruptura.html — Risco de Ruptura (out/2026, sem login)
- **Visual igual ao `estoque.html` (Posição)** desde 26/10: topo escuro, filtros, botões-pílula, cartões, tabela ordenável
  (clique no título) com 100 linhas por página, Excel da lista filtrada. Uma linha por **filial × item** de EPI/EPC/Ferramentas e Fardamento.
- **Tela inicial = cartões por filial** (27/10): nome, SKUs (filial × item), quantos A/B/C (curva da própria filial), itens a romper
  (= "Pedir agora", com valor e quantos são curva A), barra Pedir/Já solicitado/Depende/Normal, PCs atrasados. Ordenados por itens a romper.
  Clique abre a lista da filial ("← Filiais" volta; "Ver lista de todas as filiais" abre tudo). Na lista, SC aberta e Pedido mostram também o status
  (Bloqueada/Pendente/Em cotação; Pendente/Em aprovação/...).
- **Botão "Top itens"** (27/10): cartão por código somando todas as filiais (top 30 + "ver mais 30"), com curva ABC da empresa,
  filiais a romper (de quantas têm o item), saída/mês (consumo ou trocas, o maior, somado), estoque, cobertura, SC aberta, a caminho,
  PCs atrasados e onde vai romper. Ordem: mais saem (padrão) / mais filiais a romper / maior valor a comprar. Clique abre o item filial por filial.
- Lê `itens`, `estoque_sb2` (qtd_atual, `saldo_pedido` = a caminho; negativo vira 0), `consumo_mensal` (6 meses ÷ 6),
  `sc_pedidos_v2`, `filiais` e a função `trocas_previstas`.
  - **SC aberta**: `pc_numero` vazio e status Pendente / Bloqueada / Em Processo de Cotação, emitida no último ano; qtd = `sc_quant - sc_quje`.
  - **Pedido em aberto**: status Pendente / Em aprovação / Recebido parcialmente / Em recebimento (Pré-nota) / Sem status, entrega a partir de 180 dias atrás;
    atrasado = entrega vencida. Passar o mouse mostra todos os PCs/SCs (fornecedor, comprador, solicitante).
- **Curva ABC** (filtro + coluna, 26/10): calculada na hora dentro da filial e do grupo escolhidos (busca e tipo de saída não mudam a classe).
  Peso = saída por mês (o maior entre consumo médio e trocas previstas ÷ prazo) × custo médio, ou só a quantidade ("ABC por").
  A = linhas que somam 80% do peso, B = próximos 15%, C = últimos 5%; sem saída = sem classe. Com "Todas as filiais" classifica cada filial × item.
- **Auditoria do último formulário** (27/10) — metodologia para apresentar à gerência (piloto: Cascavel, estoque 100%):
  - Último formulário = rodada mais recente da filial em `solicitacoes` (status ≠ recusada; junta formulários até 15 dias antes do último, todos os CCs).
    Itens em `solicitacao_itens`: `qtd_sugerida` (sistema) → `qtd_almoxarife` → `qtd_gerente` → `quantidade` (final do master; roxo = mudou), `situacao` recusado.
  - A final de formulário **sem SC** conta como já pedida (situação "No formulário"); depois que vira SC passa a contar pela SC aberta / pedido.
  - Veredito por item: ✅ coberto · ✂️ cortado e vai faltar · 🚫 recusado e vai faltar · ⚠ pedido não cobre · ❗ ficou de fora
    (o painel pede e o item não estava no formulário) · ➕ pediu a mais (final > 2× o que faltava e ≥ 3 un a mais).
  - Na lista da filial: cartão roxo com nº/CC/status/solicitante, quantos itens cada um mexeu, recusados e os vereditos com valor.
    Cartão da filial mostra a data/status do formulário. Excel traz as colunas do formulário.
  - ⚠ Lê `solicitacoes`/`solicitacao_itens` com a chave pública: quando fizer a **RLS fase C**, liberar leitura dessas colunas para esta tela
    (ou criar uma função só de leitura), senão a auditoria some (o resto do painel continua).
- **Tirar do consumo** (27/10): caixinhas Mobilização e Admissional, **as duas desmarcadas por padrão** (a Raissa ainda não confia
  no consumo e está em período de ressuprimento — preferiu não deixar de comprar). Itens com 30% ou mais da saída de 6 meses por
  mobilização ganham a marca roxa "% mobilização" (pílula "🟣 Mobilização pesa"; também nos cartões do Top itens). Desconta do `consumo_mensal` as saídas desses motivos
  (`consumo_por_motivo` sobre o `consumo_scp`, que bate com o `consumo_mensal` em 99,6% dos filial × item × mês). Motivo nas entregas:
  1 perda, 2 roubo, 3 desgaste, 4 defeito, 5 admissional, 6 mal uso, 7 manutenção, 8 transferência, 9 consumo, **A mobilização**, C complementação.
  Motivo: itens caros como detector de tensão saem em kits de equipe nova — compra direcionada, não ressuprimento (pedido da gerente).
  O `*` roxo no consumo mostra quanto foi tirado. Se a função falhar, segue com todo o consumo e mostra aviso.
- Prazo do grupo fixo no código (p80 SC→chegada em 2026): EPI 71 dias, fardamento 99 dias (`PRAZO`).
- Meta: regular/intermitente = média × prazo; pontual = maior pico; maior entre isso e as trocas previstas.
- Situação: **Pedir agora** (estoque + a caminho + SC aberta < meta); **Já solicitado** (só cobre contando a SC aberta);
  **Depende da entrega** (estoque < meta ≤ estoque + a caminho); Normal; Sem saída. Pílulas extras: zerados com saída, pedido atrasado,
  SC aberta, pode transferir (filial com estoque > 6 meses de consumo).
- **Trocas previstas** (26/10): `trocas_previstas(71, 99)` devolve, por filial × código, as trocas de itens pessoais que caem dentro do
  prazo do grupo (vencidas contam como hoje; item de vida curta conta mais de uma troca; no máximo 4 unidades por pessoa). Usa o
  **código/tamanho que a pessoa recebeu por último** e a filial da entrega mais recente dela. Número azul = a meta veio das trocas.
- **Botão "Vida útil e trocas"** no topo: pílulas Vencidas / Próximos 30 / 90 dias / Todas (lê `vw_trocas_pessoa` com `dias <= 90`,
  carrega depois do resto) e "Vida útil por item" (`mv_vida_util`, tamanhos juntos, faixa p25–p75). Busca aceita matrícula.
  Pessoa ativa = recebeu algo nos últimos 60 dias; troca atrasada mais que 1 vida útil sai da lista.
  Entregas não têm o nome do funcionário (o `solicitante` é o almoxarife) — só matrícula e CC.
- Próximas etapas combinadas: mínimos de itens críticos (NR-10/altura) por equipe, reserva de mobilização,
  grade de fardamento semestral, alerta de formulário não enviado, contratos com fornecedor (compras).

## los.html — Menu inicial
Página com os links para todas as telas. Sem banco de dados.

## formulario.html — Solicitação de ressuprimento (almoxarife, sem login)
- Escolhe filial e CCs, mostra itens dos grupos permitidos (`cc_grupos`) com quantidade sugerida pelo
  consumo médio (`consumo_mensal`); cache de 4h no navegador (sessionStorage).
- Rascunho automático no navegador (localStorage).
- Envia pela função do banco `criar_solicitacao` (uma solicitação por CC). O **banco** grava a posição
  de estoque da filial (`estoque_sb2`) e a data no momento do envio.
- Textos digitados passam pelo gatilho `limpar_texto` (anti-XSS).
- Itens "MANUAL" (sem código) são permitidos.
- Pendência: não foi otimizado nem revisado a fundo.

## gerente.html → ver `docs/gerente.md`

## estoque.html — Posição de estoque (sem login)
- Aba **Posição**: baixa o `estoque_sb2` inteiro + `consumo_anual` inteiro a cada abertura.
- Aba **Comparativo** (por filial): baixa `itens` inteiro (38 mil linhas), `movimentos_entrada`,
  `mov_transf_env`, `mov_sd3_entrada` (TM 005/503/999), `mov_sd3_saida` (TM 501/499/001).
- Lê também `bases_status`, `sc_pedidos`, `pedidos_compra`, `consumo_anual`.
- Paginação sem `.order()` → pode pular/repetir linhas (mesmo problema já corrigido no index).
- Em 22/10 deu "statement timeout" quando vários syncs rodavam juntos (não era o RLS).
- **Pendência**: otimizar (ordem fixa na paginação, não baixar `itens` inteiro, cache).

## compras.html — Painel de compras (sem login)
- Baixa as tabelas `scs` (~105 mil linhas) e `pedidos` (~27 mil) **inteiras** a cada abertura, via REST
  (`sbGet`), e monta gráficos (Chart.js).
- Filtro de data padrão = últimos 12 meses, mas tudo é baixado.
- **Pendência**: reaplicar a versão "carrega só 12 meses e busca o resto sob demanda"
  (commits `f849d5d` e `8137792` no histórico do branch `claude/kind-volta-7vg1nq`), recriando antes os
  índices `idx_scs_emissao ("C1_EMISSAO","C1_NUM","C1_ITEM","C1_FILIAL")` e
  `idx_pedidos_emissao ("EMISSAO_PEDIDO","C7_NUM","C7_FILIAL")` — só depois que os syncs estiverem leves.

- **Aba Comparativo Mensal** (out/2026): ano × ano anterior, mês a mês, filtro de grupo/filial/tipo/status
  (padrão "só recebidos"). Lê a tabela `pedidos_grupo` (valores por pedido × grupo, separados pelo
  status de **cada item**, gerada pelo `upload_compras.py` a partir da `BEQ_LWH.dbo.LWHSC7010`).
  Sem essa tabela, usa `pedidos` e mostra aviso vermelho.
- Por que não usar só `pedidos`: o sync agrupa por pedido com `MAX(STATUS_PEDIDO)` e `MAX(C7_GRPPROD)` —
  pedido com itens eliminados por resíduo + 1 recebido vira "Recebido" com valor cheio
  (ex.: pedido 274748 filial 14: R$ 326 mil no site, R$ 5.950 recebidos de verdade).
- `scs.pedido_preco/pedido_total` vêm ×10 (o sync tira o ponto decimal de "5950.0") → aba Detalhamento.
- Paginação com `order` pela chave primária + aviso no topo se a carga vier incompleta.
- Validação no DBeaver: `BEQ_LWH.dbo.LWHSC7010` (C7_TOTAL é texto; usar `TRY_CAST(REPLACE(C7_TOTAL,',','.') AS DECIMAL(18,4))`,
  status do item em `STATUS_DESC`, grupo em `C7_GRPPROD`). Usuário raissa.carvalho não acessa `BEQ_DWH`.

## fechamento.html — Fechamento de consumo (com login Supabase Auth)
- Tabelas: `consumo_scp_resumo` (carga principal), `consumo_scp`, `mov_sd3_001` (devoluções), `centros_custo`,
  `filiais`, `sync_log`, `justificativas_consumo` (grava justificativas + `atualizado_por`).
- Cache no navegador (localStorage) renovado automaticamente quando o `sync_log` (consumo_scp) muda; botão
  **↻ Atualizar dados** descarta o cache.
- Devoluções e Comparativo buscam o `mov_sd3_001` página por página (antes cortava em 1000 linhas; há meses com 1.394).
- Filtro de filial montado a partir dos dados + nomes da tabela `filiais`.
- `login_fechamento.html` removido (era um segundo login que só redirecionava).
- Pendente (SQL no SQL Editor): RLS em `justificativas_consumo` — só usuários logados leem/gravam.

## manutencao.html — Manutenção de veículos
- Usa **outro projeto Supabase** (`vvwtqbehfwrgcmbjdniu`), não o do ressuprimento.
- Tabelas: `bens` (lista de veículos) e `manutencao_veiculos` (cria e altera registros).
- **Sem login** e grava com a chave pública → qualquer pessoa com o link pode criar/alterar registros,
  a menos que o RLS daquele projeto bloqueie. Não temos acesso a esse projeto pelo conector.
- Pendência: verificar RLS no projeto de manutenção.
