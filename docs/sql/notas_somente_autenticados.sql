-- Painel de notas (notas.html / recebimento): dados só para usuários autenticados no Supabase. Aplicado em 19/11/2026.
-- Antes, a tela pedia login, mas a chave pública (anon), que fica no código da página, lia as tabelas sem login.
-- Os syncs (sync_nfe_master, sync_movimentos_entrada, upload_compras) usam a chave de serviço e não são afetados.
revoke all on public.nfe_master, public.nfe_master_itens, public.nfe_fluxo, public.nfe_setor,
              public.fornecedor_setor, public.medicoes_nota, public.vw_nfe_sd1, public.mv_nfe_sd1 from anon;
grant select on public.nfe_master, public.nfe_master_itens, public.nfe_fluxo, public.nfe_setor,
                public.fornecedor_setor, public.medicoes_nota, public.vw_nfe_sd1, public.mv_nfe_sd1 to authenticated;

alter policy leitura_publica on public.nfe_master to authenticated;
alter policy leitura_publica on public.nfe_master_itens to authenticated;
alter policy leitura_publica on public.medicoes_nota to authenticated;
alter policy nfe_fluxo_ler on public.nfe_fluxo to authenticated;
alter policy nfe_setor_ler on public.nfe_setor to authenticated;
alter policy forn_setor_ler on public.fornecedor_setor to authenticated;

revoke execute on function public.nfe_entregas_json() from public, anon;
revoke execute on function public.nfe_entregas() from public, anon;
grant execute on function public.nfe_entregas_json() to authenticated;
grant execute on function public.nfe_entregas() to authenticated;

-- perfis_usuario (e-mail, perfil e filiais) estava sem RLS: cada usuário lê só o próprio perfil (admin lê todos)
revoke all on public.perfis_usuario from anon;
alter table public.perfis_usuario enable row level security;
