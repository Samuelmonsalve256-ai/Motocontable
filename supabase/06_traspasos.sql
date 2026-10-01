-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 06_traspasos.sql
-- Permite guardar los trámites de Traspasos Vehiculares en mc_registros, con la
-- misma cuenta, el mismo control de versiones y el mismo historial que MotoContable.
-- Se puede ejecutar más de una vez sin problema. No borra ni cambia ningún dato.
-- ════════════════════════════════════════════════════════════════════════════

begin;

alter table public.mc_registros
  drop constraint if exists mc_registros_coleccion_check;

alter table public.mc_registros
  add constraint mc_registros_coleccion_check check (coleccion in
    ('motos','movimientos','ventas','carros','contactos','metas','config','traspasos'));

commit;

-- Comprobación: debe mostrar una fila con 'traspasos' dentro de la lista.
select pg_get_constraintdef(oid) as colecciones_permitidas
from pg_constraint
where conname = 'mc_registros_coleccion_check';
