-- Validação do custo médio (18/11/2026)
-- Dados: scripts/sync_kardex_custo.py → kardex_mov (SD1/SD2/SD3 com custo), kardex_sb9, kardex_sb2, kardex_param.
--
-- Regra do Protheus (método mensal do MATA330, o mais usado):
--   Custo médio do mês = (valor do saldo inicial + valor das entradas) ÷ (qtd do saldo inicial + qtd das entradas)
--     saldo inicial = SB9 do fechamento anterior (B9_QINI, B9_VINI1)
--     entradas      = SD1 (D1_CUSTO) + SD3 com D3_TM < 500 (D3_CUSTO1)
--   Todas as saídas do mês (SD3 com D3_TM >= 500 e SD2) são valorizadas por esse custo médio.
--   Saldo final = saldo inicial + entradas − saídas (em qtd e em valor) = SB9 do mês / SB2 se o mês ainda está aberto.
-- Movimentos estornados (D3_ESTORNO = 'S') ficam de fora.
--
-- custo_validar('202610') → uma linha por filial + produto + armazém com a conta refeita e os alertas.
-- Desfazer: drop function custo_validar(text); drop table kardex_mov, kardex_sb9, kardex_sb2, kardex_param;

create table if not exists kardex_mov (
  chave text primary key, origem text not null, filial text not null, produto text not null, armazem text,
  data date not null, numseq text, tm text, cf text, entrada boolean not null,
  quantidade numeric not null default 0, custo numeric not null default 0, valor_nf numeric, doc text,
  estorno boolean not null default false, atualizado_em timestamptz default now()
);
create index if not exists kardex_mov_item on kardex_mov (filial, produto, armazem, data, numseq);
create index if not exists kardex_mov_data on kardex_mov (data);
create table if not exists kardex_sb9 (filial text not null, produto text not null, armazem text not null, data date not null,
  qini numeric, vini numeric, cm numeric, primary key (filial, produto, armazem, data));
create table if not exists kardex_sb2 (filial text not null, produto text not null, armazem text not null,
  qatu numeric, vatu numeric, cm numeric, atualizado_em timestamptz default now(), primary key (filial, produto, armazem));
create table if not exists kardex_param (filial text not null default '', nome text not null, valor text, primary key (filial, nome));
alter table kardex_mov enable row level security; alter table kardex_sb9 enable row level security;
alter table kardex_sb2 enable row level security; alter table kardex_param enable row level security;
revoke all on kardex_mov, kardex_sb9, kardex_sb2, kardex_param from anon, authenticated;

