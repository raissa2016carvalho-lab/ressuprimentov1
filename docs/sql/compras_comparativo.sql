-- Compras — 2ª entrega: Comparativo Mensal rápido
-- Tabela pronta com 1 linha por pedido × grupo (valores pelo status de cada item, de pedidos_grupo;
-- pedido sem itens em pedidos_grupo entra pelo pedido inteiro). A tela baixa só os 2 anos comparados.
-- Rodar no Supabase SQL Editor. Desfazer no fim do arquivo.

create materialized view public.mv_compras_cmp as
with ped as (
  select distinct on (trim("C7_NUM"), trim("C7_FILIAL"))
         trim("C7_NUM") num, trim("C7_FILIAL") fil, trim(coalesce("C7_CC",'')) cc, coalesce("TIPO_PEDIDO",'') tipo,
         trim(coalesce("C7_GRPPROD",'')) grp, nullif("EMISSAO_PEDIDO",'')::date dt, trim(coalesce("C7_NUMSC",'')) numsc,
         "STATUS_PEDIDO" st, coalesce("C7_TOTAL",0)::numeric total
  from public.pedidos order by trim("C7_NUM"), trim("C7_FILIAL")
),
pg as (
  select trim(c7_num) num, trim(c7_filial) fil, trim(coalesce(c7_grpprod,'')) grp, nullif(emissao,'')::date dt,
         coalesce(valor_recebido,0)::numeric rec, coalesce(valor_rec_parc,0)::numeric recparc,
         coalesce(valor_valido,0)::numeric valid, coalesce(valor_total,0)::numeric todos
  from public.pedidos_grupo
),
pgk as (select distinct num, fil from pg),
-- SCs com MOBILIZAÇÃO na observação (mesma regra da tela: MOBILIZ, sem ser "DESMOBILIZ", ou MOBIZAC)
scmob as (
  select distinct trim("C1_NUM") num, trim("C1_FILIAL") fil, nullif(trim(coalesce(pedido_num,'')),'') ped
  from public.scs
  where "C1_OBS" ilike '%mobi%' and upper("C1_OBS") ~ '(^|[^S])MOBILIZ|MOBIZAC'
),
mob as (
  select ped num, fil from scmob where ped is not null
  union
  select p.num, p.fil from ped p join scmob m on m.num = p.numsc and m.fil = p.fil
),
itens as (
  select pg.*, true por_item from pg
  union all
  -- pedido sem itens em pedidos_grupo: entra pelo pedido inteiro, pelo status do pedido
  select p.num, p.fil, p.grp, p.dt,
         case when p.st = 'Recebido' then p.total else 0 end,
         case when p.st in ('Recebido','Recebido parcialmente') then p.total else 0 end,
         case when p.st in ('Rejeitado pelo aprovador','PC Eliminado por Resíduo') then 0 else p.total end,
         p.total, false
  from ped p left join pgk k on k.num = p.num and k.fil = p.fil
  where k.num is null
)
select i.num, i.fil, coalesce(p.cc,'') cc, i.grp, i.dt, coalesce(p.tipo,'') tipo, (m.num is not null) mob,
       i.rec, i.recparc, i.valid, i.todos, i.por_item
from itens i
left join ped p on p.num = i.num and p.fil = i.fil
left join mob m on m.num = i.num and m.fil = i.fil
where i.dt is not null;
create index mv_compras_cmp_dt on public.mv_compras_cmp (dt);
create unique index mv_compras_cmp_pk on public.mv_compras_cmp (num, fil, grp, dt, por_item);

-- Linhas dos anos pedidos, em lista compacta: [num, fil, cc, grupo, data, tipo, mob, rec, recparc, valid, todos]
create or replace function public.compras_cmp_base(p_anos int[])
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_array(num, fil, cc, grp, to_char(dt,'YYYY-MM-DD'), tipo, mob,
                                            round(rec,2), round(recparc,2), round(valid,2), round(todos,2))), '[]'::json)
  from mv_compras_cmp where extract(year from dt)::int = any(p_anos)
$$;

-- Listas dos filtros do Comparativo (grupos com descrição, filiais, CCs com nome, tipos, anos) e de onde vêm os valores
create or replace function public.compras_cmp_opcoes()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'grupos', (select json_agg(json_build_array(grp, d) order by grp) from (
                 select c.grp, (select p."DESC_GRPPROD" from pedidos p where trim(coalesce(p."C7_GRPPROD",'')) = c.grp and coalesce(p."DESC_GRPPROD",'') <> ''
                                group by 1 order by count(*) desc limit 1) d
                 from (select distinct grp from mv_compras_cmp) c) x),
    'filiais', (select json_agg(fil order by fil) from (select distinct fil from mv_compras_cmp where fil <> '') x),
    'ccs',     (select json_agg(json_build_array(x.cc, c.nome) order by x.cc) from (select distinct cc from mv_compras_cmp) x
                left join centros_custo c on c.cc::text = x.cc),
    'tipos',   (select json_agg(tipo order by tipo) from (select distinct tipo from mv_compras_cmp where tipo <> '') x),
    'anos',    (select json_agg(a order by a) from (select distinct extract(year from dt)::int a from mv_compras_cmp) x),
    'por_item', (select count(*) filter (where por_item) from mv_compras_cmp),
    'por_pedido', (select count(*) filter (where not por_item) from mv_compras_cmp))
$$;
grant execute on function public.compras_cmp_base(int[]) to anon, authenticated;
grant execute on function public.compras_cmp_opcoes() to anon, authenticated;

-- Atualização: o upload_compras.py já chama atualizar_compras() no fim; agora ela atualiza também o Comparativo
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
$$;

-- DESFAZER:
-- create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
--   refresh materialized view concurrently public.mv_compras_sc;
--   refresh materialized view concurrently public.mv_compras_ped;
-- $$;
-- drop function if exists public.compras_cmp_opcoes();
-- drop function if exists public.compras_cmp_base(int[]);
-- drop materialized view if exists public.mv_compras_cmp;
