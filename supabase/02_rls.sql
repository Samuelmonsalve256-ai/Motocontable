-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 02_rls.sql
-- Seguridad: solo tu cuenta puede leer y escribir tus datos.
-- Se puede ejecutar más de una vez sin problema.
--
--  • Sin sesión (rol anon) no se puede leer ni escribir nada.
--  • Cada usuario solo ve y modifica sus propias filas (user_id = auth.uid()).
--  • No existe permiso de DELETE: las filas nunca se borran físicamente desde
--    la app; se marcan con deleted_at (eliminación suave).
--  • El historial solo se puede leer; lo escriben los disparadores y mc_push.
-- ════════════════════════════════════════════════════════════════════════════

begin;

alter table public.mc_registros enable row level security;
alter table public.mc_historial enable row level security;

-- Supabase da por defecto todos los permisos a anon y authenticated sobre las
-- tablas nuevas. Se quitan todos y se dan solo los necesarios.
revoke all on table public.mc_registros from public, anon, authenticated;
revoke all on table public.mc_historial from public, anon, authenticated;
revoke all on sequence public.mc_seq from public, anon, authenticated;
revoke all on sequence public.mc_historial_hist_id_seq from public, anon, authenticated;

grant select, insert, update on table public.mc_registros to authenticated;
grant select                 on table public.mc_historial to authenticated;

-- ── mc_registros ──────────────────────────────────────────────────────────────
drop policy if exists "leer mis registros"      on public.mc_registros;
drop policy if exists "crear mis registros"     on public.mc_registros;
drop policy if exists "modificar mis registros" on public.mc_registros;

create policy "leer mis registros" on public.mc_registros
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "crear mis registros" on public.mc_registros
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "modificar mis registros" on public.mc_registros
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ── mc_historial ──────────────────────────────────────────────────────────────
drop policy if exists "leer mi historial" on public.mc_historial;

create policy "leer mi historial" on public.mc_historial
  for select to authenticated
  using (user_id = (select auth.uid()));

commit;