create or replace function custo_validar(p_mes text)
returns table (
  filial text, produto text, armazem text, descricao text,
  q_ini numeric, v_ini numeric, q_ent numeric, v_ent numeric, q_sai numeric, v_sai numeric,
  cm_calculado numeric, cm_aplicado numeric, dif_pct numeric,
  q_fim_calc numeric, v_fim_calc numeric, q_fim_prot numeric, v_fim_prot numeric, cm_prot numeric,
  saidas_custo_zero int, entradas_custo_zero int, alerta text
)
language sql stable security definer set search_path = public as $$
with lim as (
  select to_date(p_mes || '01', 'YYYYMMDD') ini,
         (to_date(p_mes || '01', 'YYYYMMDD') + interval '1 month')::date fim
),
ini as (   -- saldo inicial: último fechamento antes do mês
  select distinct on (b.filial, b.produto, b.armazem) b.filial, b.produto, b.armazem, b.qini, b.vini
    from kardex_sb9 b, lim where b.data < lim.ini
   order by b.filial, b.produto, b.armazem, b.data desc
),
fimp as (  -- saldo final do Protheus: fechamento do mês (SB9 com data dentro do mês) ou SB2 se não fechou
  select distinct on (b.filial, b.produto, b.armazem) b.filial, b.produto, b.armazem, b.qini q, b.vini v
    from kardex_sb9 b, lim where b.data >= lim.ini and b.data < lim.fim
   order by b.filial, b.produto, b.armazem, b.data desc
),
mov as (
  select m.filial, m.produto, m.armazem,
         sum(case when m.entrada then m.quantidade else 0 end) q_ent,
         sum(case when m.entrada then m.custo else 0 end)      v_ent,
         sum(case when not m.entrada then m.quantidade else 0 end) q_sai,
         sum(case when not m.entrada then m.custo else 0 end)      v_sai,
         count(*) filter (where not m.entrada and m.quantidade > 0 and m.custo = 0)::int sz,
         count(*) filter (where m.entrada and m.origem = 'SD1' and m.quantidade > 0 and m.custo = 0)::int ez
    from kardex_mov m, lim
   where m.data >= lim.ini and m.data < lim.fim and not m.estorno
   group by 1, 2, 3
),
base as (
  select coalesce(mv.filial, i.filial) filial, coalesce(mv.produto, i.produto) produto, coalesce(mv.armazem, i.armazem) armazem,
         coalesce(i.qini, 0) q_ini, coalesce(i.vini, 0) v_ini,
         coalesce(mv.q_ent, 0) q_ent, coalesce(mv.v_ent, 0) v_ent, coalesce(mv.q_sai, 0) q_sai, coalesce(mv.v_sai, 0) v_sai,
         coalesce(mv.sz, 0) sz, coalesce(mv.ez, 0) ez
    from mov mv full join ini i on i.filial = mv.filial and i.produto = mv.produto and i.armazem = mv.armazem
   where mv.filial is not null or i.qini <> 0
),
calc as (
  select b.*,
         case when b.q_ini + b.q_ent > 0 then (b.v_ini + b.v_ent) / (b.q_ini + b.q_ent) end cm_calc,
         case when b.q_sai > 0 then b.v_sai / b.q_sai end cm_apl,
         b.q_ini + b.q_ent - b.q_sai q_fim, b.v_ini + b.v_ent - b.v_sai v_fim,
         coalesce(f.q, s2.qatu) q_prot, coalesce(f.v, s2.vatu) v_prot, s2.cm cm2
    from base b
    left join fimp f on f.filial = b.filial and f.produto = b.produto and f.armazem = b.armazem
    left join kardex_sb2 s2 on s2.filial = b.filial and s2.produto = b.produto and s2.armazem = b.armazem
                            and not exists (select 1 from fimp f2 where f2.filial = b.filial and f2.produto = b.produto and f2.armazem = b.armazem)
)
select c.filial, c.produto, c.armazem, i.descricao,
       round(c.q_ini, 4), round(c.v_ini, 2), round(c.q_ent, 4), round(c.v_ent, 2), round(c.q_sai, 4), round(c.v_sai, 2),
       round(c.cm_calc, 4), round(c.cm_apl, 4),
       case when c.cm_calc > 0 and c.cm_apl is not null then round((c.cm_apl / c.cm_calc - 1) * 100, 2) end,
       round(c.q_fim, 4), round(c.v_fim, 2), round(c.q_prot, 4), round(c.v_prot, 2), round(c.cm2, 4),
       c.sz, c.ez,
       nullif(concat_ws('; ',
         case when c.q_fim < -0.0001 then 'saldo negativo' end,
         case when c.v_fim < -0.01 then 'valor negativo' end,
         case when c.sz > 0 then c.sz || ' saída(s) com custo zero' end,
         case when c.ez > 0 then c.ez || ' entrada(s) SD1 com custo zero' end,
         case when c.cm_calc > 0 and c.cm_apl is not null and abs(c.cm_apl / c.cm_calc - 1) > 0.01 then 'custo das saídas ≠ média do mês' end,
         case when c.q_prot is not null and abs(c.q_fim - c.q_prot) > 0.0001 then 'saldo final em qtd não bate' end,
         case when c.v_prot is not null and abs(c.v_fim - c.v_prot) > greatest(1, abs(c.v_prot) * 0.005) then 'saldo final em valor não bate' end,
         case when c.q_fim > 0 and c.v_fim <= 0 then 'tem saldo e valor zero' end), '')
  from calc c
  left join itens i on i.codigo = c.produto;
$$;
revoke all on function custo_validar(text) from anon, authenticated;
