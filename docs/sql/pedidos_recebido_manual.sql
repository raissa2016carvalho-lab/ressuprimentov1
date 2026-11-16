-- Pedidos marcados como "Recebido" à mão (mobilização) — 16/11/2026 (aplicado)
-- O sync regrava o status do Protheus em sc_pedidos_v2; marcar direto não fica. Aqui o pedido entra numa lista e um gatilho
-- mantém "Recebido" sempre que o sync gravar Pendente / Em aprovação. Tela de mobilização e sync não mudam.
create table if not exists public.pedidos_recebido_manual (
  filial text not null, pc_numero text not null, motivo text, criado_em timestamptz not null default now(),
  primary key (filial, pc_numero));
alter table public.pedidos_recebido_manual enable row level security;
create policy prm_le on public.pedidos_recebido_manual for select to authenticated using (true);
create or replace function public.sc_pedidos_v2_recebido_manual() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.pc_numero is not null and coalesce(new.pc_status,'') in ('Pendente','Em aprovação')
     and exists (select 1 from pedidos_recebido_manual m
                 where m.filial = trim(coalesce(new.pc_filial, new.filial)) and m.pc_numero = trim(new.pc_numero)) then
    new.pc_status := 'Recebido';
  end if;
  return new;
end $$;
create trigger sc_pedidos_v2_recebido_manual before insert or update on public.sc_pedidos_v2
  for each row execute function public.sc_pedidos_v2_recebido_manual();

-- MARCAR UM PEDIDO (filial, número):
-- insert into public.pedidos_recebido_manual (filial, pc_numero, motivo) values ('39','000235','material chegou') on conflict do nothing;
-- update public.sc_pedidos_v2 set pc_status = pc_status where trim(coalesce(pc_filial, filial))='39' and trim(pc_numero)='000235';
-- Marcados: filial 39 — 000269, 000235, 000270.
-- DESMARCAR: delete from public.pedidos_recebido_manual where filial='39' and pc_numero='000235';  (o próximo sync volta o status do Protheus)
-- DESFAZER TUDO: drop trigger sc_pedidos_v2_recebido_manual on public.sc_pedidos_v2; drop function public.sc_pedidos_v2_recebido_manual();
--                drop table public.pedidos_recebido_manual;
