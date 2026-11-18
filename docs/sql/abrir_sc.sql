-- Formulário "Abrir SC" (abrir-sc.html) — 18/11/2026
-- Tabelas sem acesso direto do site: tudo passa pelas funções abaixo (security definer).
-- Desfazer:
--   drop function if exists sc_abertura_criar(jsonb), sc_abertura_ler(bigint), sc_abertura_listar(text,int),
--                          sc_funcionario(text,text), sc_buscar_itens(text);
--   drop table if exists sc_abertura_itens, sc_abertura, funcionarios, itens_bloqueio;
--   drop index if exists itens_descricao_trgm, descontos_epi_matricula;

-- Cadastro de funcionários (LWHSRA001), alimentado por scripts/sync_funcionarios.py
create table if not exists funcionarios (
  filial     text not null,
  matricula  text not null,
  nome       text,
  cc         text,
  desc_cc    text,
  funcao     text,
  sit_folha  text,
  atualizado_em timestamptz default now(),
  primary key (filial, matricula)
);
alter table funcionarios enable row level security;
revoke all on funcionarios from anon, authenticated;

create table if not exists sc_abertura (
  id          bigserial primary key,
  filial      text not null,
  matricula   text not null,
  nome        text,
  cc          text not null,
  criado_em   timestamptz not null default now()
);
create table if not exists sc_abertura_itens (
  id          bigserial primary key,
  abertura_id bigint not null references sc_abertura(id) on delete cascade,
  item        int not null,
  codigo      text,
  descricao   text not null,
  quantidade  numeric not null check (quantidade > 0),
  observacao  text
);
create index if not exists sc_abertura_itens_ab on sc_abertura_itens(abertura_id);
create index if not exists sc_abertura_filial on sc_abertura(filial, criado_em desc);
alter table sc_abertura enable row level security;
alter table sc_abertura_itens enable row level security;
revoke all on sc_abertura, sc_abertura_itens from anon, authenticated;

-- Busca de itens pela descrição (ou início do código)
create index if not exists itens_descricao_trgm on itens using gin (descricao gin_trgm_ops);
create index if not exists descontos_epi_matricula on descontos_epi (matricula);
create index if not exists funcionarios_matricula on funcionarios (matricula);

-- Nome e CC pela matrícula: cadastro de funcionários; se não tiver, o último desconto de EPI
create or replace function sc_funcionario(p_filial text, p_matricula text)
returns json language sql stable security definer set search_path = public as $$
  with m as (select lpad(regexp_replace(coalesce(p_matricula,''), '\D', '', 'g'), 6, '0') as mat)
  select coalesce(
    (select json_build_object('nome', f.nome, 'cc', f.cc, 'desc_cc', f.desc_cc, 'funcao', f.funcao,
                              'filial', f.filial, 'desligado', f.sit_folha = 'D')
       from funcionarios f, m
      where f.matricula = m.mat
      order by (f.filial = p_filial) desc, (coalesce(f.sit_folha,'') <> 'D') desc
      limit 1),
    (select json_build_object('nome', d.nome, 'cc', coalesce(nullif(d.cc_func,''), d.cc), 'desc_cc', d.desc_cc,
                              'funcao', d.funcao, 'filial', d.filial, 'desligado', false)
       from descontos_epi d, m
      where d.matricula = m.mat and coalesce(d.nome,'') <> ''
      order by (d.filial = p_filial) desc, d.emissao desc nulls last
      limit 1))
  where length(regexp_replace(coalesce(p_matricula,''), '\D', '', 'g')) between 3 and 6;
$$;

-- Bloqueio do produto (SB1.B1_MSBLQL), alimentado por scripts/sync_itens_bloqueio.py
create table if not exists itens_bloqueio (
  codigo text primary key,
  bloqueado boolean not null,
  atualizado_em timestamptz default now()
);
alter table itens_bloqueio enable row level security;
revoke all on itens_bloqueio from anon, authenticated;

