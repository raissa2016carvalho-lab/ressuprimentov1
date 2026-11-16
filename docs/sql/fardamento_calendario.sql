-- Calendário de fardamento (aba "Calendário Fardamento" do Painel de Compras) — 16/11/2026
-- Por dia × item de fardamento: recebido de fornecedor (notas de entrada, sem transferência entre filiais) e consumido (SCP),
-- somando todas as filiais; e a posição de estoque atual (SB2).
-- Transferência = TES 041/042/043 ou fornecedor que é a própria empresa (os "fornecedores" que aparecem nessas TES).
-- O dia a dia fica pronto numa visão materializada (a chave pública do painel tem limite de 3 s por consulta);
-- ela é atualizada pelo atualizar_compras(), que o upload_compras.py já chama no fim de cada rodada.

create index if not exists idx_movimentos_entrada_dtdigit on public.movimentos_entrada (dtdigit);
create index if not exists idx_movimentos_entrada_tes on public.movimentos_entrada (tes);

drop function if exists public.fardamento_calendario(int);
drop materialized view if exists public.mv_fardamento_dia;
create materialized view public.mv_fardamento_dia as
with k0 as (select emissao d, trim(produto) c, quantidade q, descricao from consumo_scp where grupo ilike 'FARDAMENTO%'),
sb as (select trim(codigo) c, descricao from estoque_sb2 where grupo ilike 'FARDAMENTO%'),
fi as (select distinct c from (select c from sb union all select c from k0) x),
tr as (select distinct fornecedor from movimentos_entrada where tes in ('041','042','043')),
r as (select m.dtdigit d, trim(m.produto) c, sum(m.qtd_entrada) q
      from movimentos_entrada m join fi on fi.c = trim(m.produto)
      where m.dtdigit >= '20250101' and coalesce(m.tes,'') not in ('041','042','043')
        and not exists (select 1 from tr where tr.fornecedor = m.fornecedor)
      group by 1,2),
k as (select d, c, sum(q) q from k0 group by 1,2),
nm as (select c, max(n) n from (select c, descricao n from sb union all select c, descricao from k0) x group by c)
select coalesce(r.d,k.d) d, coalesce(r.c,k.c) c, coalesce(r.q,0) rq, coalesce(k.q,0) kq, nm.n, now() calc_em
from r full join k on k.d = r.d and k.c = r.c
left join nm on nm.c = coalesce(r.c,k.c);
create unique index mv_fardamento_dia_pk on public.mv_fardamento_dia (d, c);

create or replace function public.fardamento_calendario(p_ano int)
returns json language sql stable security definer set search_path = public as $$
  with dia as (select d, c, rq, kq, n from mv_fardamento_dia where d between p_ano::text||'0101' and p_ano::text||'1231'),
  sb as (select trim(codigo) c, descricao, qtd_atual, custo_medio from estoque_sb2 where grupo ilike 'FARDAMENTO%'),
  fi as (select c, max(d) d from (select c, descricao d from sb union all select c, n from dia) x group by c),
  est as (select c, sum(qtd_atual) q, sum(qtd_atual * coalesce(custo_medio,0)) v from sb group by 1 having sum(qtd_atual) <> 0)
  select json_build_object(
    'itens',   (select json_agg(json_build_array(c, d) order by d) from fi),
    'dias',    (select coalesce(json_agg(json_build_array(d, c, rq, kq)), '[]'::json) from dia),
    'estoque', (select coalesce(json_agg(json_build_array(c, q, round(v,2))), '[]'::json) from est),
    'estoque_em', (select max(atualizado_em) from estoque_sb2),
    'consumo_ate', (select max(d) from dia where kq > 0),
    'entrada_ate', (select max(d) from dia where rq > 0),
    'calc_em', (select max(calc_em) from mv_fardamento_dia))
$$;
grant execute on function public.fardamento_calendario(int) to anon, authenticated;

