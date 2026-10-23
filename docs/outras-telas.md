# Outras telas

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

## fechamento.html + login_fechamento.html — Fechamento de consumo (com login)
- Tabelas: `consumo_scp`, `consumo_scp_resumo`, `mov_sd3_001`, `centros_custo`, `sync_log`,
  `justificativas_consumo` (grava justificativas).
- Cache de 4h no navegador (localStorage) para o resumo de consumo.
- Tem login próprio, e o `login_fechamento.html` faz um login separado (duplicado) — dá para unificar.
- Não foi revisado a fundo.

## manutencao.html — Manutenção de veículos
- Usa **outro projeto Supabase** (`vvwtqbehfwrgcmbjdniu`), não o do ressuprimento.
- Tabelas: `bens` (lista de veículos) e `manutencao_veiculos` (cria e altera registros).
- **Sem login** e grava com a chave pública → qualquer pessoa com o link pode criar/alterar registros,
  a menos que o RLS daquele projeto bloqueie. Não temos acesso a esse projeto pelo conector.
- Pendência: verificar RLS no projeto de manutenção.
