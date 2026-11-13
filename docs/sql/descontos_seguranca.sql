-- Descontos de EPI — segurança e rastreio (13/11/2026)
-- 1) Histórico: toda mudança em descontos_decisao fica gravada (quem, quando, antes → depois), com o "lote" das marcações em massa.
-- 2) Trava: só administrador (perfis_usuario.role = admin) mexe na decisão final (decisao); gerente só responde
--    (gerente_decisao/obs) nos descontos dos CCs dele. Quem gravou é sempre o e-mail do login (não dá para se passar por outro).
-- 3) Exportações: cada arquivo baixado para o Protheus fica registrado (para avisar o que mudou depois).
-- 4) gerentes_cc: todos leem; só administrador altera.

alter table public.descontos_decisao add column if not exists lote text;

create table if not exists public.descontos_decisao_hist (
  id           bigserial primary key,
  chave        text not null,
  acao         text not null,                -- INSERT / UPDATE / DELETE
  decisao_ant  text, decisao_nova text,
  gerente_ant  text, gerente_nova text,
  obs_ant      text, obs_nova     text,
  lote         text,
  por          text,                         -- e-mail do login que fez a mudança
  em           timestamptz not null default now()
);
create index if not exists descontos_decisao_hist_chave on public.descontos_decisao_hist (chave);
create index if not exists descontos_decisao_hist_em on public.descontos_decisao_hist (em desc);
alter table public.descontos_decisao_hist enable row level security;
drop policy if exists hist_le on public.descontos_decisao_hist;
create policy hist_le on public.descontos_decisao_hist for select to authenticated using (true);  -- gravação só pelo gatilho

create table if not exists public.descontos_exportacao (
  id        bigserial primary key,
  periodo   text not null,                   -- '2026-09-21|2026-10-20'
  filtro    text,                            -- CC/filial escolhidos no filtro, se houver
  linhas    int, abonadas int, descontadas int, pendentes int,
  valor_descontado numeric,
  por       text default (auth.jwt()->>'email'),
  em        timestamptz not null default now()
);
alter table public.descontos_exportacao enable row level security;
drop policy if exists exp_le on public.descontos_exportacao;
create policy exp_le on public.descontos_exportacao for select to authenticated using (true);
drop policy if exists exp_admin on public.descontos_exportacao;
create policy exp_admin on public.descontos_exportacao for insert to authenticated with check (public.is_admin());

-- trava + carimbo (antes de gravar)
create or replace function public.descontos_decisao_guarda() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  eu text := lower(coalesce(auth.jwt()->>'email',''));
  sistema boolean := coalesce(auth.role(),'') = 'service_role' or eu = '';
  adm boolean := public.is_admin();
  meu_cc boolean;
begin
  if sistema then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if not adm then raise exception 'Só administrador pode apagar decisões de desconto.'; end if;
    return old;
  end if;
  if not adm then
    select exists (select 1 from descontos_epi d join gerentes_cc g on g.cc::text = trim(d.cc)
                   where d.chave = new.chave and lower(trim(g.email)) = eu) into meu_cc;
    if not meu_cc then raise exception 'Este desconto não é de um centro de custo seu.'; end if;
    if new.decisao is distinct from (case when tg_op = 'UPDATE' then old.decisao end) then
      raise exception 'Só administrador pode mudar a decisão final. Responda em "Resposta do gerente".';
    end if;
    if tg_op = 'UPDATE' then new.decidido_por := old.decidido_por; new.decidido_em := old.decidido_em; end if;
  end if;
  -- carimbo: quem gravou é sempre o login
  if new.decisao is distinct from (case when tg_op = 'UPDATE' then old.decisao end) then
    new.decidido_por := case when new.decisao is null then null else eu end;
    new.decidido_em  := case when new.decisao is null then null else now() end;
  end if;
  if new.gerente_decisao is distinct from (case when tg_op = 'UPDATE' then old.gerente_decisao end) then
    new.gerente_por := case when new.gerente_decisao is null then null else eu end;
    new.gerente_em  := case when new.gerente_decisao is null then null else now() end;
  end if;
  return new;
end $$;
drop trigger if exists descontos_decisao_guarda on public.descontos_decisao;
create trigger descontos_decisao_guarda before insert or update or delete on public.descontos_decisao
  for each row execute function public.descontos_decisao_guarda();

-- histórico (depois de gravar)
create or replace function public.descontos_decisao_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.decisao is not distinct from old.decisao and new.gerente_decisao is not distinct from old.gerente_decisao
     and new.gerente_obs is not distinct from old.gerente_obs then return new; end if;
  insert into descontos_decisao_hist (chave, acao, decisao_ant, decisao_nova, gerente_ant, gerente_nova, obs_ant, obs_nova, lote, por)
  values (coalesce(new.chave, old.chave), tg_op,
          case when tg_op <> 'INSERT' then old.decisao end, case when tg_op <> 'DELETE' then new.decisao end,
          case when tg_op <> 'INSERT' then old.gerente_decisao end, case when tg_op <> 'DELETE' then new.gerente_decisao end,
          case when tg_op <> 'INSERT' then old.gerente_obs end, case when tg_op <> 'DELETE' then new.gerente_obs end,
          case when tg_op <> 'DELETE' then new.lote end,
          coalesce(nullif(lower(auth.jwt()->>'email'),''), 'sistema'));
  return coalesce(new, old);
end $$;
drop trigger if exists descontos_decisao_log on public.descontos_decisao;
create trigger descontos_decisao_log after insert or update or delete on public.descontos_decisao
  for each row execute function public.descontos_decisao_log();

-- gerentes_cc: todos leem, só admin altera
drop policy if exists logado_tudo on public.gerentes_cc;
drop policy if exists ger_le on public.gerentes_cc;
create policy ger_le on public.gerentes_cc for select to authenticated using (true);
drop policy if exists ger_admin on public.gerentes_cc;
create policy ger_admin on public.gerentes_cc for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- DESFAZER:
-- drop trigger if exists descontos_decisao_guarda on public.descontos_decisao; drop function if exists public.descontos_decisao_guarda();
-- drop trigger if exists descontos_decisao_log on public.descontos_decisao;   drop function if exists public.descontos_decisao_log();
-- drop table if exists public.descontos_decisao_hist; drop table if exists public.descontos_exportacao;
-- alter table public.descontos_decisao drop column if exists lote;
-- drop policy if exists ger_le on public.gerentes_cc; drop policy if exists ger_admin on public.gerentes_cc;
-- create policy logado_tudo on public.gerentes_cc for all to authenticated using (true) with check (true);