-- ── Matriz de fardamento (16/11): cliente → categoria → SKU → CC, meses com consumo e recebimento ──
-- consumo por mês × item × CC (o recebimento vem da mv_fardamento_dia, por mês × item: nota de entrada não tem CC)
drop function if exists public.fardamento_matriz(int);
drop materialized view if exists public.mv_fardamento_cc;
create materialized view public.mv_fardamento_cc as
select mes, trim(produto) c, coalesce(nullif(trim(cc),''),'(sem CC)') cc, sum(quantidade) kq
from consumo_scp where grupo ilike 'FARDAMENTO%' group by 1,2,3;
create unique index mv_fardamento_cc_pk on public.mv_fardamento_cc (mes, c, cc);

create or replace function public.fardamento_matriz(p_ano int)
returns json language sql stable security definer set search_path = public as $$
  with k as (select mes, c, cc, kq from mv_fardamento_cc where mes between p_ano::text||'01' and p_ano::text||'12'),
  r as (select left(d,6) mes, c, sum(rq) rq from mv_fardamento_dia where d between p_ano::text||'0101' and p_ano::text||'1231' and rq > 0 group by 1,2),
  nm as (select c, max(n) n from mv_fardamento_dia group by c),
  sb as (select trim(codigo) c, sum(qtd_atual) q from estoque_sb2 where grupo ilike 'FARDAMENTO%' group by 1 having sum(qtd_atual) <> 0)
  select json_build_object(
    'cons',    (select coalesce(json_agg(json_build_array(mes, c, cc, kq)), '[]'::json) from k),
    'rec',     (select coalesce(json_agg(json_build_array(mes, c, rq)), '[]'::json) from r),
    'nomes',   (select json_object_agg(c, n) from nm where n is not null),
    'estoque', (select coalesce(json_object_agg(c, q), '{}'::json) from sb),
    'ccs',     (select json_object_agg(cc::text, nome) from centros_custo where cc::text in (select distinct cc from k)),
    'calc_em', (select max(calc_em) from mv_fardamento_dia))
$$;
grant execute on function public.fardamento_matriz(int) to anon, authenticated;

-- atualizar_compras (chamada pelo upload_compras.py) passa a atualizar também o calendário
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
  refresh materialized view concurrently public.mv_compras_precos;
  refresh materialized view concurrently public.mv_fardamento_dia;
  refresh materialized view concurrently public.mv_fardamento_cc;
$$;

-- DESFAZER:
-- create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
--   refresh materialized view concurrently public.mv_compras_sc; refresh materialized view concurrently public.mv_compras_ped;
--   refresh materialized view concurrently public.mv_compras_cmp; refresh materialized view concurrently public.mv_compras_det;
--   refresh materialized view concurrently public.mv_compras_precos;
-- $$;
-- drop function if exists public.fardamento_calendario(int); drop materialized view if exists public.mv_fardamento_dia;
-- drop function if exists public.fardamento_matriz(int); drop materialized view if exists public.mv_fardamento_cc;

-- ── Ressuprimento de fardamento (16/11): semáforo sem depender do estoque do Protheus ──
-- Por SKU: consumo e recebimento dos últimos 90 dias (mv_fardamento_dia), pedidos a caminho (Pendente / Em aprovação, com previsão
-- de entrega), último recebimento; listas dos últimos pedidos recebidos (data da nota) e dos pedidos a caminho.
-- Itens de pedido de fardamento ficam prontos em mv_fardamento_ped (com nome do fornecedor e data da nota), atualizada pelo atualizar_compras().
drop function if exists public.fardamento_ressup();
drop materialized view if exists public.mv_fardamento_ped;
create materialized view public.mv_fardamento_ped as
with nm as (select distinct c from mv_fardamento_dia),
pc as (select distinct on (trim(v.pc_filial), trim(v.pc_numero), trim(v.pc_item))
              trim(v.pc_filial) fil, trim(v.pc_numero) num, trim(v.pc_item) it, trim(v.sc_produto) c, v.pc_quant q,
              v.pc_status st, v.pc_emissao emi, v.pc_dt_entrega ent, trim(v.pc_fornecedor) forn
       from sc_pedidos_v2 v join nm on nm.c = trim(v.sc_produto)
       where v.pc_numero is not null and v.pc_emissao >= '20250101'
       order by trim(v.pc_filial), trim(v.pc_numero), trim(v.pc_item)),