drop function if exists sc_buscar_itens(text);
create function sc_buscar_itens(p_q text)
returns table(codigo text, descricao text, unidade text, bloqueado boolean)
language sql stable security definer set search_path = public as $$
  with q as (select upper(trim(coalesce(p_q,''))) as t)
  select i.codigo, i.descricao, i.unidade, b.bloqueado
    from itens i cross join q
    left join itens_bloqueio b on b.codigo = i.codigo
   where length(q.t) >= 2
     and (i.codigo like q.t || '%' or i.descricao ilike '%' || replace(q.t, ' ', '%') || '%')
   order by (i.codigo = q.t) desc, coalesce(b.bloqueado, false), (upper(i.descricao) like q.t || '%') desc, length(i.descricao), i.descricao
   limit 20;
$$;

create or replace function sc_abertura_criar(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_id bigint; v_fil text; v_mat text; v_cc text; v_nome text; it jsonb; n int := 0;
begin
  v_fil := trim(coalesce(p->>'filial',''));
  v_mat := lpad(regexp_replace(coalesce(p->>'matricula',''), '\D', '', 'g'), 6, '0');
  v_cc  := trim(coalesce(p->>'cc',''));
  if v_fil = '' or not exists (select 1 from filiais where filial = v_fil) then raise exception 'Filial inválida'; end if;
  if v_mat = '000000' then raise exception 'Informe a matrícula'; end if;
  if v_cc = '' then raise exception 'Informe o centro de custo'; end if;
  if jsonb_typeof(p->'itens') <> 'array' or jsonb_array_length(p->'itens') = 0 then raise exception 'Inclua pelo menos um item'; end if;
  if jsonb_array_length(p->'itens') > 200 then raise exception 'Máximo de 200 itens por formulário'; end if;
  v_nome := coalesce(sc_funcionario(v_fil, v_mat)->>'nome', nullif(trim(p->>'nome'),''));

  insert into sc_abertura(filial, matricula, nome, cc) values (v_fil, v_mat, v_nome, v_cc) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    if trim(coalesce(it->>'descricao','')) = '' then raise exception 'Item sem descrição'; end if;
    if coalesce((it->>'quantidade')::numeric, 0) <= 0 then raise exception 'Quantidade inválida em %', it->>'descricao'; end if;
    n := n + 1;
    insert into sc_abertura_itens(abertura_id, item, codigo, descricao, quantidade, observacao)
    values (v_id, n, nullif(trim(it->>'codigo'),''), left(trim(it->>'descricao'), 200),
            (it->>'quantidade')::numeric, nullif(left(trim(coalesce(it->>'observacao','')), 250), ''));
  end loop;
  return v_id;
end $$;

create or replace function sc_abertura_ler(p_id bigint)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', a.id, 'filial', a.filial, 'nome_filial', f.nome_filial, 'matricula', a.matricula, 'nome', a.nome,
    'cc', a.cc, 'nome_cc', c.nome, 'criado_em', a.criado_em,
    'itens', coalesce((select json_agg(json_build_object('item', i.item, 'codigo', i.codigo, 'descricao', i.descricao,
                                                         'quantidade', i.quantidade, 'observacao', i.observacao) order by i.item)
                         from sc_abertura_itens i where i.abertura_id = a.id), '[]'))
  from sc_abertura a
  left join filiais f on f.filial = a.filial
  left join centros_custo c on c.cc = a.cc
  where a.id = p_id;
$$;

create or replace function sc_abertura_listar(p_filial text default null, p_limite int default 50)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(x order by x.id desc), '[]') from (
    select a.id, a.filial, a.nome, a.cc, a.criado_em,
           (select count(*) from sc_abertura_itens i where i.abertura_id = a.id) as itens
      from sc_abertura a
     where p_filial is null or p_filial = '' or a.filial = p_filial
     order by a.id desc
     limit least(greatest(coalesce(p_limite, 50), 1), 200)) x;
$$;

grant execute on function sc_funcionario(text,text), sc_buscar_itens(text), sc_abertura_criar(jsonb),
                          sc_abertura_ler(bigint), sc_abertura_listar(text,int) to anon, authenticated;
