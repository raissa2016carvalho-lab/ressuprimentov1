-- Aba "Fardamento" do Painel de Compras (16/11/2026, aplicado): compra × consumo × estoque, no formato da planilha da Raissa
-- mv_farda_compra: itens de SC/PC de fardamento por filial × SKU × mês (emissão do PC; SC sem PC pela data da SC) × status SC × status PC
-- mv_farda_cons:   consumo (SCP) de fardamento por filial × SKU × mês
-- farda_compra(ano): as duas + estoque SB2 por filial × SKU, nomes e filiais (~1 s; chave pública tem limite de 3 s)
-- atualizar_compras() (chamada pelo upload_compras.py) atualiza as duas visões.
create materialized view if not exists public.mv_farda_compra as
with f as (select trim(codigo) c from estoque_sb2 where grupo ilike 'FARDAMENTO%'
           union select trim(produto) from consumo_scp where grupo ilike 'FARDAMENTO%')
select trim(v.filial) fil, trim(v.sc_produto) c, max(trim(v.sc_descricao)) n,
       left(coalesce(nullif(v.pc_emissao,''), v.sc_emissao),6) mes,
       coalesce(v.sc_status,'(vazio)') sc_st, coalesce(nullif(v.pc_status,''),'(vazio)') pc_st,
       sum(coalesce(v.pc_quant, v.sc_quant)) q
from sc_pedidos_v2 v join f on f.c = trim(v.sc_produto)
where coalesce(nullif(v.pc_emissao,''), v.sc_emissao) >= '20250101'
group by 1,2,4,5,6;
create unique index if not exists mv_farda_compra_pk on public.mv_farda_compra (fil, c, mes, sc_st, pc_st);

create materialized view if not exists public.mv_farda_cons as
select trim(filial) fil, trim(produto) c, max(descricao) n, mes, sum(quantidade) q
from consumo_scp where grupo ilike 'FARDAMENTO%' and mes >= '202501' group by 1,2,4;
create unique index if not exists mv_farda_cons_pk on public.mv_farda_cons (fil, c, mes);

create or replace function public.farda_compra(p_ano int)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'compra',  (select coalesce(json_agg(json_build_array(fil, c, mes, sc_st, pc_st, q)), '[]'::json)
                from mv_farda_compra where mes between p_ano::text||'01' and p_ano::text||'12'),
    'consumo', (select coalesce(json_agg(json_build_array(fil, c, mes, q)), '[]'::json)
                from mv_farda_cons where mes between p_ano::text||'01' and p_ano::text||'12'),
    'estoque', (select coalesce(json_agg(json_build_array(trim(filial), trim(codigo), q)), '[]'::json)
                from (select filial, codigo, sum(qtd_atual) q from estoque_sb2 where grupo ilike 'FARDAMENTO%'
                      group by 1,2 having sum(qtd_atual) <> 0) e),
    'nomes',   (select json_object_agg(c, n) from (select c, max(n) n from (select c, n from mv_farda_compra union all select c, n from mv_farda_cons) x
                                                   where n is not null group by c) y),
    'filiais', (select json_object_agg(trim(filial), nome_filial) from filiais),
    'estoque_em', (select max(atualizado_em) from estoque_sb2),
    'consumo_ate', (select max(emissao) from consumo_scp where mes = (select max(mes) from mv_farda_cons)))
$$;
grant execute on function public.farda_compra(int) to anon, authenticated;

create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
  refresh materialized view concurrently public.mv_compras_precos;
  refresh materialized view concurrently public.mv_farda_compra;
  refresh materialized view concurrently public.mv_farda_cons;
$$;

-- Sobras da aba antiga (removida em 16/11), ainda no banco e sem uso: mv_fardamento_dia/cc/ped e funções fardamento_calendario/matriz/ressup.
-- Para apagar: drop function public.fardamento_ressup(), public.fardamento_matriz(int), public.fardamento_calendario(int);
--              drop materialized view public.mv_fardamento_ped, public.mv_fardamento_cc, public.mv_fardamento_dia;
-- DESFAZER esta aba: drop function public.farda_compra(int); drop materialized view public.mv_farda_compra, public.mv_farda_cons;
--                    (e tirar as duas linhas do atualizar_compras)

-- ── SC com rateio (16/11, aplicado): consumo de fardamento por filial × SKU × CC × mês, para dividir a compra pelos CCs ──
create materialized view if not exists public.mv_farda_cons_cc as
select trim(filial) fil, trim(produto) c, coalesce(nullif(trim(cc),''),'') cc, mes, sum(quantidade) q
from consumo_scp where grupo ilike 'FARDAMENTO%' and mes >= '202501' group by 1,2,3,4;
create unique index if not exists mv_farda_cons_cc_pk on public.mv_farda_cons_cc (fil, c, cc, mes);
create or replace function public.farda_rateio(p_ano int)
returns json language sql stable security definer set search_path = public as $$
  with k as (select fil, c, cc, sum(q) q from mv_farda_cons_cc where mes between p_ano::text||'01' and p_ano::text||'12' group by 1,2,3)
  select json_build_object(
    'cons', (select coalesce(json_agg(json_build_array(fil, c, cc, q)), '[]'::json) from k where q > 0),
    'ccs',  (select coalesce(json_object_agg(cc::text, trim(nome)), '{}'::json) from centros_custo where cc::text in (select distinct cc from k)))
$$;
grant execute on function public.farda_rateio(int) to anon, authenticated;
-- atualizar_compras() também faz: refresh materialized view concurrently public.mv_farda_cons_cc;
-- DESFAZER: drop function public.farda_rateio(int); drop materialized view public.mv_farda_cons_cc; (e tirar a linha do atualizar_compras)

-- 16/11 (aplicado): a tela foi para fardamento.html (aba 👕 Fardamento do index.html) e farda_compra(ano) passou a devolver também
-- 'pend' = a chegar, de qualquer ano: PC Pendente / Em aprovação, ou SC Pendente / Em Processo de Cotação / Bloqueada ainda sem PC,
-- por filial × SKU. A compra trimestral/semestral da tela = ⌈média × 3 ou 6⌉ − a chegar. Excel de SC: C1_XTIPOSC = 006.
