-- Controle de acesso por painel (aplicado em 19/11/2026). Tela: acessos.html (só admin). Trava: bq-acesso.js em cada tela.
-- acesso_painel(email, painel): quem vê cada painel. Admin (perfis_usuario.role = 'admin') vê tudo, inclusive a tela de Acessos.
-- Chaves dos painéis (data-painel): index, gerente, formulario, ruptura, estoque, compras, fechamento, notas (inclui recebimento),
--   separacao, descontos, estoque-central, fardamento, abrir-sc, manutencao, acessos (só admin).
-- Funções: tem_acesso(painel) → boolean (a trava pergunta); meus_paineis() → {admin, paineis};
--   acessos_listar() / acesso_definir(email, painel, liberado) / acesso_admin(email, admin) → só admin.
-- Carga inicial: todo usuário não-admin recebeu as 8 telas que já pediam senha (index, gerente, ruptura, fechamento, notas,
--   separacao, descontos, estoque-central). As 6 que passaram a pedir senha começaram só com admin.
-- Observação: a trava das 6 telas novas é na tela; os dados delas (compras, estoque, fardamento, abrir-sc, formulario,
--   manutencao) ainda podem ser lidos pela chave pública do banco. Fechar no banco é um passo separado.
create table if not exists public.acesso_painel (
  email text not null, painel text not null, liberado_por text, liberado_em timestamptz not null default now(),
  primary key (email, painel));
alter table public.acesso_painel enable row level security;
revoke all on public.acesso_painel from anon, authenticated;

create or replace function public.tem_acesso(p_painel text) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.is_admin()
    or (p_painel <> 'acessos' and exists (select 1 from public.acesso_painel
         where lower(email) = lower(auth.jwt()->>'email') and painel = p_painel)))
$$;

create or replace function public.meus_paineis() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('admin', public.is_admin(),
    'paineis', coalesce((select json_agg(painel order by painel) from public.acesso_painel
                          where lower(email) = lower(auth.jwt()->>'email')), '[]'::json))
$$;

create or replace function public.acessos_listar() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente administradores.'; end if;
  return (select coalesce(json_agg(x order by x.admin desc, x.email), '[]'::json) from (
    select lower(u.email) email, u.last_sign_in_at ultimo_login, u.created_at criado,
           exists (select 1 from public.perfis_usuario p where lower(p.email) = lower(u.email) and p.role = 'admin') admin,
           coalesce((select json_agg(a.painel order by a.painel) from public.acesso_painel a where lower(a.email) = lower(u.email)), '[]'::json) paineis
      from auth.users u where u.email is not null) x);
end $$;

create or replace function public.acesso_definir(p_email text, p_painel text, p_liberado boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente administradores.'; end if;
  if p_liberado then
    insert into public.acesso_painel (email, painel, liberado_por) values (lower(trim(p_email)), p_painel, auth.jwt()->>'email')
    on conflict (email, painel) do nothing;
  else
    delete from public.acesso_painel where lower(email) = lower(trim(p_email)) and painel = p_painel;
  end if;
end $$;

create or replace function public.acesso_admin(p_email text, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente administradores.'; end if;
  if not p_admin and lower(trim(p_email)) = lower(auth.jwt()->>'email') then
    raise exception 'Você não pode tirar o seu próprio acesso de administrador.'; end if;
  if p_admin then
    if exists (select 1 from public.perfis_usuario where lower(email) = lower(trim(p_email))) then
      update public.perfis_usuario set role = 'admin' where lower(email) = lower(trim(p_email));
    else
      insert into public.perfis_usuario (email, role) values (lower(trim(p_email)), 'admin');
    end if;
  else
    update public.perfis_usuario set role = 'usuario' where lower(email) = lower(trim(p_email)) and role = 'admin';
  end if;
end $$;

revoke execute on function public.tem_acesso(text), public.meus_paineis(), public.acessos_listar(),
  public.acesso_definir(text, text, boolean), public.acesso_admin(text, boolean) from public, anon;
grant execute on function public.tem_acesso(text), public.meus_paineis(), public.acessos_listar(),
  public.acesso_definir(text, text, boolean), public.acesso_admin(text, boolean) to authenticated;

-- ── 19/11/2026 (2ª parte): nível "somente visualização" e regras de acesso ─────────────────────────────
-- acesso_painel.somente_ver: true = só consulta (a trava barra gravações na tela). acesso_nivel(painel) → 'editar' | 'ver' | 'nenhum'.
-- acesso_definir ganhou o 4º parâmetro p_somente_ver (default false). acessos_listar devolve também a lista 'somente_ver'.
-- Regras aplicadas (admins não mudam: veem tudo):
--   gerentes (e-mails em gerentes_cc) → só 'gerente' (editar)
--   anne@beq.com.br → só 'fechamento' (editar)
--   demais usuários → só 'index' (Ressuprimento), somente visualização
alter table public.acesso_painel add column if not exists somente_ver boolean not null default false;
create or replace function public.acesso_nivel(p_painel text) returns text
language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then 'nenhum'
    when public.is_admin() then 'editar'
    when p_painel = 'acessos' then 'nenhum'
    else coalesce((select case when a.somente_ver then 'ver' else 'editar' end from public.acesso_painel a
                    where lower(a.email) = lower(auth.jwt()->>'email') and a.painel = p_painel), 'nenhum')
  end
$$;
-- (acessos_listar e acesso_definir: ver migração acesso_paineis_somente_ver no Supabase)
