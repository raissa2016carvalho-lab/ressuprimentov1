-- 23/11/2026: efetivo por centro de custo (tabela funcionarios = SRA), usado no Excel de SC do Fardamento.
-- Devolve só contagens (normal / férias / afastado), nunca nomes ou matrículas.
create or replace function public.efetivo_cc(p_ccs text[]) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_object_agg(cc, json_build_object('normal', normal, 'ferias', ferias, 'afastado', afastado)), '{}'::json)
  from (select trim(cc) cc,
               count(*) filter (where sit_folha = 'NORMAL') normal,
               count(*) filter (where sit_folha ilike 'F%RIAS') ferias,
               count(*) filter (where sit_folha = 'AFASTADO') afastado
          from public.funcionarios where trim(cc) = any(p_ccs) group by 1) x
$$;
grant execute on function public.efetivo_cc(text[]) to anon, authenticated;
