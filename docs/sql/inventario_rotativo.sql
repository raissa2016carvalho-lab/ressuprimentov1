-- Inventário rotativo (23/11/2026). Tela: inventario.html. Migrações no Supabase: inventario_rotativo, acesso_nivel_inventario_coord.
-- Acessos (tela Acessos): 'inventario' = almoxarife (conta e justifica, NÃO vê saldo/custo: contagem cega);
--                         'inventario-coord' = coordenador (gera lista, vê saldo, aprova/reprova, exporta, fecha). Admin = coordenador.
-- Fluxo: coordenador gera a lista (itens de maior valor saldo×custo da SB2 nos armazéns escolhidos, pulando os contados
--   nos últimos N dias; o saldo fica CONGELADO na geração) → almoxarife conta (papel ou tela) e digita → se bater: OK;
--   se não: recontagem (mesma pessoa) → bateu: OK; não bateu: divergente → justificativa → coordenador aprova
--   (aceita a contagem) ou reprova (volta para recontagem). Sem tolerância. Exporta planilha SB7 (B7_FILIAL, B7_COD,
--   B7_LOCAL, B7_DOC, B7_QUANT, B7_DATA) com a quantidade final dos itens OK/aprovados + aba de conferência.
create table if not exists public.inv_lista (
  id bigserial primary key, filial text not null, armazens text[] not null, data_contagem date not null,
  status text not null default 'aberta', criado_por text, criado_em timestamptz not null default now(),
  fechado_por text, fechado_em timestamptz, obs text);
create table if not exists public.inv_item (
  id bigserial primary key, lista_id bigint not null references public.inv_lista(id) on delete cascade,
  codigo text not null, descricao text, unidade text, armazem text not null, localizacao text,
  saldo numeric not null, custo numeric not null default 0,
  cont1 numeric, cont1_por text, cont1_em timestamptz, cont2 numeric, cont2_por text, cont2_em timestamptz,
  status text not null default 'pendente', justificativa text, just_por text, just_em timestamptz,
  decisao_por text, decisao_em timestamptz, decisao_obs text);
-- RLS ligado e sem acesso direto (anon/authenticated); tudo passa pelas funções (security definer):
--   inv_papel() → coord | contar | ver | nenhum
--   inv_gerar(filial, armazens[], qtd, data, dias_rotacao) → id da lista (coord)
--   inv_listas(filial) / inv_itens(lista) → saldo e custo só para coord
--   inv_contar(item, qtd) → ok | recontar | divergente
--   inv_justificar(item, texto) / inv_decidir(item, aprovar, obs) / inv_status_lista(lista, aberta|fechada|cancelada)
-- acesso_nivel('inventario') também aceita quem tem 'inventario-coord'.
