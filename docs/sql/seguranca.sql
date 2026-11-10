-- Segurança das tabelas (RLS) — em etapas
-- ── Etapa 1 (10/11, aplicada): perfis e pedidos de troca de senha ────────────────────────
-- As regras já existiam (perfil_ler; pedido_criar / pedido_admin_ler / pedido_admin_editar); faltava ligar a trava.
alter table public.perfis_usuario enable row level security;
alter table public.pedidos_redefinicao enable row level security;
-- DESFAZER:
-- alter table public.perfis_usuario disable row level security;
-- alter table public.pedidos_redefinicao disable row level security;
