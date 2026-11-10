-- Compras — aba "Variação de preço": itens com maior variação no preço unitário dos pedidos e os últimos preços
-- Preço unitário = valor do item do pedido ÷ quantidade (pedidos_compra). Fora: rejeitado pelo aprovador e sem status.
-- Rodar no Supabase SQL Editor. Desfazer no fim do arquivo.

create materialized view public.mv_compras_precos as
select pc.id, trim(pc.c7_produto) produto, trim(pc.c7_descri) descri, trim(coalesce(pc.c7_um,'')) um,
       trim(coalesce(pc.c7_grpprod,'')) grp, trim(pc.c7_filial) fil, trim(pc.c7_num) num,
       to_date(pc.c7_emissao,'YYYYMMDD') dt, pc.c7_quant qtd, round(pc.c7_total / pc.c7_quant, 4) preco,
       trim(coalesce(pc.c7_fornece,'')) forn_cod, coalesce(nullif(trim(p.fornecedor),''), trim(coalesce(pc.c7_fornece,''))) forn,
       trim(coalesce(pc.c7_comprador,'')) comprador, pc.status_desc st,
       (trim(coalesce(pc.c7_grpprod,'')) like '3%' or trim(coalesce(pc.c7_grpprod,'')) like '4%') servico
from public.pedidos_compra pc
left join public.mv_compras_ped p on trim(p.num) = trim(pc.c7_num) and p.fil = trim(pc.c7_filial)
where pc.c7_quant > 0 and pc.c7_total > 0 and pc.c7_emissao ~ '^\d{8}$'
  and coalesce(pc.status_desc,'') not in ('REJEITADO PELO APROVADOR','SEM STATUS');
create unique index mv_compras_precos_pk on public.mv_compras_precos (id);
create index mv_compras_precos_prod on public.mv_compras_precos (produto, dt desc);
create index mv_compras_precos_dt on public.mv_compras_precos (dt);

-- Lista de itens com a variação no período (mín./máx./médio, último e penúltimo preço)
-- Preço fora do padrão (mais de 5x abaixo ou acima da mediana do item no período, ex.: R$ 0,01 de base de troca,
-- garantia ou unidade diferente) não entra na conta; a coluna 'fora' mostra quantos foram ignorados.
-- p_ordem: 'var' (maior diferença entre o menor e o maior preço), 'subiu' (último × anterior, maior alta),
--          'desceu' (maior queda), 'valor' (mais comprado em R$)
create or replace function public.compras_precos(p_ini date default null, p_fim date default null, p_grp text default null,
  p_fil text default null, p_q text default null, p_servicos boolean default false, p_min int default 2,
  p_ordem text default 'var', p_off int default 0, p_lim int default 20)
returns json language sql stable security definer set search_path = public
  set enable_nestloop = off set plan_cache_mode = force_custom_plan as $$   -- evita o cruzamento linha a linha (lento)
with b as materialized (
  select * from mv_compras_precos
  where (p_ini is null or dt >= p_ini) and (p_fim is null or dt <= p_fim)
    and (p_grp is null or grp = p_grp) and (p_fil is null or fil = trim(p_fil))
    and (p_servicos or not servico)
    and (p_q is null or produto ilike '%'||trim(p_q)||'%' or descri ilike '%'||trim(p_q)||'%')
),
md as (select produto, percentile_cont(0.5) within group (order by preco) med from b group by produto),
bf as (select b.*, (b.preco between md.med/5 and md.med*5) ok from b join md using (produto)),
fo as (select produto, count(*) fora from bf where not ok group by produto),
a as (
  select produto, max(descri) descri, max(um) um, max(grp) grp, count(*) n, sum(qtd*preco) valor,
         min(preco) pmin, max(preco) pmax, sum(qtd*preco)/nullif(sum(qtd),0) pmed,
         (array_agg(preco order by dt desc, num desc))[1] ult, (array_agg(dt order by dt desc, num desc))[1] ult_dt,
         (array_agg(forn order by dt desc, num desc))[1] ult_forn, (array_agg(fil order by dt desc, num desc))[1] ult_fil,
         (array_agg(preco order by dt desc, num desc))[2] ant, (array_agg(dt order by dt desc, num desc))[2] ant_dt
  from bf where ok group by produto having count(*) >= greatest(coalesce(p_min,2),1)
),
z as (select a.*, coalesce(fo.fora,0) fora, case when pmin > 0 then pmax/pmin - 1 end var, case when ant > 0 then ult/ant - 1 end var_ult
      from a left join fo using (produto))
select json_build_object(
  'total', (select count(*) from z),
  'rows', (select coalesce(json_agg(x), '[]'::json) from (
     select produto, descri, um, grp, n, round(valor,2) valor, round(pmin,4) pmin, round(pmax,4) pmax, round(pmed,4) pmed,
            round(ult,4) ult, to_char(ult_dt,'YYYY-MM-DD') ult_dt, ult_forn, ult_fil, round(ant,4) ant, to_char(ant_dt,'YYYY-MM-DD') ant_dt,
            round(var,4) var, round(var_ult,4) var_ult, fora
     from z
     order by case p_ordem when 'subiu' then -coalesce(var_ult,-1e9) when 'desceu' then coalesce(var_ult,1e9)
                           when 'valor' then -valor else -coalesce(var,0) end, produto
     offset greatest(p_off,0) limit least(greatest(p_lim,1),200)) x)
)
$$;

-- Últimos preços de um item (para abrir a linha): data, pedido, filial, fornecedor, qtd, preço
create or replace function public.compras_precos_hist(p_produto text, p_ini date default null, p_fim date default null)
returns json language sql stable security definer set search_path = public as $$
  with h as (select * from mv_compras_precos
             where produto = trim(p_produto) and (p_ini is null or dt >= p_ini) and (p_fim is null or dt <= p_fim)),
       md as (select percentile_cont(0.5) within group (order by preco) med from h)
  select coalesce(json_agg(x), '[]'::json) from (
    select to_char(dt,'YYYY-MM-DD') dt, num, fil, forn, qtd, round(preco,4) preco, comprador, st,
           not (preco between (select med from md)/5 and (select med from md)*5) fora
    from h order by dt desc, num desc limit 30) x
$$;
grant execute on function public.compras_precos(date,date,text,text,text,boolean,int,text,int,int) to anon, authenticated;
grant execute on function public.compras_precos_hist(text,date,date) to anon, authenticated;

-- Atualização: o upload_compras.py chama atualizar_compras() no fim; agora atualiza também os preços
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
  refresh materialized view concurrently public.mv_compras_precos;
$$;

-- DESFAZER:
-- create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
--   refresh materialized view concurrently public.mv_compras_sc;
--   refresh materialized view concurrently public.mv_compras_ped;
--   refresh materialized view concurrently public.mv_compras_cmp;
--   refresh materialized view concurrently public.mv_compras_det;
-- $$;
-- drop function if exists public.compras_precos_hist(text,date,date);
-- drop function if exists public.compras_precos(date,date,text,text,text,boolean,int,text,int,int);
-- drop materialized view if exists public.mv_compras_precos;
