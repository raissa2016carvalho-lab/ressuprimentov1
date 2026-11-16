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

-- atualizar_compras (chamada pelo upload_compras.py) passa a atualizar também o calendário
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
  refresh materialized view concurrently public.mv_compras_precos;
  refresh materialized view concurrently public.mv_fardamento_dia;
$$;

-- DESFAZER:
-- create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
--   refresh materialized view concurrently public.mv_compras_sc; refresh materialized view concurrently public.mv_compras_ped;
--   refresh materialized view concurrently public.mv_compras_cmp; refresh materialized view concurrently public.mv_compras_det;
--   refresh materialized view concurrently public.mv_compras_precos;
-- $$;
-- drop function if exists public.fardamento_calendario(int); drop materialized view if exists public.mv_fardamento_dia;
