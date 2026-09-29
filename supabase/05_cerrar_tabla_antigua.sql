-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 05_cerrar_tabla_antigua.sql
-- EJECÚTALO SOLO AL FINAL (fase 5 del LEEME), cuando todos tus dispositivos ya
-- usen la versión nueva y hayas verificado que tus datos están en mc_registros.
--
--  • NO borra la tabla mc_datos ni sus datos: queda como archivo histórico.
--  • Quita el acceso público (clave anon) a mc_datos, para que nadie que tenga la
--    clave de la página pueda leer ni sobrescribir esos datos.
--  • Como efecto, una versión vieja de la app que haya quedado abierta o en caché
--    en algún dispositivo ya no podrá escribir en mc_datos.
--
-- Antes de ejecutarlo, guarda el resultado de la consulta 4 de 00_diagnostico.sql
-- (las políticas actuales), por si alguna vez quisieras volver a crearlas.
-- ════════════════════════════════════════════════════════════════════════════

begin;

alter table public.mc_datos enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'mc_datos'
  loop
    execute format('drop policy %I on public.mc_datos', p.policyname);
  end loop;
end
$$;

revoke all on table public.mc_datos from public, anon, authenticated;

commit;

-- Verificación: debe mostrar rls_activado = true y ninguna política.
select c.relname as tabla, c.relrowsecurity as rls_activado
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'mc_datos';

select policyname from pg_policies where schemaname = 'public' and tablename = 'mc_datos';
