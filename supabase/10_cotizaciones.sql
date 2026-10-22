-- ════════════════════════════════════════════════════════════════════════════
-- MotoContable · 10_cotizaciones.sql
-- Permite guardar las Cotizaciones de crédito en la nube, en la misma tabla
-- mc_registros, con la misma seguridad (RLS), el mismo historial y las mismas
-- funciones de sincronización.
--
--  • Solo amplía la lista de colecciones permitidas con:
--      'cotizaciones' → las cotizaciones guardadas
--      'cot_motos'    → el catálogo de motos con su precio
--      'cot_config'   → los ajustes (empresa, planes, plazos) y los requisitos
--  • NO borra ni modifica ningún dato. Los registros existentes siguen cumpliendo
--    la regla nueva.
--  • Se puede ejecutar más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════════════════

begin;

alter table public.mc_registros
  drop constraint if exists mc_registros_coleccion_check;

alter table public.mc_registros
  add constraint mc_registros_coleccion_check check (coleccion in
    ('motos','movimientos','ventas','carros','contactos','metas','config',
     'traspasos','traspasos_borradores',
     'cotizaciones','cot_motos','cot_config'));

commit;

-- Verificación: debe mostrar la regla nueva con las 12 colecciones.
select pg_get_constraintdef(oid) as regla
from pg_constraint
where conname = 'mc_registros_coleccion_check';
