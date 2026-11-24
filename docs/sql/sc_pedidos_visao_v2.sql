-- 24/11/2026 — Etapa 2 dos syncs (aplicado no banco)
-- sc_pedidos (gravada pelo sync_sc_pedidos.py, legado, que dava timeout) virou uma visão da sc_pedidos_v2 com os
-- nomes de coluna antigos. As telas que liam sc_pedidos (index, gerente, estoque) não mudaram.
-- Conferido antes: nenhuma SC existia só na antiga; 1.344 itens diferiam e a v2 estava certa (pedido refeito
-- depois de um eliminado por resíduo, pedidos novos que a antiga não tinha pego por causa do timeout).
alter table public.sc_pedidos rename to sc_pedidos_legado_bkp;
create view public.sc_pedidos with (security_invoker = true) as
select v.id, v.filial as c1_filial, v.sc_numero as c1_num, v.sc_item as c1_item, v.sc_produto as c1_produto,
       null::text as c1_grprd, null::text as c1_descgrp, v.sc_descricao as c1_descri, v.sc_unidade as c1_um,
       v.sc_quant as c1_quant, v.sc_quje as c1_quje, v.sc_cc as c1_cc, v.sc_emissao as c1_emissao, v.sc_obs as c1_obs,
       v.sc_solicitante as c1_solicit, v.sc_tipo as c1_xtiposc, v.sc_aprovacao as c1_aprov, null::text as c1_user,
       v.sc_status as status_desc, v.pc_numero, v.pc_item, v.pc_quant, v.pc_preco, v.pc_valor as pc_total,
       v.pc_fornecedor as pc_fornece, v.pc_emissao, v.pc_encerrado, v.pc_comprador, v.pc_status, v.pc_dt_entrega,
       v.pc_dt_aprovacao as pc_dt_aprov, v.atualizado_em
from public.sc_pedidos_v2 v;
revoke all on public.sc_pedidos from anon, authenticated;
grant select on public.sc_pedidos to anon, authenticated;
-- índices da antiga, agora na v2
create index if not exists idx_sc_pedidos_v2_cc_emissao on public.sc_pedidos_v2 (sc_cc, sc_emissao desc);
create index if not exists idx_sc_pedidos_v2_obs_trgm on public.sc_pedidos_v2 using gin (sc_obs gin_trgm_ops);
create index if not exists idx_sc_pedidos_v2_filial_num on public.sc_pedidos_v2 (filial, sc_numero);
create index if not exists idx_sc_pedidos_v2_produto on public.sc_pedidos_v2 (sc_produto);
-- DESFAZER: drop view public.sc_pedidos; alter table public.sc_pedidos_legado_bkp rename to sc_pedidos;
--           e voltar o sync_sc_pedidos.py no iniciar_syncs.bat.
-- A parte "consumo_filial" do sync_sc_pedidos.py também deixa de rodar: nenhuma tela lê consumo_filial.
