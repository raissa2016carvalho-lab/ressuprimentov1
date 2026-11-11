-- Descontos de EPI (customização LWHZZA010 do Protheus) — painel de abono/desconto por período da folha (21 a 20)
-- descontos_epi: cópia da ZZA já ligada à SA (LWHSCP001) e ao funcionário (LWHSRA001), gravada pelo sync_descontos_epi.py
-- descontos_decisao: o que o almoxarifado (e depois o gerente) decidiu em cada desconto — fica separada para o sync não apagar

create table if not exists public.descontos_epi (
  chave          text primary key,     -- filial|SA|produto|matrícula|data de inclusão
  filial         text,
  sa             text,                 -- nº da SA (ZZA_TRANS = CP_NUM)
  emissao        date,                 -- emissão da SA (CP_EMISSAO); sem SA, a data de inclusão do desconto
  datinc         date,                 -- data em que o desconto foi gerado (ZZA_DATINC)
  matricula      text,
  nome           text,                 -- cadastro de funcionários (LWHSRA001) ou ZZA_NOMFUN
  funcao         text,
  cc             text,                 -- centro de custo da SA (CP_CC)
  cc_func        text,                 -- centro de custo do funcionário (cadastro)
  desc_cc        text,
  produto        text,
  descricao      text,
  quantidade     numeric,
  motivo         text,                 -- código do motivo (ZZA_MOTIVO)
  observacao     text,                 -- observação da SA (CP_YCOMREQ)
  solicitante    text,
  vida_util      numeric,              -- vida útil do material em dias (ZZA_VIDUTI)
  valor          numeric,              -- custo do material (ZZA_VALOR)
  valor_desconto numeric,              -- desconto calculado (ZZA_VALDES): proporcional ao que faltava de vida útil
  status         text,
  integrado      text,                 -- ZZA_INTEG (N = ainda não foi para a folha)
  atualizado_em  timestamptz default now()
);
create index if not exists descontos_epi_datinc on public.descontos_epi (datinc);
create index if not exists descontos_epi_cc on public.descontos_epi (cc);

create table if not exists public.descontos_decisao (
  chave        text primary key,         -- mesma chave de descontos_epi (sem ligação: o sync refaz os descontos sem apagar as decisões)
  decisao      text check (decisao in ('descontar','abonar')),
  decidido_por text,
  decidido_em  timestamptz default now(),
  obs          text
);

alter table public.descontos_epi enable row level security;
alter table public.descontos_decisao enable row level security;
drop policy if exists logado_le on public.descontos_epi;
create policy logado_le on public.descontos_epi for select to authenticated using (true);   -- gravação só pelo sync (chave secreta)
drop policy if exists logado_tudo on public.descontos_decisao;
create policy logado_tudo on public.descontos_decisao for all to authenticated using (true) with check (true);

-- DESFAZER:
-- drop table if exists public.descontos_decisao;
-- drop table if exists public.descontos_epi;