ped as (select distinct on (trim("C7_FILIAL"), trim("C7_NUM")) trim("C7_FILIAL") fil, trim("C7_NUM") num, replace("ENTRADA_NOTA",'-','') ent_nf
        from pedidos where "EMISSAO_PEDIDO" >= '2025' order by trim("C7_FILIAL"), trim("C7_NUM")),
fn as (select distinct on (trim(fornecedor_cod)) trim(fornecedor_cod) cod, coalesce(nullif(trim(fornecedor_fantasia),''), fornecedor_nome) nome
       from nfe_master where coalesce(trim(fornecedor_cod),'') <> '' order by trim(fornecedor_cod), id desc)
select pc.*, ped.ent_nf, coalesce(fn.nome, pc.forn) forn_nome
from pc left join ped on ped.fil = pc.fil and ped.num = pc.num left join fn on fn.cod = pc.forn;
create unique index mv_fardamento_ped_pk on public.mv_fardamento_ped (fil, num, it);

create or replace function public.fardamento_ressup()
returns json language sql stable security definer set search_path = public as $$
  with h as (select to_char(current_date,'YYYYMMDD') hoje, to_char(current_date - 90,'YYYYMMDD') ini, to_char(current_date - 120,'YYYYMMDD') ini_rec),
  mv as (select d.c, max(d.n) n, sum(d.kq) filter (where d.d >= h.ini) k90, sum(d.rq) filter (where d.d >= h.ini) r90,
                max(d.d) filter (where d.rq > 0) ult_r, max(d.d) filter (where d.kq > 0) ult_k
         from mv_fardamento_dia d, h group by d.c),
  ur as (select m.c, sum(m.rq) q from mv_fardamento_dia m join mv on mv.c = m.c and m.d = mv.ult_r group by m.c),
  cam as (select * from mv_fardamento_ped where st in ('Pendente','Em aprovação')),
  rec as (select * from mv_fardamento_ped, h where st = 'Recebido' and ent_nf >= h.ini_rec),
  ca as (select c, sum(q) q, min(ent) prev, sum(q) filter (where ent < (select hoje from h)) atr from cam group by c)
  select json_build_object(
    'hoje', (select hoje from h),
    'skus', (select coalesce(json_agg(json_build_array(mv.c, mv.n, coalesce(mv.k90,0), coalesce(mv.r90,0), coalesce(ca.q,0), ca.prev,
                    coalesce(ca.atr,0), mv.ult_r, coalesce(ur.q,0), mv.ult_k)), '[]'::json)
             from mv left join ca on ca.c = mv.c left join ur on ur.c = mv.c
             where coalesce(mv.k90,0) > 0 or coalesce(mv.r90,0) > 0 or coalesce(ca.q,0) > 0),
    'recebidos', (select coalesce(json_agg(json_build_array(ent_nf, fil, num, forn_nome, c, q) order by ent_nf desc), '[]'::json) from rec),
    'caminho', (select coalesce(json_agg(json_build_array(fil, num, forn_nome, emi, ent, c, q, st) order by ent), '[]'::json) from cam),
    'calc_em', (select max(calc_em) from mv_fardamento_dia))
$$;
grant execute on function public.fardamento_ressup() to anon, authenticated;

-- atualizar_compras passa a atualizar também os pedidos de fardamento
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
  refresh materialized view concurrently public.mv_compras_precos;
  refresh materialized view concurrently public.mv_fardamento_dia;
  refresh materialized view concurrently public.mv_fardamento_cc;
  refresh materialized view concurrently public.mv_fardamento_ped;
$$;
-- DESFAZER: drop function if exists public.fardamento_ressup(); drop materialized view if exists public.mv_fardamento_ped;
--           (e voltar o atualizar_compras sem a linha da mv_fardamento_ped)
