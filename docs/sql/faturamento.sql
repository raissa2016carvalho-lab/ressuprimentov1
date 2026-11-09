-- Faturamento (Protheus SF2 — LWHSF2001) para o Comparativo mês a mês do Compras
-- Rodar uma vez no SQL Editor do Supabase.

create table if not exists public.faturamento_sf2 (
  filial    text not null,
  doc       text not null,
  serie     text not null default '',
  cliente   text not null default '',
  loja      text not null default '',
  emissao   date,
  tipo      text,          -- N = normal, D = devolução, B = beneficiamento, C/I/P = complementos
  valbrut   numeric,       -- valor bruto da nota (com impostos)
  valmerc   numeric,       -- valor das mercadorias
  valfat    numeric,       -- valor faturado (duplicatas)
  atualizado_em timestamptz default now(),
  primary key (filial, doc, serie, cliente, loja)
);
create index if not exists faturamento_sf2_emissao on public.faturamento_sf2 (emissao);
alter table public.faturamento_sf2 enable row level security;   -- leitura só pela função abaixo

-- Faturamento por mês e filial (só notas normais, tipo N), para os anos pedidos
create or replace function public.faturamento_mensal(p_anos int[])
returns table(mes text, filial text, valor numeric)
language sql stable security definer set search_path = public as $$
  select to_char(emissao,'YYYY-MM'), trim(filial), sum(coalesce(valbrut,0))
  from faturamento_sf2
  where emissao is not null and extract(year from emissao)::int = any(p_anos) and coalesce(trim(tipo),'N') = 'N'
  group by 1, 2
$$;
grant execute on function public.faturamento_mensal(int[]) to anon, authenticated;

-- ── DESFAZER ────────────────────────────────────────────────────────────────
-- drop function if exists public.faturamento_mensal(int[]);
-- drop table if exists public.faturamento_sf2;
